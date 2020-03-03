
#import "EncoderAAC.h"
#include <pthread/pthread.h>

typedef struct {
    // pcm数据指针
    void *source;
    // pcm数据的长度
    UInt32 sourceSize;
    // 声道数
    UInt32 channelCount;
    
    AudioStreamPacketDescription *packetDescription;
}FillComplexInputParm;

typedef struct {
    AudioConverterRef converter;
    int samplerate;
    int channles;
}ConverterContext;




// AudioConverter的提供数据的回调函数
OSStatus audioConverterComplexInputDataProc(AudioConverterRef inAudioConverter,UInt32 * ioNumberDataPacket,AudioBufferList *ioData,AudioStreamPacketDescription ** outDataPacketDescription,void *inUserData){
    // ioData用来接受需要转换的pcm数据給converter进行编码
    
    FillComplexInputParm *param = (FillComplexInputParm *)inUserData;
    if (param->sourceSize <= 0) {
        *ioNumberDataPacket = 0;
        return  - 1;
    }
    ioData->mBuffers[0].mData = param->source;
    ioData->mBuffers[0].mDataByteSize = param->sourceSize;
    ioData->mBuffers[0].mNumberChannels = param->channelCount;
    *ioNumberDataPacket = 1;
    param->sourceSize = 0;
    return noErr;
}

@interface EncoderAAC ()
{
    ConverterContext *convertContext;
    dispatch_queue_t encodeQueue;
    NSMutableData    *preaudiodata;
    pthread_mutex_t               m_pMutex;
}
@end

@implementation EncoderAAC
-(instancetype)init{
    if ( self = [super init]) {
        encodeQueue = dispatch_queue_create("encode", DISPATCH_QUEUE_SERIAL);
 
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&m_pMutex, &attr);
        pthread_mutexattr_destroy(&attr);
              preaudiodata=[[NSMutableData alloc]init];
    }
    return self;
}

- (void)setaudiodata:(unsigned char *)data length:(int)length
{
    @autoreleasepool {
        
        (void)pthread_mutex_lock(&m_pMutex);
        
        NSData *dedata =  [NSData dataWithBytes:data length:length];
        
        if(data)
        {
            [ preaudiodata appendData:dedata];
        }
        
        pthread_mutex_unlock(&m_pMutex);
        usleep(50);
    }
}

- (NSData*)getaudiodata:(int)nframes
{
    (void)pthread_mutex_lock(&m_pMutex);
    NSData *subFileData = nil;
    if ([ preaudiodata length]>nframes*2)
    {
        NSRange range = NSMakeRange(0,nframes*2);
        subFileData =  [ preaudiodata  subdataWithRange:range];
        [preaudiodata replaceBytesInRange:range withBytes:NULL length:0];
    }
    pthread_mutex_unlock(&m_pMutex);
    return subFileData;
}

- (void)setUpConverter:(CMSampleBufferRef)sampleBuffer{
    // 获取audioformat的描述信息
    CMAudioFormatDescriptionRef audioFormatDes =  (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer);
    // 获取输入的asbd的信息
    AudioStreamBasicDescription inAudioStreamBasicDescription = *(CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDes));
    
    //  开始构造输出的asbd
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0};
    // 对于压缩格式必须设置为0
    outAudioStreamBasicDescription.mBitsPerChannel = 0;
    outAudioStreamBasicDescription.mBytesPerFrame = 0;
    // 设定声道数为1
    outAudioStreamBasicDescription.mChannelsPerFrame = 1;
    outAudioStreamBasicDescription.mSampleRate = 44100;
    
    // 设定输出音频的格式
    outAudioStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC;
//    outAudioStreamBasicDescription.mFormatFlags = kMPEG4Object_AAC_LC;
    
    // 填充输出的音频格式
    UInt32 size = sizeof(outAudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &outAudioStreamBasicDescription);
    
    // 创建convertcontext用来保存converter的信息
    ConverterContext *context =(ConverterContext *) malloc(sizeof(ConverterContext));
    self->convertContext = context;
    
    AudioClassDescription *desc = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC
                                                        fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
    
    OSStatus result = AudioConverterNewSpecific(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, 1, desc, &(context->converter));
    
    
    if (result == noErr) {
        // 创建编解码器成功
        AudioConverterRef converter = context->converter;
        
        // 设置编码起属性
        UInt32 temp = kAudioConverterQuality_High;
        AudioConverterSetProperty(converter, kAudioConverterCodecQuality, sizeof(temp), &temp);
        
        // 设置比特率
        UInt32 bitRate = 64000;
        result = AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, sizeof(bitRate), &bitRate);
        if (result != noErr) {
            NSLog(@"设置比特率失败");
        }
        
        UInt32 value = 0;
        size = sizeof(value);
        AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &value);
           NSLog(@"OutputPacketSize = %d",value);
    }else{
        // 创建编解码器失败
        free(context);
        context = NULL;
        NSLog(@"创建编解码器失败");
    }
    
 
    
}

- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type
                                           fromManufacturer:(UInt32)manufacturer
{
    static AudioClassDescription desc;
    
    UInt32 encoderSpecifier = type;
    OSStatus st;
    
    UInt32 size;
    st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                    sizeof(encoderSpecifier),
                                    &encoderSpecifier,
                                    &size);
    if (st) {
        NSLog(@"error getting audio format propery info: %d", (int)(st));
        return nil;
    }
    
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                sizeof(encoderSpecifier),
                                &encoderSpecifier,
                                &size,
                                descriptions);
    if (st) {
        NSLog(@"error getting audio format propery: %d", (int)(st));
        return nil;
    }
    
    for (unsigned int i = 0; i < count; i++) {
        if ((type == descriptions[i].mSubType) &&
            (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    
    return nil;
}


// 编码samplebuffer数据
-(void)encodeSmapleBuffer:(CMSampleBufferRef)sampleBuffer{
    if (!self->convertContext) {
        [self setUpConverter:sampleBuffer];
    }
    
     if (!self->convertContext)
     {
         return;
         
     }
    ConverterContext *cxt = self->convertContext;
    if (cxt )
    {
        // 从samplebuffer中提取数据
        CFRetain(sampleBuffer);
        dispatch_async(encodeQueue, ^{
            // 从samplebuffer众获取blockbuffer
            CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
            size_t  pcmLength = 0;
            char * pcmData = NULL;
            // 获取blockbuffer中的pcm数据的指针和长度
            OSStatus status =  CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &pcmLength, &pcmData);
            NSLog(@"pcmLength = %zu",pcmLength);
     
            //2048
            if (status != noErr) {
                NSLog(@"从block众获取pcm数据失败");
                CFRelease(sampleBuffer);
                return ;
            }else{
                
                [self setaudiodata:(unsigned char *)pcmData length:(int)pcmLength];
                
                NSData *audiodata =[self getaudiodata:1024];
                if (!audiodata) {
                    return ;
                }
                // 在堆区分配内存用来保存编码后的aac数据
                NSLog(@"audiodata yes");
                
                UInt32 packetSize = 1;
                AudioStreamPacketDescription *outputPacketDes = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * packetSize);
                // 使用fillcomplexinputparm来保存pcm数据
                FillComplexInputParm userParam;
                
//                                userParam.source = pcmData;
//                                userParam.sourceSize = pcmLength;
                userParam.source = (void*)audiodata.bytes;
                userParam.sourceSize = (UInt32)audiodata.length;
                userParam.channelCount = 1;
                userParam.packetDescription = NULL;

                UInt32 value = 0;
              UInt32  size = sizeof(value);
                AudioConverterGetProperty(cxt->converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &value);
                
                AudioBufferList outputBufferList;
                outputBufferList.mNumberBuffers = 1;
                
                outputBufferList.mBuffers[0].mDataByteSize = value;
                outputBufferList.mBuffers[0].mNumberChannels = 1;
                char *outputBuffer = (char *) malloc(value);
                memset(outputBuffer, 0, value);
                outputBufferList.mBuffers[0].mData = outputBuffer;
                
                
                status = AudioConverterFillComplexBuffer(convertContext->converter, audioConverterComplexInputDataProc, &userParam, &packetSize, &outputBufferList, outputPacketDes);
                free(outputPacketDes);
                outputPacketDes = NULL;
                if (status == noErr) {
                    static int64_t totoalLength = 0;
                    if (totoalLength >= 1024 * 1024 * 1) {
                        return;
                    }

                    // 获取原始的aac数据
                    NSData *rawAAC = [NSData dataWithBytes:outputBufferList.mBuffers[0].mData length:outputBufferList.mBuffers[0].mDataByteSize];
                    free(outputBuffer);
                    outputBuffer = NULL;
                    
                    //  设置adts头
                    int headerLength = 0;
                    char *packetHeader = newAdtsDataForPacketLength(rawAAC.length, 44100, 1, &headerLength);
                    NSData *adtsHeader = [NSData dataWithBytes:packetHeader length:headerLength];
                    free(packetHeader);
                    packetHeader = NULL;
                    NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
                    [fullData appendData:rawAAC];
                    if (self.delegate) {
                        [self.delegate  outPutAAC:(const char* )[fullData bytes] len:[fullData length]] ;
                    }
 
                }
                CFRelease(sampleBuffer);
                
            }
        });
    }
}
// 給aac加上adts头, packetLength 为rewaac的长度，
char *newAdtsDataForPacketLength(int packetLength,int sampleRate,int channelCout, int *ioHeaderLen){
    // adts头的长度为固定的7个字节
    int adtsLen = 7;
    // 在堆区分配7个字节的内存
    char *packet = (char*) malloc(sizeof(char) * adtsLen);
    // 选择AAC LC
    int profile = 2;
    // 选择采样率对应的下标
    int freqIdx = 4;
    // 选择声道数所对应的下标
    int chanCfg = 1;
    // 获取adts头和raw aac的总长度
    NSUInteger fullLength = adtsLen + packetLength;
    // 设置syncword
    packet[0] = 0xFF;
    packet[1] = 0xF9;
    packet[2] = (char)(((profile - 1)<<6) + (freqIdx<<2)+(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6)+(fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF)>>3);
    packet[5] = (char)(((fullLength&7)<<5)+0x1F);
    packet[6] = (char)0xFC;
    *ioHeaderLen =adtsLen;
    return packet;
}
@end
