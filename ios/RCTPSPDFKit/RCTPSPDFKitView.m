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
//#import "ClipAnnotation.h"

#define VALIDATE_DOCUMENT(document, ...) { if (!document.isValid) { NSLog(@"Document is invalid."); if (self.onDocumentLoadFailed) { self.onDocumentLoadFailed(@{@"error": @"Document is invalid."}); } return __VA_ARGS__; }}

//======== PlanTrail ==============
typedef void (^imageRenderCompletionHandler)(UIImage *_Nullable, NSError *_Nullable);
NSString *clipAnnotationName = @"PLANTRAIL_CLIP_ANNOTATION";
//=================================

@interface RCTPSPDFKitViewController : PSPDFViewController
@end

@interface RCTPSPDFKitView ()<
    PSPDFDocumentDelegate, 
    PSPDFViewControllerDelegate, 
    PSPDFFlexibleToolbarContainerDelegate, 
    PSPDFAnnotationStateManagerDelegate,
    PSPDFDocumentViewControllerDelegate
  >
  @property (nonatomic, nullable) UIViewController *topController;
@end

@implementation RCTPSPDFKitView

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _pdfController = [[RCTPSPDFKitViewController alloc] init];
    _pdfController.delegate = self;
    _pdfController.annotationToolbarController.delegate = self;
    _closeButton = [[UIBarButtonItem alloc] initWithImage:[PSPDFKitGlobal imageNamed:@"x"] style:UIBarButtonItemStylePlain target:self action:@selector(closeButtonPressed:)];
    
    //PlanTrail, we need to get notified when annotationState changes so we can update our menu buttons
    [_pdfController.annotationStateManager addDelegate:self];
    _pdfController.documentViewController.delegate = self;
    _isAutomaticClipRect = YES;
    
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

- (void)
    documentViewController:(PSPDFDocumentViewController *)documentViewController 
    didChangeContinuousSpreadIndex:(CGFloat)oldContinuousSpreadIndex {

    NSLog(@"spredaIndex %f", oldContinuousSpreadIndex);
}



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

//-------------- mergeImage ----------------------------------------------------------
- (UIImage*)mergeImage:(UIImage*)first withImage:(UIImage*)second
{
    // get size of the first image
    CGImageRef firstImageRef = first.CGImage;
    CGFloat firstWidth = CGImageGetWidth(firstImageRef);
    CGFloat firstHeight = CGImageGetHeight(firstImageRef);

    // get size of the second image
    CGImageRef secondImageRef = second.CGImage;
    CGFloat secondWidth = CGImageGetWidth(secondImageRef);
    CGFloat secondHeight = CGImageGetHeight(secondImageRef);

    // build merged size
    CGSize mergedSize = CGSizeMake(MAX(firstWidth, secondWidth), firstHeight + secondHeight);

    // capture image context ref
    UIGraphicsBeginImageContext(mergedSize);

    //Draw images onto the context
    [first drawInRect:CGRectMake(0, 0, firstWidth, firstHeight)];
    [second drawInRect:CGRectMake(0, firstHeight, secondWidth, secondHeight)];
//    [second drawInRect:CGRectMake(firstWidth, 0, secondWidth, secondHeight) blendMode:kCGBlendModeNormal alpha:1.0];

    // assign context to new UIImage
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();

    // end context
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
    withPdfClipRect:(CGRect)pdfClipRect 
    atSize:(CGFloat)maxSize 
    withResolution:(CGFloat)resolution //if resolution is given, size will be omitted 
    asFileType:(NSString *)fileType //"jpg" or "png"
    includeArrows:(BOOL)includeArrows
    includeInk:(BOOL)includeInk
    includeHighlights:(BOOL)includeHighlights
    resolver:(RCTPromiseResolveBlock)resolve
    rejecter:(RCTPromiseRejectBlock)reject
    error:(NSError *_Nullable *)error 
  {
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document);

  PSPDFPageInfo *pageInfo = [document pageInfoForPageAtIndex:pageIndex];

  if(CGRectIsEmpty(pdfClipRect)) {
    //If no pdfClipRect is provided we will extract the whole page
    pdfClipRect = CGRectMake(0,0,pageInfo.size.width, pageInfo.size.height);
  }

  CGSize extractedImageSize;
  if(resolution > 0) {
    //72 dpi is default for PDFs
    CGFloat scaleFactor = resolution / 72.0;
    CGSize baseSize = (CGRectIsEmpty(pdfClipRect)) ? pageInfo.size : pdfClipRect.size;
    extractedImageSize = CGSizeMake(baseSize.width * scaleFactor, baseSize.height * scaleFactor);
  } else {
    extractedImageSize = CGSizeMake(maxSize, maxSize);
  }

  PSPDFAnnotationType annotationTypes = 
    (includeHighlights ? PSPDFAnnotationTypeHighlight : PSPDFAnnotationTypeNone) | 
    (includeArrows ? PSPDFAnnotationTypeLine : PSPDFAnnotationTypeNone ) | 
    (includeInk ? PSPDFAnnotationTypeInk : PSPDFAnnotationTypeNone);

  NSArray <PSPDFAnnotation *> *annotations = [document annotationsForPageAtIndex:pageIndex type:annotationTypes];

  PSPDFMutableRenderRequest *request = [[PSPDFMutableRenderRequest alloc] initWithDocument:document];
  request.pageIndex = pageIndex;
  request.imageScale = 1.0;
  request.imageSize = extractedImageSize;
  request.pdfRect = pdfClipRect;
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
      resolve(@{
        @"width": [NSNumber numberWithFloat:extractedImageSize.width],
        @"height": [NSNumber numberWithFloat:extractedImageSize.height]
      });
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

//-------------- setAnnotationState ----------------------------------------------------------
- (void)
    setAnnotationState:(nullable PSPDFAnnotationString)annotationString 
    variant:(nullable PSPDFAnnotationVariantString)variantString
    drawColor:(nullable UIColor*)drawColor
    lineWidth:(CGFloat)lineWidth
  {
  PSPDFAnnotationStateManager *annotationStateManager = self.pdfController.annotationStateManager;
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document);

  if([annotationStateManager.state isEqualToString:annotationString]) {
    [annotationStateManager setState:nil variant:nil];
  } else {

    [annotationStateManager setState:annotationString variant:variantString];

    if(drawColor) {
      annotationStateManager.drawColor = drawColor;
    };

    if(lineWidth) {
      annotationStateManager.lineWidth = lineWidth;
    };
  }
}

//-------------- setNavigationBarHidden ----------------------------------------------------------
- (void) setNavigationBarHidden:(BOOL)hidden {
  [self.pdfController.navigationController setNavigationBarHidden:hidden animated:NO];
}

//-------------- showOutline ----------------------------------------------------------
- (void)showOutline {
    PSPDFDocument *document = self.pdfController.document;
    VALIDATE_DOCUMENT(document);

    PSPDFOutlineViewController *outlineController = [[PSPDFOutlineViewController alloc] initWithDocument:document];
    outlineController.modalPresentationStyle = UIModalPresentationPopover;

    [self.pdfController presentViewController:outlineController options:@{ PSPDFPresentationOptionCloseButton: @YES, PSPDFPresentationOptionPopoverArrowDirections: @(UIPopoverArrowDirectionUp) } animated:YES sender:self completion:NULL];
}

//-------------- searchForString ----------------------------------------------------------
- (void) searchForString {
   [self.pdfController searchForString:nil options:nil sender:self animated:YES];
}

//----------Adjust clipAnnotationMargins on all pages------------------------
- (void) 
    adjustClipAnnotationAtAllPages
{
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document);
  PSPDFDocumentProvider *documentProvider = document.documentProviders.firstObject;
  PSPDFAnnotationManager *annotationManager = documentProvider.annotationManager;

  NSArray<PSPDFAnnotation *> *allAnnotations = [[document allAnnotationsOfType:PSPDFAnnotationTypeAll].allValues valueForKeyPath:@"@unionOfArrays.self"];
  NSMutableArray *updatedClipAnnotations = [NSMutableArray array];

  for (PSPDFAnnotation *annotation in allAnnotations) {
    NSLog(@"Checking annotation: %@ at page %d", annotation.name, annotation.pageIndex);
    if ([annotation.name isEqualToString:clipAnnotationName ]) {
      NSInteger pageIndex = annotation.pageIndex;
      PSPDFPageInfo *pageInfo = [document pageInfoForPageAtIndex:pageIndex];

        [self adjustClipAnnotationMargins:annotation pageSize:pageInfo.size];
        [updatedClipAnnotations addObject:annotation];
    }
  }

  if([updatedClipAnnotations count] > 0) {
    [annotationManager updateAnnotations:updatedClipAnnotations animated:YES];
  }             
}


//-------------- adjustClipAnnotationMargins ----------------------------------------------------------
- (BOOL) 
    adjustClipAnnotationMargins:(PSPDFAnnotation*)clipAnnotation
    pageSize:(CGSize)pageSize
{
  //But first, make sure the user hasn't shrunk the clipAnnotation so it no longer containg our highlights etc.
  if(clipAnnotation.customData && self.isAutomaticClipRect) {
    CGRect lastShapesBoundingBox = CGRectFromString(clipAnnotation.customData[@"shapesBoundingBox"]);
    clipAnnotation.boundingBox = CGRectUnion(clipAnnotation.boundingBox, lastShapesBoundingBox);
  };

  //Also adjust for top/bottom margin 
  //This helps the user to understand that header/footer is not clipable and also prohibits resize-knobs to 
  //be hidden outside of the page
  CGFloat topMargin = 0;
  CGFloat bottomMargin = 0;
  CGFloat leftMargin = 0;
  CGFloat rightMargin = 0;

  if(self.isAutomaticClipRect) {
    topMargin = self.documentMargins ? [self.documentMargins[@"top"] floatValue] : 0.0;
    bottomMargin = self.documentMargins ? [self.documentMargins[@"bottom"] floatValue] : 0.0;
    leftMargin = self.documentMargins ? [self.documentMargins[@"left"] floatValue] - 1 : 0.0;
    rightMargin = self.documentMargins ? [self.documentMargins[@"right"] floatValue] - 1 : 0.0;
  }

  CGRect clipableRectWithoutTopBottomMargins = CGRectMake(
      leftMargin, 
      bottomMargin, 
      pageSize.width - leftMargin - rightMargin, 
      pageSize.height - topMargin - bottomMargin
  );

  if(!self.isAutomaticClipRect) {
    //The original clipRect, but with full page width.
    clipAnnotation.boundingBox = CGRectMake(
        0, 
        clipAnnotation.boundingBox.origin.y, 
        pageSize.width, 
        clipAnnotation.boundingBox.size.height
    );
  }

  clipAnnotation.boundingBox = CGRectIntersection(clipAnnotation.boundingBox, clipableRectWithoutTopBottomMargins);
  return YES;
}


//-------------- updateClipAnnotation ----------------------------------------------------------
- (BOOL) 
    updateClipAnnotation:annotations
{
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, NO);
  PSPDFDocumentProvider *documentProvider = document.documentProviders.firstObject;
  PSPDFAnnotationManager *annotationManager = documentProvider.annotationManager;

  //An onAnnotationChanged will not include annotations on different pages, hence we can take pageIndex from the first object
  PSPDFAnnotation *firstAnnotation = [annotations firstObject];
  NSInteger pageIndex = firstAnnotation.pageIndex;
  PSPDFPageInfo *pageInfo = [document pageInfoForPageAtIndex:pageIndex];
  PSPDFAnnotation *clipAnnotation;

  //If only one annotation exists in the triggering annotation array and if this is our clipAnnotation, we need to bail out
  BOOL isOnlyClipAnnotations = YES;
  for (PSPDFAnnotation *loopedAnnotation in annotations) {
    if ([loopedAnnotation.name isEqualToString:clipAnnotationName ]) {
      //If this function is triggered by creation/modification of a clipAnnotation we need to bail out
      //so we don't end up in an infinite trigger-loop
      clipAnnotation = loopedAnnotation;
    } else {
      isOnlyClipAnnotations = NO;
      break;
    }
  }

  //If only clipAnnotation and margins where found in the annotation array there is no point in continuing (we would get an infinite)
  if(isOnlyClipAnnotations) {
    [self adjustClipAnnotationMargins:clipAnnotation pageSize:pageInfo.size];
    return YES;
  }

  //We won't go through the trouble of identifying impact on the boundingbox from to this very change
  //Instead we recalculate the complete boundingbox for this page
  NSArray <PSPDFAnnotation *> *allAnnotations = [document annotationsForPageAtIndex:pageIndex type:PSPDFAnnotationTypeAll];
  CGRect shapesBoundingBox = CGRectZero;

  for (PSPDFAnnotation *loopedAnnotation in allAnnotations) {
    if ([loopedAnnotation.name isEqualToString:clipAnnotationName ]) {
      clipAnnotation = loopedAnnotation;
    } else  {
      //This is all our annotations we want to calculate our shapesBoundingBox from
      //Higlight annotations has a rects-array with all selection rects. We need to use those rects instead of 
      //the annotation's boundingBox, since PSPDF adds a margin to boundingBox which we don't want
      if ([loopedAnnotation isKindOfClass:[PSPDFHighlightAnnotation class]]) {
        for (NSValue *rect in loopedAnnotation.rects) {
          shapesBoundingBox = CGRectIsEmpty(shapesBoundingBox) ? [rect CGRectValue] : CGRectUnion(shapesBoundingBox, [rect CGRectValue]);
        }
      } else {
        shapesBoundingBox = CGRectIsEmpty(shapesBoundingBox) ? loopedAnnotation.boundingBox : CGRectUnion(shapesBoundingBox, loopedAnnotation.boundingBox);
      }
    }
  }

  // If no selection exists, the selectionRect will be CGRectZero. The remaining clipAnnotation should be removed
  if(CGRectIsEmpty(shapesBoundingBox)) {
    if(clipAnnotation) {
      [document removeAnnotations:@[clipAnnotation] options:nil];
      self.snippetCount -= 1;

      //Report to JS that a box is removed so JS can decide if saveButton should be enabled
      if(self.onClipAnnotationStateChanged) {
        self.onClipAnnotationStateChanged(@{
          @"snippetCount" : @(self.snippetCount)
        });
      }
    }
    return YES;
  }

  CGRect minBoundingBox = CGRectMake(0, shapesBoundingBox.origin.y, pageInfo.size.width, shapesBoundingBox.size.height);
  if(!clipAnnotation) {
    clipAnnotation = [[PSPDFSquareAnnotation alloc] init];
    clipAnnotation.pageIndex = pageIndex;
    clipAnnotation.name = clipAnnotationName;
    clipAnnotation.boundingBox = minBoundingBox;
    clipAnnotation.borderStyle = PSPDFAnnotationBorderStyleDashed;
    clipAnnotation.lineWidth = 1;
    clipAnnotation.dashArray = @[@3,@3];
    // clipAnnotation.overlay = YES;
    [document addAnnotations:@[clipAnnotation] options:nil];
    //Report to JS that a box is created so JS can decide if annotationButtons should be enabled

    self.snippetCount += 1;

    //Report to JS that a box is removed so JS can decide if saveButton should be enabled
    if(self.onClipAnnotationStateChanged) {
      self.onClipAnnotationStateChanged(@{
        @"snippetCount" : @(self.snippetCount)
      });
    }
  } else {
    clipAnnotation.boundingBox = CGRectUnion(clipAnnotation.boundingBox, minBoundingBox);
    [annotationManager updateAnnotations:@[clipAnnotation] animated:YES];
  }

  //Store the last calculated shapesBoundingBox so we can test it if clipAnnotation is modified (i.e about 50 lines above)
  NSDictionary *customData = @{@"shapesBoundingBox": NSStringFromCGRect(clipAnnotation.boundingBox)};
  clipAnnotation.customData = customData;

  return YES;
}


//--------------------- getClipAnnotations -----------------------------
- (NSDictionary *)getClipAnnotations {
  PSPDFDocument *document = self.pdfController.document;
  VALIDATE_DOCUMENT(document, nil);

  NSArray<PSPDFAnnotation *> *allAnnotations = [[document allAnnotationsOfType:PSPDFAnnotationTypeAll].allValues valueForKeyPath:@"@unionOfArrays.self"];
  NSMutableArray *clipRects = [NSMutableArray array];
  NSMutableArray *allNonClipAnnotations = [NSMutableArray array];
  NSString *words = @"";

  for (PSPDFAnnotation *annotation in allAnnotations) {
    if ([annotation.name isEqualToString:clipAnnotationName ]) {
      NSDictionary *clipRect = @{
        @"guid": annotation.uuid,
        @"pageIndex": [NSNumber numberWithInteger:annotation.pageIndex],
        @"x": [NSNumber numberWithFloat:annotation.boundingBox.origin.x],
        @"y": [NSNumber numberWithFloat:annotation.boundingBox.origin.y],
        @"width": [NSNumber numberWithFloat:annotation.boundingBox.size.width],
        @"height": [NSNumber numberWithFloat:annotation.boundingBox.size.height],
      };
      [clipRects addObject:clipRect];
    } else {
      [allNonClipAnnotations addObject:annotation];

      //For all highlight annotations we want to collect the marked up text, line by line
      if([annotation isKindOfClass:[PSPDFHighlightAnnotation class]]) {
        NSString *markedUpString = [(PSPDFHighlightAnnotation *)annotation markedUpString];
        markedUpString = [markedUpString lowercaseString];

        //Separate any previous words collctions with a space
        if([words length] > 0) {
          words = [words stringByAppendingString:@" "];
        }

        //Replace all tabs, cr, lf, dashes, commas and periods with single spaces
        NSError *error = nil;
        NSRegularExpression *regex1 = [NSRegularExpression 
          regularExpressionWithPattern:@"\\r|\\n|\\t|-|–|\\.|\\,|(\\(.+\\))|\\d:\\d|\\d" 
          options:NSRegularExpressionCaseInsensitive 
          error:&error];

        markedUpString = [regex1 
          stringByReplacingMatchesInString:markedUpString 
          options:0 
          range:NSMakeRange(0, [markedUpString length]) 
          withTemplate:@" "
        ];

        //Get rid of any dubble spaces generated by replacing for example " -"
        NSRegularExpression *regex2 = [NSRegularExpression 
          regularExpressionWithPattern:@"\\ {2,}" 
          options:NSRegularExpressionCaseInsensitive 
          error:&error];

        markedUpString = [regex2 
          stringByReplacingMatchesInString:markedUpString 
          options:0 
          range:NSMakeRange(0, [markedUpString length]) 
          withTemplate:@" "
        ];

        words = [words stringByAppendingString:markedUpString];
      }
    }
  }

  NSArray <NSDictionary *> *nonClipAnnotationsJSON;
  if([allNonClipAnnotations count] > 0) {
    nonClipAnnotationsJSON = [RCTConvert instantJSONFromAnnotations:allNonClipAnnotations error:nil];
  }             

  return @{
    @"annotations" : nonClipAnnotationsJSON,
    @"words": words,
    @"clipRects" : clipRects
  };
}


//--------------------- delegate for annotationStateManager -----------------------------
- (void)annotationStateManager:(nonnull PSPDFAnnotationStateManager *)manager
                didChangeState:(nullable PSPDFAnnotationString)oldState
                            to:(nullable PSPDFAnnotationString)newState
                       variant:(nullable PSPDFAnnotationVariantString)oldVariant
                            to:(nullable PSPDFAnnotationVariantString)newVariant 
{
  NSLog(@"Delegate called, %@, %@", oldState, newState);
  if(self.onAnnotationManagerStateChanged) {

    //Sending string to JS-side via an NSDictionary. I got it to work with stringWithFormat 
    //There probably is a much simpler way..
    self.onAnnotationManagerStateChanged(@{
      @"oldState" : [NSString stringWithFormat: @"%@", oldState],
      @"oldVariant" : [NSString stringWithFormat: @"%@", oldVariant],
      @"newState" : [NSString stringWithFormat: @"%@", newState],
      @"newVariant" : [NSString stringWithFormat: @"%@", newVariant],
    });
  }
};

//--------------------- delegate for pdfViewController -----------------------------
- (NSArray<PSPDFMenuItem *> *)
    pdfViewController:(PSPDFViewController *)pdfController 
    shouldShowMenuItems:(NSArray<PSPDFMenuItem *> *)menuItems 
    atSuggestedTargetRect:(CGRect)rect 
    forAnnotations:(NSArray<PSPDFAnnotation *> *)annotations 
    inRect:(CGRect)annotationRect 
    onPageView:(PSPDFPageView *)pageView 
{
  
  BOOL isClipAnnotation = NO;
  for (PSPDFAnnotation *annotation in annotations) {
    if ([annotation.name isEqualToString:clipAnnotationName ]
    ) {
      isClipAnnotation = YES;
      break;
    }
  }

    // Only show Remove-menu
    return [menuItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PSPDFMenuItem *menuItem, NSDictionary *bindings) {
        NSLog(@"%@", menuItem.identifier);

        return [menuItem.identifier isEqualToString:PSPDFAnnotationMenuRemove] && !isClipAnnotation;
    }]];
}


//-------------- willShowAnnotationView ---------------------
//HÄR
- (void)
  pdfViewController:(nonnull PSPDFViewController *)pdfController
  willShowAnnotationView:(nonnull UIView<PSPDFAnnotationPresenting> *)annotationView
  onPageView:(nonnull PSPDFPageView *)pageView {
    NSLog(@"willShowAnnotationView....");
  }

//----------------------------------------------------------------------------
// - (nullable UIView<PSPDFAnnotationPresenting> *)
//     pdfViewController:(nonnull PSPDFViewController *)pdfController
//     annotationView:(nullable UIView<PSPDFAnnotationPresenting> *)annotationView
//     forAnnotation:(nonnull PSPDFAnnotation *)annotation
//     onPageView:(nonnull PSPDFPageView *)pageView
// {
  // if([annotation isKindOfClass:[PSPDFClipLineAnnotation class]]) {
  //   return annotationView;
  // } else {
    // return annotationView;
  // }
// }

//------ setIsAutomaticClipRect --------------------------------- property setter 
- (void)setIsAutomaticClipRect:(bool)isAutomaticClipRect {
  _isAutomaticClipRect = isAutomaticClipRect;
  [self adjustClipAnnotationAtAllPages];
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

  PSPDFRenderOptions *options = [[PSPDFRenderOptions alloc] init];
  options.drawBlock =^void(CGContextRef _Nonnull context, PSPDFPageIndex pageIndex, CGRect pageRect, PSPDFRenderOptions *_Nonnull options) {
      NSLog(@"...................executing drawBlock");
      if(self.documentMargins && self.isAutomaticClipRect) {
        CGFloat topMargin = self.documentMargins ? [self.documentMargins[@"top"] floatValue] : 0.0;
        CGFloat bottomMargin = self.documentMargins ? [self.documentMargins[@"bottom"] floatValue] : 0.0;
        CGFloat leftMargin = self.documentMargins ? [self.documentMargins[@"left"] floatValue] - 1 : 0.0;
        CGFloat rightMargin = self.documentMargins ? [self.documentMargins[@"right"] floatValue] - 1 : 0.0;

        CGRect leftRect = CGRectMake(0, 0, leftMargin, pageRect.size.height);
        CGRect rightRect = CGRectMake(pageRect.size.width - rightMargin, 0, leftMargin, pageRect.size.height);
        CGRect topRect = CGRectMake(leftMargin, pageRect.size.height - topMargin, pageRect.size.width - leftMargin - rightMargin, topMargin);
        CGRect bottomRect = CGRectMake(leftMargin, 0, pageRect.size.width - leftMargin - rightMargin, bottomMargin);
        CGContextSetRGBFillColor(context, 0.7, 0.7, 0.7, 0.1);
  //      CGContextSetRGBStrokeColor(context, 1.0, 0.0, 0.0, 1.0);
        CGContextFillRect(context, leftRect);  
        CGContextFillRect(context, rightRect);  
        CGContextFillRect(context, topRect);  
        CGContextFillRect(context, bottomRect);  
      }
  };

  [document setRenderOptions:options type: PSPDFRenderTypeAll];


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

  //------PlanTrail----------------------
  [self updateClipAnnotation:annotations];
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
