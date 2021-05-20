//
//  Copyright © 2018-2021 PSPDFKit GmbH. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY INTERNATIONAL COPYRIGHT LAW
//  AND MAY NOT BE RESOLD OR REDISTRIBUTED. USAGE IS BOUND TO THE PSPDFKIT LICENSE AGREEMENT.
//  UNAUTHORIZED REPRODUCTION OR DISTRIBUTION IS SUBJECT TO CIVIL AND CRIMINAL PENALTIES.
//  This notice may not be removed from this file.
//

#import "RCTPSPDFKitView.h"
#import <React/RCTUtils.h>
#import "RCTConvert+PSPDFAnnotation.h"
#import "RCTConvert+PSPDFViewMode.h"
#import "RCTConvert+UIBarButtonItem.h"

#define VALIDATE_DOCUMENT(document, ...) { if (!document.isValid) { NSLog(@"Document is invalid."); if (self.onDocumentLoadFailed) { self.onDocumentLoadFailed(@{@"error": @"Document is invalid."}); } return __VA_ARGS__; }}

typedef void (^imageRenderCompletionHandler)(UIImage *_Nullable, NSError *_Nullable);

@interface RCTPSPDFKitViewController : PSPDFViewController
@end

@interface RCTPSPDFKitView ()<PSPDFDocumentDelegate, PSPDFViewControllerDelegate, PSPDFFlexibleToolbarContainerDelegate>

@property (nonatomic, nullable) UIViewController *topController;

@end

@implementation RCTPSPDFKitView

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _pdfController = [[RCTPSPDFKitViewController alloc] init];
    _pdfController.delegate = self;
    _pdfController.annotationToolbarController.delegate = self;
    _closeButton = [[UIBarButtonItem alloc] initWithImage:[PSPDFKitGlobal imageNamed:@"x"] style:UIBarButtonItemStylePlain target:self action:@selector(closeButtonPressed:)];
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(annotationChangedNotification:) name:PSPDFAnnotationChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(annotationChangedNotification:) name:PSPDFAnnotationsAddedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(annotationChangedNotification:) name:PSPDFAnnotationsRemovedNotification object:nil];
  }
  
  return self;
}

- (void)removeFromSuperview {
  // When the React Native `PSPDFKitView` in unmounted, we need to dismiss the `PSPDFViewController` to avoid orphan popovers.
  // See https://github.com/PSPDFKit/react-native/issues/277
  [self.pdfController dismissViewControllerAnimated:NO completion:NULL];
  [super removeFromSuperview];
}

- (void)dealloc {
  [self destroyViewControllerRelationship];
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)didMoveToWindow {
  UIViewController *controller = self.pspdf_parentViewController;
  if (controller == nil || self.window == nil || self.topController != nil) {
    return;
  }
  
  if (self.pdfController.configuration.useParentNavigationBar || self.hideNavigationBar) {
    self.topController = self.pdfController;
  } else {
    self.topController = [[PSPDFNavigationController alloc] initWithRootViewController:self.pdfController];
  }
  
  UIView *topControllerView = self.topController.view;
  topControllerView.translatesAutoresizingMaskIntoConstraints = NO;
  
  [self addSubview:topControllerView];
  [controller addChildViewController:self.topController];
  [self.topController didMoveToParentViewController:controller];
  
  [NSLayoutConstraint activateConstraints:
   @[[topControllerView.topAnchor constraintEqualToAnchor:self.topAnchor],
     [topControllerView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
     [topControllerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
     [topControllerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
   ]];
}

- (void)destroyViewControllerRelationship {
  if (self.topController.parentViewController) {
    [self.topController willMoveToParentViewController:nil];
    [self.topController removeFromParentViewController];
  }
}

- (void)closeButtonPressed:(nullable id)sender {
  if (self.onCloseButtonPressed) {
    self.onCloseButtonPressed(@{});
    
  } else {
    // try to be smart and pop if we are not displayed modally.
    BOOL shouldDismiss = YES;
    if (self.pdfController.navigationController) {
      UIViewController *topViewController = self.pdfController.navigationController.topViewController;
      UIViewController *parentViewController = self.pdfController.parentViewController;
      if ((topViewController == self.pdfController || topViewController == parentViewController) && self.pdfController.navigationController.viewControllers.count > 1) {
        [self.pdfController.navigationController popViewControllerAnimated:YES];
        shouldDismiss = NO;
      }
    }
    if (shouldDismiss) {
      [self.pdfController dismissViewControllerAnimated:YES completion:NULL];
    }
  }
}

- (UIViewController *)pspdf_parentViewController {
  UIResponder *parentResponder = self;
  while ((parentResponder = parentResponder.nextResponder)) {
    if ([parentResponder isKindOfClass:UIViewController.class]) {
      return (UIViewController *)parentResponder;
    }
  }
  return nil;
}


//====================== PlanTrail ===========================================================
//-------------- sizeFromSize ----------------------------------------------------------
- (CGSize)
    sizeFromSize:(CGSize)size 
    withLargestSide:(CGFloat)maxSize 
  {
    CGSize newCGSize;
    if (size.width > size.height) {
      newCGSize = CGSizeMake(maxSize, maxSize * size.height/size.width);
    } else {
      newCGSize = CGSizeMake(maxSize * size.width/size.height, maxSize);
    }
    return newCGSize;
}

//-------------- resizeImage ----------------------------------------------------------
- (UIImage *)
    resizeImage:(UIImage *)image 
    to:(CGFloat)maxSize 
  {
    CGSize newCGSize = [self sizeFromSize:image.size withLargestSide:maxSize];

    UIGraphicsBeginImageContextWithOptions(newCGSize, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, newCGSize.width, newCGSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();    
    UIGraphicsEndImageContext();
    return newImage;
}

//-------------- saveImageAsPng ----------------------------------------------------------
- (BOOL)
    saveImageAsPng:(UIImage*)image 
    withFileName:(NSString*)fileName 
  {
  fileName = [fileName stringByAppendingString:@".png"];

  NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
  NSString *filePath = [documentsDirectory stringByAppendingPathComponent:fileName];

  // Convert UIImage object into NSData (a wrapper for a stream of bytes) formatted according to PNG spec
  NSData *imageData = UIImagePNGRepresentation(image); 
  return [imageData writeToFile:filePath atomically:YES];
};

//-------------- saveImageAsJpg ----------------------------------------------------------
- (BOOL)
    saveImageAsJpg:(UIImage*)image 
    withFileName:(NSString*)fileName 
  {
  fileName = [fileName stringByAppendingString:@".jpg"];

  NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
  NSString *filePath = [documentsDirectory stringByAppendingPathComponent:fileName];

  NSData *imageData = UIImageJPEGRepresentation(image, 0.85f);
  return [imageData writeToFile:filePath atomically:YES];
};

//-------------- extractImage ----------------------------------------------------------
- (void)
    extractImage:(NSString*)fileGuid 
    atPageIndex:(PSPDFPageIndex)pageIndex 
    withClipRect:(CGRect)clipRect 
    atSize:(CGFloat)maxSize 
    withResolution:(CGFloat)resolution //if resolution is given, size will be omitted 
    asFileType:(NSString *)fileType //"jpg" or "png"
    resolver:(RCTPromiseResolveBlock)resolve
    rejecter:(RCTPromiseRejectBlock)reject
    error:(NSError *_Nullable *)error 
  {
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document);

  PSPDFPageInfo *pageInfo = [document pageInfoForPageAtIndex:pageIndex];

  if(CGRectIsEmpty(clipRect)) {
    //If no clipRect is provided we will extract the whole page
    clipRect = CGRectMake(0,0,pageInfo.size.width, pageInfo.size.height);
  } else {
    //Use the lower y (y2) and flip it from ViewCoordinates to PdfCoordinates
    clipRect.origin.y = pageInfo.size.height - (clipRect.origin.y + clipRect.size.height);
  }

  CGSize extractedImageSize;
  if(resolution > 0) {
    //72 dpi is default for PDFs
    CGFloat scaleFactor = resolution / 72.0;
    CGSize baseSize = (CGRectIsEmpty(clipRect)) ? pageInfo.size : clipRect.size;
    extractedImageSize = CGSizeMake(baseSize.width * scaleFactor, baseSize.height * scaleFactor);
  } else {
    extractedImageSize = CGSizeMake(maxSize, maxSize);
  }

  //Get all annotations of type Highlight, for specifying which annotations should be rendered to the image
  PSPDFAnnotationType *type = PSPDFAnnotationTypeHighlight;
  NSArray <PSPDFAnnotation *> *annotations = [document annotationsForPageAtIndex:pageIndex type:type];

  PSPDFMutableRenderRequest *request = [[PSPDFMutableRenderRequest alloc] initWithDocument:document];
  request.pageIndex = pageIndex;
  request.imageScale = 1.0;
  request.imageSize = extractedImageSize;
  request.pdfRect = clipRect;
  request.annotations = annotations;
  request.cachePolicy = PSPDFRenderRequestCachePolicyReloadIgnoringCacheData;

  // Create a render task using the `PSPDFMutableRenderRequest`.
  PSPDFRenderTask *task = [[PSPDFRenderTask alloc] initWithRequest:request error:&error];
  if (task == nil) {
      reject(@"Error", @"extractImage::PSPDfRenderTask alloc returned nil", *error);
  }
  task.delegate = self;
  task.priority = PSPDFRenderQueuePriorityUtility;

  imageRenderCompletionHandler handler = ^void(UIImage *imageOriginal, NSError *renderError) {
    if(renderError) {
      reject(@"Error", @"extractImage::PSPDFREnderTask failed", renderError);
    }

    UIImage *imageThumbnail = [self resizeImage:imageOriginal to: 120.0];
    NSString *fileNameThumbnail = [fileGuid stringByAppendingString:@"_thumbnail"];
    NSString *fileNameOriginal = [fileGuid stringByAppendingString:@"_original"];

    BOOL success;
    if([fileType isEqualToString:@"png"]) {
      success = [self saveImageAsPng:imageOriginal withFileName:fileNameOriginal] &&
        [self saveImageAsPng:imageThumbnail withFileName:fileNameThumbnail];
    } else {
      success = [self saveImageAsJpg:imageOriginal withFileName:fileNameOriginal] &&
        [self saveImageAsJpg:imageThumbnail withFileName:fileNameThumbnail];
    }

    if(success) {
      resolve(@(success));
    } else {
      reject(@"Error", @"extractImage::saveImage failed", nil);
    }
  };

  task.completionHandler = handler;
  [ PSPDFKitGlobal.sharedInstance.renderManager.renderQueue scheduleTask:task ];
}

//-------------- getPageSizeForPageAtIndex ----------------------------------------------------------
- (NSDictionary *)
    getPageSizeForPageAtIndex:(PSPDFPageIndex)pageIndex 
  {
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, nil);

  PSPDFPageInfo *pageInfo = [document pageInfoForPageAtIndex:pageIndex];
  return @{ 
    @"width" : [NSNumber numberWithDouble:pageInfo.size.width], 
    @"height" : [NSNumber numberWithDouble:pageInfo.size.height]
  };
}

//=====================================================================================================


- (BOOL)enterAnnotationCreationMode {
  [self.pdfController setViewMode:PSPDFViewModeDocument animated:YES];
  [self.pdfController.annotationToolbarController updateHostView:self container:nil viewController:self.pdfController];
  return [self.pdfController.annotationToolbarController showToolbarAnimated:YES completion:NULL];
}

- (BOOL)exitCurrentlyActiveMode {
  return [self.pdfController.annotationToolbarController hideToolbarAnimated:YES completion:NULL];
}

- (BOOL)saveCurrentDocumentWithError:(NSError *_Nullable *)error {
  return [self.pdfController.document saveWithOptions:nil error:error];
}

#pragma mark - PSPDFDocumentDelegate

- (void)pdfDocumentDidSave:(nonnull PSPDFDocument *)document {
  if (self.onDocumentSaved) {
    self.onDocumentSaved(@{});
  }
}

- (void)pdfDocument:(PSPDFDocument *)document saveDidFailWithError:(NSError *)error {
  if (self.onDocumentSaveFailed) {
    self.onDocumentSaveFailed(@{@"error": error.description});
  }
}

#pragma mark - PSPDFViewControllerDelegate

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController didTapOnAnnotation:(PSPDFAnnotation *)annotation annotationPoint:(CGPoint)annotationPoint annotationView:(UIView<PSPDFAnnotationPresenting> *)annotationView pageView:(PSPDFPageView *)pageView viewPoint:(CGPoint)viewPoint {
  if (self.onAnnotationTapped) {
    NSData *annotationData = [annotation generateInstantJSONWithError:NULL];
    NSDictionary *annotationDictionary = [NSJSONSerialization JSONObjectWithData:annotationData options:kNilOptions error:NULL];
    self.onAnnotationTapped(annotationDictionary);
  }
  return self.disableDefaultActionForTappedAnnotations;
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldSaveDocument:(nonnull PSPDFDocument *)document withOptions:(NSDictionary<PSPDFDocumentSaveOption,id> *__autoreleasing  _Nonnull * _Nonnull)options {
  return !self.disableAutomaticSaving;
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didConfigurePageView:(PSPDFPageView *)pageView forPageAtIndex:(NSInteger)pageIndex {
  [self onStateChangedForPDFViewController:pdfController pageView:pageView pageAtIndex:pageIndex];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController willBeginDisplayingPageView:(PSPDFPageView *)pageView forPageAtIndex:(NSInteger)pageIndex {
  [self onStateChangedForPDFViewController:pdfController pageView:pageView pageAtIndex:pageIndex];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didChangeDocument:(nullable PSPDFDocument *)document {
  VALIDATE_DOCUMENT(document)
}

#pragma mark - PSPDFFlexibleToolbarContainerDelegate

- (void)flexibleToolbarContainerDidShow:(PSPDFFlexibleToolbarContainer *)container {
  PSPDFPageIndex pageIndex = self.pdfController.pageIndex;
  PSPDFPageView *pageView = [self.pdfController pageViewForPageAtIndex:pageIndex];
  [self onStateChangedForPDFViewController:self.pdfController pageView:pageView pageAtIndex:pageIndex];
}

- (void)flexibleToolbarContainerDidHide:(PSPDFFlexibleToolbarContainer *)container {
  PSPDFPageIndex pageIndex = self.pdfController.pageIndex;
  PSPDFPageView *pageView = [self.pdfController pageViewForPageAtIndex:pageIndex];
  [self onStateChangedForPDFViewController:self.pdfController pageView:pageView pageAtIndex:pageIndex];
}

#pragma mark - Instant JSON

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)getAnnotations:(PSPDFPageIndex)pageIndex type:(PSPDFAnnotationType)type error:(NSError *_Nullable *)error {
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, nil);
  
  NSArray <PSPDFAnnotation *> *annotations = [document annotationsForPageAtIndex:pageIndex type:type];
  NSArray <NSDictionary *> *annotationsJSON = [RCTConvert instantJSONFromAnnotations:annotations error:error];
  return @{@"annotations" : annotationsJSON};
}

- (BOOL)addAnnotation:(id)jsonAnnotation error:(NSError *_Nullable *)error {
  NSData *data;
  if ([jsonAnnotation isKindOfClass:NSString.class]) {
    data = [jsonAnnotation dataUsingEncoding:NSUTF8StringEncoding];
  } else if ([jsonAnnotation isKindOfClass:NSDictionary.class])  {
    data = [NSJSONSerialization dataWithJSONObject:jsonAnnotation options:0 error:error];
  } else {
    NSLog(@"Invalid JSON Annotation.");
    return NO;
  }
  
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, NO)
  PSPDFDocumentProvider *documentProvider = document.documentProviders.firstObject;
  
  BOOL success = NO;
  if (data) {
    PSPDFAnnotation *annotation = [PSPDFAnnotation annotationFromInstantJSON:data documentProvider:documentProvider error:error];
    if (annotation) {
      success = [document addAnnotations:@[annotation] options:nil];
    }
  }

  if (!success) {
    NSLog(@"Failed to add annotation.");
  }
  
  return success;
}

- (BOOL)removeAnnotationWithUUID:(NSString *)annotationUUID {
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, NO)
  BOOL success = NO;
  
  NSArray<PSPDFAnnotation *> *allAnnotations = [[document allAnnotationsOfType:PSPDFAnnotationTypeAll].allValues valueForKeyPath:@"@unionOfArrays.self"];
  for (PSPDFAnnotation *annotation in allAnnotations) {
    // Remove the annotation if the uuids match.
    if ([annotation.uuid isEqualToString:annotationUUID]) {
      success = [document removeAnnotations:@[annotation] options:nil];
      break;
    }
  }
  
  if (!success) {
    NSLog(@"Failed to remove annotation.");
  }
  return success;
}

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)getAllUnsavedAnnotationsWithError:(NSError *_Nullable *)error {
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, nil)
  
  PSPDFDocumentProvider *documentProvider = document.documentProviders.firstObject;
  NSData *data = [document generateInstantJSONFromDocumentProvider:documentProvider error:error];
  NSDictionary *annotationsJSON = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:error];
  return annotationsJSON;
}

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)getAllAnnotations:(PSPDFAnnotationType)type error:(NSError *_Nullable *)error {
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, nil)

  NSArray<PSPDFAnnotation *> *annotations = [[document allAnnotationsOfType:type].allValues valueForKeyPath:@"@unionOfArrays.self"];
  NSArray <NSDictionary *> *annotationsJSON = [RCTConvert instantJSONFromAnnotations:annotations error:error];
  return @{@"annotations" : annotationsJSON};
}

- (BOOL)addAnnotations:(id)jsonAnnotations error:(NSError *_Nullable *)error {
  NSData *data;
  if ([jsonAnnotations isKindOfClass:NSString.class]) {
    data = [jsonAnnotations dataUsingEncoding:NSUTF8StringEncoding];
  } else if ([jsonAnnotations isKindOfClass:NSDictionary.class])  {
    data = [NSJSONSerialization dataWithJSONObject:jsonAnnotations options:0 error:error];
  } else {
    NSLog(@"Invalid JSON Annotations.");
    return NO;
  }
  
  PSPDFDataContainerProvider *dataContainerProvider = [[PSPDFDataContainerProvider alloc] initWithData:data];
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, NO)
  PSPDFDocumentProvider *documentProvider = document.documentProviders.firstObject;
  BOOL success = [document applyInstantJSONFromDataProvider:dataContainerProvider toDocumentProvider:documentProvider lenient:NO error:error];
  if (!success) {
    NSLog(@"Failed to add annotations.");
  }
  
  [self.pdfController reloadData];
  return success;
}

#pragma mark - Forms

- (NSDictionary<NSString *, id> *)getFormFieldValue:(NSString *)fullyQualifiedName {
  if (fullyQualifiedName.length == 0) {
    NSLog(@"Invalid fully qualified name.");
    return nil;
  }
  
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, nil)
  
  for (PSPDFFormElement *formElement in document.formParser.forms) {
    if ([formElement.fullyQualifiedFieldName isEqualToString:fullyQualifiedName]) {
      id formFieldValue = formElement.value;
      return @{@"value": formFieldValue ?: [NSNull new]};
    }
  }
  
  return @{@"error": @"Failed to get the form field value."};
}

- (BOOL)setFormFieldValue:(NSString *)value fullyQualifiedName:(NSString *)fullyQualifiedName {
  if (fullyQualifiedName.length == 0) {
    NSLog(@"Invalid fully qualified name.");
    return NO;
  }
  
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, NO)

  BOOL success = NO;
  for (PSPDFFormElement *formElement in document.formParser.forms) {
    if ([formElement.fullyQualifiedFieldName isEqualToString:fullyQualifiedName]) {
      if ([formElement isKindOfClass:PSPDFButtonFormElement.class]) {
        if ([value isEqualToString:@"selected"]) {
          [(PSPDFButtonFormElement *)formElement select];
          success = YES;
        } else if ([value isEqualToString:@"deselected"]) {
          [(PSPDFButtonFormElement *)formElement deselect];
          success = YES;
        }
      } else if ([formElement isKindOfClass:PSPDFChoiceFormElement.class]) {
        ((PSPDFChoiceFormElement *)formElement).selectedIndices = [NSIndexSet indexSetWithIndex:value.integerValue];
        success = YES;
      } else if ([formElement isKindOfClass:PSPDFTextFieldFormElement.class]) {
        formElement.contents = value;
        success = YES;
      } else if ([formElement isKindOfClass:PSPDFSignatureFormElement.class]) {
        NSLog(@"Signature form elements are not supported.");
        success = NO;
      } else {
        NSLog(@"Unsupported form element.");
        success = NO;
      }
      break;
    }
  }
  return success;
}

#pragma mark - Notifications

- (void)annotationChangedNotification:(NSNotification *)notification {
  id object = notification.object;
  NSArray <PSPDFAnnotation *> *annotations;
  if ([object isKindOfClass:NSArray.class]) {
    annotations = object;
  } else if ([object isKindOfClass:PSPDFAnnotation.class]) {
    annotations = @[object];
  } else {
    if (self.onAnnotationsChanged) {
      self.onAnnotationsChanged(@{@"error" : @"Invalid annotation error."});
    }
    return;
  }
  
  NSString *name = notification.name;
  NSString *change;
  if ([name isEqualToString:PSPDFAnnotationChangedNotification]) {
    change = @"changed";
  } else if ([name isEqualToString:PSPDFAnnotationsAddedNotification]) {
    change = @"added";
  } else if ([name isEqualToString:PSPDFAnnotationsRemovedNotification]) {
    change = @"removed";
  }
  
  NSArray <NSDictionary *> *annotationsJSON = [RCTConvert instantJSONFromAnnotations:annotations error:NULL];
  if (self.onAnnotationsChanged) {
    self.onAnnotationsChanged(@{@"change" : change, @"annotations" : annotationsJSON});
  }
}

#pragma mark - Customize the Toolbar

- (void)setLeftBarButtonItems:(nullable NSArray <NSString *> *)items forViewMode:(nullable NSString *) viewMode animated:(BOOL)animated {
  NSMutableArray *leftItems = [NSMutableArray array];
  for (NSString *barButtonItemString in items) {
    UIBarButtonItem *barButtonItem = [RCTConvert uiBarButtonItemFrom:barButtonItemString forViewController:self.pdfController];
    if (barButtonItem && ![self.pdfController.navigationItem.rightBarButtonItems containsObject:barButtonItem]) {
      [leftItems addObject:barButtonItem];
    }
  }
  
  if (viewMode.length) {
    [self.pdfController.navigationItem setLeftBarButtonItems:[leftItems copy] forViewMode:[RCTConvert PSPDFViewMode:viewMode] animated:animated];
  } else {
    [self.pdfController.navigationItem setLeftBarButtonItems:[leftItems copy] animated:animated];
  }
}

- (void)setRightBarButtonItems:(nullable NSArray <NSString *> *)items forViewMode:(nullable NSString *) viewMode animated:(BOOL)animated {
  NSMutableArray *rightItems = [NSMutableArray array];
  for (NSString *barButtonItemString in items) {
    UIBarButtonItem *barButtonItem = [RCTConvert uiBarButtonItemFrom:barButtonItemString forViewController:self.pdfController];
    if (barButtonItem && ![self.pdfController.navigationItem.leftBarButtonItems containsObject:barButtonItem]) {
      [rightItems addObject:barButtonItem];
    }
  }
  
  if (viewMode.length) {
    [self.pdfController.navigationItem setRightBarButtonItems:[rightItems copy] forViewMode:[RCTConvert PSPDFViewMode:viewMode] animated:animated];
  } else {
    [self.pdfController.navigationItem setRightBarButtonItems:[rightItems copy] animated:animated];
  }
}

- (NSArray <NSString *> *)getLeftBarButtonItemsForViewMode:(NSString *)viewMode {
  NSArray *items;
  if (viewMode.length) {
    items = [self.pdfController.navigationItem leftBarButtonItemsForViewMode:[RCTConvert PSPDFViewMode:viewMode]];
  } else {
    items = [self.pdfController.navigationItem leftBarButtonItems];
  }
  
  return [self buttonItemsStringFromUIBarButtonItems:items];
}

- (NSArray <NSString *> *)getRightBarButtonItemsForViewMode:(NSString *)viewMode {
  NSArray *items;
  if (viewMode.length) {
    items = [self.pdfController.navigationItem rightBarButtonItemsForViewMode:[RCTConvert PSPDFViewMode:viewMode]];
  } else {
    items = [self.pdfController.navigationItem rightBarButtonItems];
  }
  
  return [self buttonItemsStringFromUIBarButtonItems:items];
}

#pragma mark - Helpers

- (void)onStateChangedForPDFViewController:(PSPDFViewController *)pdfController pageView:(PSPDFPageView *)pageView pageAtIndex:(NSInteger)pageIndex {
  if (self.onStateChanged) {
    BOOL isDocumentLoaded = [pdfController.document isValid];
    PSPDFPageCount pageCount = pdfController.document.pageCount;
    BOOL isAnnotationToolBarVisible = [pdfController.annotationToolbarController isToolbarVisible];
    BOOL hasSelectedAnnotations = pageView.selectedAnnotations.count > 0;
    BOOL hasSelectedText = pageView.selectionView.selectedText.length > 0;
    BOOL isFormEditingActive = NO;
    for (PSPDFAnnotation *annotation in pageView.selectedAnnotations) {
      if ([annotation isKindOfClass:PSPDFWidgetAnnotation.class]) {
        isFormEditingActive = YES;
        break;
      }
    }
    
    self.onStateChanged(@{@"documentLoaded" : @(isDocumentLoaded),
                          @"currentPageIndex" : @(pageIndex),
                          @"pageCount" : @(pageCount),
                          @"annotationCreationActive" : @(isAnnotationToolBarVisible),
                          @"annotationEditingActive" : @(hasSelectedAnnotations),
                          @"textSelectionActive" : @(hasSelectedText),
                          @"formEditingActive" : @(isFormEditingActive)
    });
  }
}

- (NSArray <NSString *> *)buttonItemsStringFromUIBarButtonItems:(NSArray <UIBarButtonItem *> *)barButtonItems {
  NSMutableArray *barButtonItemsString = [NSMutableArray new];
  [barButtonItems enumerateObjectsUsingBlock:^(UIBarButtonItem * _Nonnull barButtonItem, NSUInteger idx, BOOL * _Nonnull stop) {
    NSString *buttonNameString = [RCTConvert stringBarButtonItemFrom:barButtonItem forViewController:self.pdfController];
    if (buttonNameString) {
      [barButtonItemsString addObject:buttonNameString];
    }
  }];
  return [barButtonItemsString copy];
}

@end

@implementation RCTPSPDFKitViewController

- (void)viewWillTransitionToSize:(CGSize)newSize withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
  [super viewWillTransitionToSize:newSize withTransitionCoordinator:coordinator];
  
  /* Workaround for internal issue 25653:
   We re-apply the current view state to workaround an issue where the last page view would be layed out incorrectly
   in single page mode and scroll per spread page trasition after device rotation.

   We do this because the `PSPDFViewController` is not embedded as recommended in
   https://pspdfkit.com/guides/ios/current/customizing-the-interface/embedding-the-pdfviewcontroller-inside-a-custom-container-view-controller
   and because React Native itself handles the React Native view.

   TL;DR: We are adding the `PSPDFViewController` to `RCTPSPDFKitView` and not to the container controller's view.
   */
  [coordinator animateAlongsideTransition:NULL completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    [self applyViewState:self.viewState animateIfPossible:NO];
  }];
}

@end
