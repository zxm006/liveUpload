#import "H264HwEncoderImpl.h"
#import "Uploader.h"
#include "uuRtmpClient.h"
#import <sys/time.h>


#include "EncoderAAC.h"

unsigned long XGetTimestamp(void)
{
#ifdef WIN32
    return timeGetTime();
#else
    struct timeval now;
    gettimeofday(&now,NULL);
    return now.tv_sec*1000+now.tv_usec/1000;
#endif
}

//UPAVStreamerDelegate/
@interface Uploader () <H264HwEncoderImplDelegate,EncoderAACDelegate>
{
    bool isinith264Encoder;
    bool contectedRtmpServer;
    NSMutableData *  SpsPpsdata;
    CRtmpClient*        m_pRtmpClient;
    EncoderAAC *m_EncoderAAC;
    int m_isnosend;
    unsigned long m_playtick;
    unsigned long m_vtick;
    unsigned long m_atick;
    AudioConverterRef m_converter;
    dispatch_queue_t  m_send_video_queue;
}

@property (nonatomic, strong) H264HwEncoderImpl *h264Encoder;
@property (nonatomic) dispatch_source_t networkStateTimer;
@end

@implementation Uploader

+ (Uploader *)sharedInstance {
    static Uploader *_sharedInstance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedInstance = [[Uploader alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    
    if (self)
    {
        m_playtick     = 0;
        m_vtick        = 0;
        m_atick        = 0;
        contectedRtmpServer = NO;
        m_EncoderAAC =[[EncoderAAC alloc]init];
        m_EncoderAAC.delegate = self;
        isinith264Encoder = NO;
        _h264Encoder = [H264HwEncoderImpl alloc];
        SpsPpsdata=[[NSMutableData alloc]init];
        [_h264Encoder initWithConfiguration];
        _h264Encoder.delegate =self;
        m_isnosend =0;
        m_send_video_queue = dispatch_queue_create("live_send_video_queue", DISPATCH_QUEUE_PRIORITY_DEFAULT);
        
    }
    return self;
}

- (void)dealloc
{
    if (self.h264Encoder)
    {
        [self.h264Encoder unint];
        self.h264Encoder=nil;
        isinith264Encoder = NO;
    }
    if(m_pRtmpClient&&contectedRtmpServer)
    {
        m_pRtmpClient->DisconnectServer();
        delete m_pRtmpClient;
        m_pRtmpClient = NULL;
    }
    
}

- (void)fwritebuff:(const char*)path data:(const char*)data  datalen:(int)datalen
{
    
    //          remove(path);
    FILE* fp_out= fopen(path,"wb");
    
    if(fp_out)
    {
        size_t  write_length =  fwrite(data,1,datalen,fp_out);
        printf("write_length = %zu\n", write_length);
        fclose(fp_out);
    }
}
- (void)outPutAAC:( const char*)data  len:(int)len
{
    m_atick = XGetTimestamp() - m_playtick;
    //                      NSLog(@"len = 编码成功%d",len);
    if(m_pRtmpClient&&contectedRtmpServer)
    {
        m_pRtmpClient->SendH264AudioPacket((unsigned char*)data,len, m_atick);
    }
}
static long x =0;

- (void)pushBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType {
    switch (sampleBufferType) {
        case RPSampleBufferTypeVideo:
        {
            x++;
            NSLog(@"RPSampleBufferTypeVideo %ld",x);
            //              sleep(10);
            CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
            
            if(!isinith264Encoder)
            {
                
                isinith264Encoder = YES;
                
                if (!m_pRtmpClient)
                {
                    m_pRtmpClient = new CRtmpClient;
                    
                    UIPasteboard *pasteboard = [UIPasteboard pasteboardWithName:@"com.aiyou.rtmp.liveurl" create:NO];
                    
                 // NSLog(@"pasteboard.string == %@",pasteboard.string);
                    if (!pasteboard.string) {
                        contectedRtmpServer = m_pRtmpClient->ConnectServer( "rtmp://115.182.73.124/live/streaming");
                        NSLog(@"rtmp://115.182.73.124/live/streaming" );
                    }
                    else
                    {
                        NSLog(@"pasteboard = %@",pasteboard.string);
                        
                        contectedRtmpServer = m_pRtmpClient->ConnectServer(  [pasteboard.string  UTF8String]);
                    }
                    //    contectedRtmpServer = m_pRtmpClient->ConnectServer("rtmp://192.168.113.185/live/linux-strea");
                    
                    //                    m_playtick = XGetTimestamp();
                }
                
                UIPasteboard *quality = [UIPasteboard pasteboardWithName:@"com.aiyou.rtmp.quality" create:NO];
                
                
                int bitrate =2500 * 1024;//rtmp://192.168.113.185/live/linux-stream0
                
                if([quality.string isEqualToString:@"0"])
                {
                    bitrate =1000 * 1024;
                }
                else  if([quality.string isEqualToString:@"1"])
                {
                    bitrate =2000 * 1024;
                }
                else   if([quality.string isEqualToString:@"2"])
                    
                {
                    bitrate =3000 * 1024;
                }
                else
                {
                    bitrate =2000 * 1024;
                }
                
                
                _h264Encoder = [H264HwEncoderImpl alloc];
                SpsPpsdata=[[NSMutableData alloc]init];
                [ self.h264Encoder initWithConfiguration];
                self.h264Encoder.delegate =self;
                
                [self.h264Encoder initEncode:640 height:360  framerate:30 bitrate:bitrate];
                isinith264Encoder =YES;
            }
            //          begin =mach_absolute_time();
            if(_h264Encoder)
                [_h264Encoder encode:imageBuffer];
            NSLog(@"videoing");
            //
            break;
        }
        case RPSampleBufferTypeAudioApp:{
            
            NSLog(@"RPSampleBufferTypeAudioApp");
            //
            //            CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
            //            size_t  pcmLength = 0;
            //            char * pcmData = NULL;
            //            // 获取blockbuffer中的pcm数据的指针和长度
            //            OSStatus status =  CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &pcmLength, &pcmData);
            //            if (status != noErr) {
            //                NSLog(@"从block众获取pcm数据失败");
            //                CFRelease(sampleBuffer);
            //                return ;
            //            }else{
            //                // 在堆区分配内存用来保存编码后的aac数据
            //                char *outputBuffer = (char *) malloc(pcmLength);
            //                memset(outputBuffer, 0, pcmLength);
            //
            //                m_atick = XGetTimestamp() - m_playtick;
            //               int ret =   m_pRtmpClient->SendH264AudioPacket((unsigned char*) outputBuffer,pcmLength, m_atick);
            //            }
            //
            //                        if (m_EncoderAAC) {
            //                            [m_EncoderAAC encodeSmapleBuffer:sampleBuffer];
            //                        }
            break;
        }
        case RPSampleBufferTypeAudioMic:
            
        {
            //                 NSLog(@"RPSampleBufferTypeAudioMic");
            //
            //                        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
            //                        size_t  pcmLength = 0;
            //                        char * pcmData = NULL;
            //                        // 获取blockbuffer中的pcm数据的指针和长度
            //                        OSStatus status =  CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &pcmLength, &pcmData);
            //                        if (status != noErr) {
            //                            NSLog(@"从block众获取pcm数据失败");
            //                            CFRelease(sampleBuffer);
            //                            return ;
            //                        }else{
            //                            // 在堆区分配内存用来保存编码后的aac数据
            //                            char *outputBuffer = (char *) malloc(pcmLength);
            //                            memset(outputBuffer, 0, pcmLength);
            //                            memcpy(outputBuffer, pcmData, pcmLength);
            //                            if(m_pRtmpClient&&contectedRtmpServer)
            //                            {
            //                            m_atick = XGetTimestamp() - m_playtick;
            //                           int ret =   m_pRtmpClient->SendH264AudioPacket((unsigned char*) outputBuffer,pcmLength, m_atick);
            //                            }
            //                            free(outputBuffer);
            //                            outputBuffer =NULL;
            //
            //                        }
            
            if (m_EncoderAAC)
            {
                //                           NSLog(@"RPSampleBufferTypeAudioMic");
                [m_EncoderAAC encodeSmapleBuffer:sampleBuffer];
            }
            //            char szBuf[4096];
            //            int  nSize = sizeof(szBuf);
            //            if ([self encoderAAC:sampleBuffer aacData:szBuf aacLen:&nSize] == YES)
            //            {
            //                // do something
            //                if(m_pRtmpClient&&contectedRtmpServer)
            //                {
            //                    int ret =   m_pRtmpClient->SendH264AudioPacket((unsigned char*)szBuf,nSize, m_atick);
            //
            //                }
            //            }
            //
            
        }
            
    }
}

- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    
    if( [SpsPpsdata  length]>0)
    {
        [SpsPpsdata setLength:0];
    }
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    NSMutableData *ByteHeader = [NSMutableData dataWithBytes:bytes length:length];
    [SpsPpsdata setData:ByteHeader];
    [SpsPpsdata appendData:sps];
    [SpsPpsdata appendData:ByteHeader];
    [SpsPpsdata appendData:pps];
    
    
    
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    NSMutableData *ByteHeader = [NSMutableData dataWithBytes:bytes length:length];
    NSMutableData *Bytedata = [[NSMutableData alloc]init];
    if (isKeyFrame)
    {
        [Bytedata setData:SpsPpsdata];
        [Bytedata appendData:ByteHeader];
        [Bytedata appendData:data];
    }
    else
    {
        [Bytedata setData:ByteHeader];
        [Bytedata appendData:data];
    }
    
    
    if(Bytedata && [Bytedata length] > 0 && m_pRtmpClient)
    {
        if (((m_isnosend == 1||m_isnosend==2)&&!isKeyFrame))
        {
            NSLog(@"丢弃p帧\n");
            usleep(20000);
            return;
        }
        else if (m_isnosend == 2 && isKeyFrame)
        {
            m_isnosend=1;
            
            NSLog(@"丢弃关键帧\n");
            usleep(20000);
            return;
        }
        else
        {
            m_isnosend =0;
        }
        
        
        m_vtick = XGetTimestamp() - m_playtick;
        dispatch_async(m_send_video_queue, ^{
            unsigned long   diffold =  XGetTimestamp();
            
            if(m_pRtmpClient&&contectedRtmpServer)
            {
                int ret = m_pRtmpClient->SendH264VideoPacket((unsigned char *)[Bytedata bytes], [ Bytedata length], 0, 0, 0, isKeyFrame, (unsigned int)m_vtick);
                NSLog(@"m_pRtmpClient == %d",ret);
                
                //            if (ret ==0) {
                //                m_pRtmpClient->reconnectServer();
                //                return ;
                //            }
                
            }
            
            unsigned long   diff  =  XGetTimestamp() - diffold;
            if(diff>100&&diff<200)
            {
                m_isnosend =1;
                //                               printf("视频发送间隔过大 diff = %ld",diff);
            }
            else if(diff>200)
            {
                
                m_isnosend =2;
            }
            
        });
        
        
    }
    
}


@end
