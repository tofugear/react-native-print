
//  Created by Christopher Dro on 9/4/15.

#import "RNPrint.h"
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>

@implementation RNPrint

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

-(NSDictionary*)constantsToExport{
    return @{
             @"Duplex": @{
                     @"none": @(UIPrintInfoDuplexNone),
                     @"longEdge": @(UIPrintInfoDuplexLongEdge),
                     @"shortEdge": @(UIPrintInfoDuplexShortEdge)
                     },
             @"OutputType": @{
                     @"general": @(UIPrintInfoOutputGeneral),
                     @"photo": @(UIPrintInfoOutputPhoto),
                     @"photoGrayscale": @(UIPrintInfoOutputPhotoGrayscale)
                     }
             };
}

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(print:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    if (options[@"filePath"]){
        _filePath = [RCTConvert NSString:options[@"filePath"]];
    } else {
        _filePath = nil;
    }
    
    if (options[@"file"]){
        _filePath = [RCTConvert NSString:options[@"file"]];
    }

    if (options[@"html"]){
        _htmlString = [RCTConvert NSString:options[@"html"]];
    } else {
        _htmlString = nil;
    }
    
    if (options[@"printerURL"]){
        _printerURL = [NSURL URLWithString:[RCTConvert NSString:options[@"printerURL"]]];
        _pickedPrinter = [UIPrinter printerWithURL:_printerURL];
    } else {
        _printerURL = nil;
        _pickedPrinter = nil;
    }
    
    if(options[@"isLandscape"]) {
        _isLandscape = [[RCTConvert NSNumber:options[@"isLandscape"]] boolValue];
    }
    
    if ((_filePath && _htmlString) || (_filePath == nil && _htmlString == nil)) {
        reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@"Must provide either `html` or `filePath`. Both are either missing or passed together"));
    }
    
    UIPrintInfoDuplex duplex = UIPrintInfoDuplexNone;
    if (options[@"duplex"]){
        duplex = [(NSNumber*)(options[@"duplex"]) intValue];
    }

    UIPrintInfoOutputType outputType = UIPrintInfoOutputGeneral;
    if (options[@"outputType"]){
        outputType = [(NSNumber*)(options[@"outputType"]) intValue];
    }

    NSData *printData;
    BOOL isValidURL = NO;
    NSURL *candidateURL = [NSURL URLWithString: _filePath];
    if (candidateURL && candidateURL.scheme && candidateURL.host)
        isValidURL = YES;
    
    if (isValidURL) {
        // TODO: This needs updated to use NSURLSession dataTaskWithURL:completionHandler:
        printData = [NSData dataWithContentsOfURL:candidateURL];
    } else {
        printData = [NSData dataWithContentsOfFile: _filePath];
    }
    
    if(!_htmlString && ![UIPrintInteractionController canPrintData:printData]) {
        reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@"Unable to print this filePath"));
        return;
    }
    
    UIPrintInteractionController *printInteractionController = [UIPrintInteractionController sharedPrintController];
    printInteractionController.delegate = self;

    // Create printing info
    UIPrintInfo *printInfo = [UIPrintInfo printInfo];
    
    printInfo.outputType = outputType;
    printInfo.jobName = [_filePath lastPathComponent];
    printInfo.duplex = duplex;
    printInfo.orientation = _isLandscape? UIPrintInfoOrientationLandscape: UIPrintInfoOrientationPortrait;
    
    printInteractionController.printInfo = printInfo;
    printInteractionController.showsPageRange = YES;
    
    if (_htmlString) {
        UIMarkupTextPrintFormatter *formatter = [[UIMarkupTextPrintFormatter alloc] initWithMarkupText:_htmlString];
        printInteractionController.printFormatter = formatter;
    } else {
        printInteractionController.printingItem = printData;
    }
    
    // Completion handler
    void (^completionHandler)(UIPrintInteractionController *, BOOL, NSError *) =
    ^(UIPrintInteractionController *printController, BOOL completed, NSError *error) {
        if (!completed && error) {
            NSLog(@"Printing could not complete because of error: %@", error);
            reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(error.description));
        } else {
            resolve(completed ? printInfo.jobName : nil);
        }
    };
    
    if (_pickedPrinter) {
        [_pickedPrinter contactPrinter:^(BOOL available) {
             if (available) {
                 [printInteractionController printToPrinter:_pickedPrinter completionHandler:completionHandler];
             } else {
                 reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@"Printer not available"));
             }
         }
         ];
    } else {
        [printInteractionController presentAnimated:YES completionHandler:completionHandler];
    }
}

RCT_EXPORT_METHOD(selectPrinter:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    UIPrinterPickerController *printPicker = [UIPrinterPickerController printerPickerControllerWithInitiallySelectedPrinter: _pickedPrinter];
    
    printPicker.delegate = self;
    
    void (^completionHandler)(UIPrinterPickerController *, BOOL, NSError *) =
    ^(UIPrinterPickerController *printerPicker, BOOL userDidSelect, NSError *error) {
        if (!userDidSelect && error) {
            NSLog(@"Printing could not complete because of error: %@", error);
            reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(error.description));
        } else {
            [UIPrinterPickerController printerPickerControllerWithInitiallySelectedPrinter:printerPicker.selectedPrinter];
            if (userDidSelect) {
                _pickedPrinter = printerPicker.selectedPrinter;
                NSDictionary *printerDetails = @{
                                                 @"name" : _pickedPrinter.displayName,
                                                 @"url" : _pickedPrinter.URL.absoluteString,
                                                 };
                resolve(printerDetails);
            }
        }
    };
}

#pragma mark - UIPrintInteractionControllerDelegate

-(UIViewController*)printInteractionControllerParentViewController:(UIPrintInteractionController*)printInteractionController  {
    UIViewController *result = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    while (result.presentedViewController) {
        result = result.presentedViewController;
    }
    return result;
}


-(void)printInteractionControllerWillDismissPrinterOptions:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerDidDismissPrinterOptions:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerWillPresentPrinterOptions:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerDidPresentPrinterOptions:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerWillStartJob:(UIPrintInteractionController*)printInteractionController {}

-(void)printInteractionControllerDidFinishJob:(UIPrintInteractionController*)printInteractionController {}

- (UIPrintPaper *)printInteractionController:(UIPrintInteractionController *)printInteractionController
                                 choosePaper:(NSArray<UIPrintPaper *> *)paperList{

    UIPrintPaper* paper = nil;
    for (UIPrintPaper* apaper in paperList){
        if (CGSizeEqualToSize(apaper.paperSize, CGSizeMake(612, 792)) ){ // A4 paper size
            paper = apaper;
            break;
        }
    }
    if (!paper){
        paper = [UIPrintPaper bestPaperForPageSize:CGSizeMake(842, 595) withPapersFromArray:paperList]; // A4 pixel size
    }
    return paper;

}

+(BOOL)requiresMainQueueSetup
{
  return YES;
}

@end
