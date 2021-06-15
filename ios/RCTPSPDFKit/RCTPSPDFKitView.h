//
//  Copyright © 2018-2021 PSPDFKit GmbH. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY INTERNATIONAL COPYRIGHT LAW
//  AND MAY NOT BE RESOLD OR REDISTRIBUTED. USAGE IS BOUND TO THE PSPDFKIT LICENSE AGREEMENT.
//  UNAUTHORIZED REPRODUCTION OR DISTRIBUTION IS SUBJECT TO CIVIL AND CRIMINAL PENALTIES.
//  This notice may not be removed from this file.
//

#import <UIKit/UIKit.h>
#import <React/RCTComponent.h>
#import <React/RCTBridgeModule.h>

@import PSPDFKit;
@import PSPDFKitUI;

NS_ASSUME_NONNULL_BEGIN

@interface RCTPSPDFKitView: UIView

@property (nonatomic, readonly) PSPDFViewController *pdfController;
@property (nonatomic) BOOL hideNavigationBar;
@property (nonatomic, readonly) UIBarButtonItem *closeButton;
@property (nonatomic) BOOL disableDefaultActionForTappedAnnotations;
@property (nonatomic) BOOL disableAutomaticSaving;
@property (nonatomic) PSPDFPageIndex pageIndex;
@property (nonatomic, copy, nullable) NSString *annotationAuthorName;
@property (nonatomic, copy) RCTBubblingEventBlock onCloseButtonPressed;
@property (nonatomic, copy) RCTBubblingEventBlock onDocumentSaved;
@property (nonatomic, copy) RCTBubblingEventBlock onDocumentSaveFailed;
@property (nonatomic, copy) RCTBubblingEventBlock onDocumentLoadFailed;
@property (nonatomic, copy) RCTBubblingEventBlock onAnnotationTapped;
@property (nonatomic, copy) RCTBubblingEventBlock onAnnotationsChanged;
@property (nonatomic, copy) RCTBubblingEventBlock onStateChanged;
@property (nonatomic, copy, nullable) NSArray<NSString *> *availableFontNames;
@property (nonatomic, copy, nullable) NSString *selectedFontName;
@property (nonatomic) BOOL showDownloadableFonts;

/// Annotation Toolbar
- (BOOL)enterAnnotationCreationMode;
- (BOOL)exitCurrentlyActiveMode;

/// Document
- (BOOL)saveCurrentDocumentWithError:(NSError *_Nullable *)error;

///PlanTrail -------------------------------------
@property (nonatomic, copy) RCTBubblingEventBlock onAnnotationManagerStateChanged;
@property (nonatomic, copy) RCTBubblingEventBlock onClipAnnotationStateChanged;
@property (nonatomic) NSDictionary *documentMargins;
@property (nonatomic) BOOL isAutomaticClipRect;
@property (nonatomic) NSInteger snippetCount;

- (NSDictionary *) getPageSizeForPageAtIndex:(PSPDFPageIndex)pageIndex;

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)
    extractImage:(NSString*)fileGuid 
    atPageIndex:(PSPDFPageIndex)pageIndex 
    withPdfClipRect:(CGRect)pdfClipRect 
    atSize:(CGFloat)maxSize 
    withResolution:(CGFloat)resolution
    asFileType:(NSString*)fileType
    includeArrows:(BOOL)includeArrows
    includeInk:(BOOL)includeInk
    includeHighlights:(BOOL)includeHighlights
    resolver:(RCTPromiseResolveBlock)resolve 
    rejecter:(RCTPromiseRejectBlock)reject
    error:(NSError *_Nullable *)error;

- (void) 
    setAnnotationState:(nullable PSPDFAnnotationString)annotationString 
    variant:(nullable PSPDFAnnotationVariantString)variantString
    drawColor:(nullable UIColor*)drawColor
    lineWidth:(CGFloat)lineWidth;

- (void)setNavigationBarHidden:(BOOL)hidden;
- (void)showOutline;
- (void)searchForString;

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)getClipAnnotations;

///----------------------------------------------

/// Anotations
- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)getAnnotations:(PSPDFPageIndex)pageIndex type:(PSPDFAnnotationType)type error:(NSError *_Nullable *)error;
- (BOOL)addAnnotation:(id)jsonAnnotation error:(NSError *_Nullable *)error;
- (BOOL)removeAnnotationWithUUID:(NSString *)annotationUUID;
- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)getAllUnsavedAnnotationsWithError:(NSError *_Nullable *)error;
- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)getAllAnnotations:(PSPDFAnnotationType)type error:(NSError *_Nullable *)error;
- (BOOL)addAnnotations:(NSString *)jsonAnnotations error:(NSError *_Nullable *)error;

/// Forms
- (NSDictionary<NSString *, NSString *> *)getFormFieldValue:(NSString *)fullyQualifiedName;
- (BOOL)setFormFieldValue:(NSString *)value fullyQualifiedName:(NSString *)fullyQualifiedName;

// Toolbar buttons customizations
- (void)setLeftBarButtonItems:(nullable NSArray <NSString *> *)items forViewMode:(nullable NSString *) viewMode animated:(BOOL)animated;
- (void)setRightBarButtonItems:(nullable NSArray <NSString *> *)items forViewMode:(nullable NSString *) viewMode animated:(BOOL)animated;
- (NSArray <NSString *> *)getLeftBarButtonItemsForViewMode:(NSString *)viewMode;
- (NSArray <NSString *> *)getRightBarButtonItemsForViewMode:(NSString *)viewMode;

@end

NS_ASSUME_NONNULL_END
