//
//  SampleHandler.m
//  UPUpload
//
//  Created by lingang on 2016/10/11.
//  Copyright © 2016年 upyun.com. All rights reserved.
//


#import "SampleHandler.h"
#import "Uploader.h"
#import <objc/runtime.h>
  

//  To handle samples with a subclass of RPBroadcastSampleHandler set the following in the extension's Info.plist file:
//  - RPBroadcastProcessMode should be set to RPBroadcastProcessModeSampleBuffer
//  - NSExtensionPrincipalClass should be set to this class

@interface SampleHandler ()
{
}
@end

@implementation SampleHandler



-(void)doesNotRecognizeSelector:(SEL)aSelector{
    
}

- (void)broadcastStartedWithSetupInfo:(NSDictionary<NSString *,NSObject *> *)setupInfo {
    // User has requested to start the broadcast. Setup info from the UI extension will be supplied.
    

    
}

- (void)broadcastPaused {
    // User has requested to pause the broadcast. Samples will stop being delivered.
}

- (void)broadcastResumed {
    // User has requested to resume the broadcast. Samples delivery will resume.
}

- (void)broadcastFinished {
    // User has requested to finish the broadcast.
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType {
    
    [[Uploader sharedInstance] pushBuffer:sampleBuffer withType:sampleBufferType];
}

@end
