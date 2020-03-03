//
//  EN.h
//  UPLiveSDKDemo
//
//  Created by zhangxinming on 2017/6/9.
//  Copyright © 2017年 upyun.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@protocol EncoderAACDelegate <NSObject>
- (void)outPutAAC:( const char*)data  len:(int)len ;
@end

@interface EncoderAAC : NSObject
{
    
}
@property (weak,nonatomic)  id<EncoderAACDelegate >delegate;

-(void)encodeSmapleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
