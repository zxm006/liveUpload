//
//  Uploader.h
//  ReplayKitForLiving
//
//  Created by lingang on 2016/10/11.
//  Copyright © 2016年 upyun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ReplayKit/ReplayKit.h>

#define UPYUN_APP_EXTENSIONS

@interface Uploader : NSObject


+ (Uploader *)sharedInstance;

- (void)pushBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType;
@end
