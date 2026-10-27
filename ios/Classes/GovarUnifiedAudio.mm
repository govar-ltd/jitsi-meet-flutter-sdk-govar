#import "GovarUnifiedAudio.h"
#import "GovarDuplexCore.hpp"
#import <WebRTC/WebRTC.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#include <memory>
#include <atomic>

static NSError *Failure(NSInteger code,NSString *message) {
    return [NSError errorWithDomain:@"online.govar.unified-audio" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
@interface GovarDuplexDevice : NSObject <RTCAudioDevice> {
@public
    AudioUnit _unit;
    std::unique_ptr<GovarDuplexCore> _core;
    GovarAudioGain _microphoneGain;
    GovarAudioGain _playbackGain;
    std::atomic<uint64_t> _microphoneLimited;
    std::atomic<uint64_t> _playbackLimited;
    std::unique_ptr<GovarGrowingWav> _wav;
    std::atomic<bool> _playing, _recording, _fileWanted, _flushOnly;
    std::atomic<uint64_t> _renderCallbacks, _captureCallbacks, _callbackErrors;
    std::atomic<int> _delay;
    int16_t _input[4096];
    AudioTimeStamp _captureTime;
    id<RTCAudioDeviceDelegate> _delegate;
}
@property BOOL prepared;
@property BOOL initialized;
@property BOOL playoutInitialized;
@property BOOL recordingInitialized;
@property BOOL interrupted;
@property BOOL running;
@property BOOL freshStart;
@property BOOL sessionHeld;
@property dispatch_queue_t diskQueue;
@property dispatch_source_t diskTimer;
@property NSMutableArray *observers;
@property NSInteger lastError;
- (BOOL)prepare;
- (void)startFile:(NSString *)path completion:(void (^)(NSError *))completion;
- (void)stopFile:(void (^)(void))completion;
- (NSDictionary *)status;
@end
static GovarDuplexDevice *currentDevice;
static BOOL installed, factorySelected;
static NSString *selectionReason=@"not_installed";
static NSLock *selectionLock;
static Ivar mandatoryConstraintsIvar, optionalConstraintsIvar;
static GovarDuplexDevice *Current(void) {
    [selectionLock lock];GovarDuplexDevice *device=currentDevice;[selectionLock unlock];return device;
}

static void Processed(void *context,const int16_t *samples,size_t count) {
    GovarDuplexDevice *device=(__bridge GovarDuplexDevice *)context;
    // The callback owns this mutable core buffer; WAV and RTC get identical gained PCM.
    int16_t *gained=const_cast<int16_t *>(samples);
    device->_microphoneLimited+=device->_microphoneGain.process(gained,count);
    device->_wav->append(gained,count);
    if(device->_recording.load(std::memory_order_acquire)&&!device->_flushOnly.load()) {
        AudioBufferList list={1,{{1,(UInt32)(count*2),(void *)samples}}};
        AudioUnitRenderActionFlags flags=0;
        OSStatus s=device->_delegate.deliverRecordedData(&flags,&device->_captureTime,1,(UInt32)count,&list,NULL,nil);
        if(s!=noErr)device->_callbackErrors++;
    }
}
static OSStatus Render(void *context,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,
                       UInt32 bus,UInt32 frames,AudioBufferList *data) {
    GovarDuplexDevice *d=(__bridge GovarDuplexDevice *)context;
    if(!data || data->mNumberBuffers!=1 || !data->mBuffers[0].mData || frames>4096) return kAudioUnitErr_TooManyFramesToProcess;
    d->_renderCallbacks++;
    data->mBuffers[0].mDataByteSize=frames*2;data->mBuffers[0].mNumberChannels=1;
    memset(data->mBuffers[0].mData,0,frames*2);
    if(d->_playing.load(std::memory_order_acquire)) {
        OSStatus s=d->_delegate.getPlayoutData(flags,time,0,frames,data);
        if(s!=noErr) { memset(data->mBuffers[0].mData,0,frames*2);d->_callbackErrors++; }
    }
    d->_playbackLimited+=d->_playbackGain.process((int16_t *)data->mBuffers[0].mData,frames);
    // Reference includes playback gain/limiting: exact PCM sent to RemoteIO.
    d->_core->render((const int16_t *)data->mBuffers[0].mData,frames);
    return noErr;
}
static OSStatus Capture(void *context,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,
                        UInt32 bus,UInt32 frames,AudioBufferList *unused) {
    GovarDuplexDevice *d=(__bridge GovarDuplexDevice *)context;
    if(frames>4096)return kAudioUnitErr_TooManyFramesToProcess;
    AudioBufferList list={1,{{1,frames*2,d->_input}}};
    OSStatus s=AudioUnitRender(d->_unit,flags,time,1,frames,&list);
    if(s!=noErr) { d->_callbackErrors++;return s; }
    d->_captureCallbacks++;d->_captureTime=*time;
    d->_core->capture(d->_input,frames,d->_delay.load(std::memory_order_relaxed));
    return noErr;
}
@implementation GovarDuplexDevice
- (instancetype)init {
    self=[super init];if(!self)return nil;
    _microphoneGain=GovarAudioGain(8.f);_playbackGain=GovarAudioGain(2.f);
    _microphoneLimited=0;_playbackLimited=0;
    _core=std::make_unique<GovarDuplexCore>(Processed,(__bridge void *)self);
    _wav=std::make_unique<GovarGrowingWav>();
    _diskQueue=dispatch_queue_create("online.govar.unified-wav",DISPATCH_QUEUE_SERIAL);
    _observers=[NSMutableArray new];self.freshStart=YES;
    return self;
}
- (void)dealloc {
    if(_unit){AudioOutputUnitStop(_unit);AudioUnitUninitialize(_unit);AudioComponentInstanceDispose(_unit);}
    for(id observer in self.observers)[NSNotificationCenter.defaultCenter removeObserver:observer];
    if(self.diskTimer)dispatch_source_cancel(self.diskTimer);
}
- (BOOL)configureSession {
    RTCAudioSession *rtc=RTCAudioSession.sharedInstance;
    [rtc lockForConfiguration];
    NSError *error=nil;
    RTCAudioSessionConfiguration *config=[RTCAudioSessionConfiguration new];
    config.category=AVAudioSessionCategoryPlayAndRecord;
    config.mode=AVAudioSessionModeMeasurement;
    config.categoryOptions=AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionAllowBluetoothHFP;
    config.sampleRate=48000;config.ioBufferDuration=.01;
    config.inputNumberOfChannels=1;config.outputNumberOfChannels=1;
    BOOL okay=[rtc setConfiguration:config error:&error];
    if(okay&&!self.sessionHeld) { okay=[rtc setActive:YES error:&error];self.sessionHeld=okay; }
    [rtc unlockForConfiguration];
    if(!okay)self.lastError=error.code ?: -1;
    AVAudioSession *session=AVAudioSession.sharedInstance;
    // Include both hardware latencies and one I/O buffer of callback/framing
    // delay. AEC3 also estimates the actual render->capture echo alignment.
    _delay.store((int)std::clamp(1000*(session.inputLatency+session.outputLatency+session.IOBufferDuration),0.,500.));
    return okay;
}
- (void)releaseSession {
    if(!self.sessionHeld)return;
    RTCAudioSession *rtc=RTCAudioSession.sharedInstance;[rtc lockForConfiguration];
    [rtc setActive:NO error:nil];[rtc unlockForConfiguration];self.sessionHeld=NO;
}
- (BOOL)createUnit {
    AudioComponentDescription type={kAudioUnitType_Output,kAudioUnitSubType_RemoteIO,kAudioUnitManufacturer_Apple,0,0};
    AudioComponent component=AudioComponentFindNext(NULL,&type);
    OSStatus s=component?AudioComponentInstanceNew(component,&_unit):-1;
    UInt32 one=1,maximum=4096;
    AudioStreamBasicDescription format={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked,2,1,2,1,16,0};
    AURenderCallbackStruct output={Render,(__bridge void *)self},input={Capture,(__bridge void *)self};
    if(s==noErr)s=AudioUnitSetProperty(_unit,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,&one,sizeof(one));
    if(s==noErr)s=AudioUnitSetProperty(_unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,sizeof(format));
    if(s==noErr)s=AudioUnitSetProperty(_unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Output,1,&format,sizeof(format));
    if(s==noErr)s=AudioUnitSetProperty(_unit,kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,&maximum,sizeof(maximum));
    if(s==noErr)s=AudioUnitSetProperty(_unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&output,sizeof(output));
    if(s==noErr)s=AudioUnitSetProperty(_unit,kAudioOutputUnitProperty_SetInputCallback,kAudioUnitScope_Global,1,&input,sizeof(input));
    if(s==noErr)s=AudioUnitInitialize(_unit);
    if(s!=noErr) { self.lastError=s;if(_unit){AudioComponentInstanceDispose(_unit);_unit=NULL;}return NO; }
    return YES;
}
- (BOOL)prepare {
    BOOL okay=_core->ready()&&[self configureSession]&&[self createUnit];
    self.prepared=okay;[self releaseSession];return okay;
}
- (BOOL)startIfNeeded {
    if(self.running)return YES;
    if(self.interrupted)return YES; // Resume observer retains requested state.
    if(!self.prepared||![self configureSession])return NO;
    if(self.freshStart){_core->reset();self.freshStart=NO;}
    if(_delegate){[_delegate notifyAudioInputParametersChange];[_delegate notifyAudioOutputParametersChange];}
    OSStatus s=AudioOutputUnitStart(_unit);self.running=s==noErr;
    if(s!=noErr){self.lastError=s;[self releaseSession];}
    return self.running;
}
- (void)stopUnit {
    if(self.running) {
        AudioOutputUnitStop(_unit);self.running=NO;
        // RemoteIO can resume on a different real-time thread.
        if(_delegate){[_delegate notifyAudioInputInterrupted];[_delegate notifyAudioOutputInterrupted];}
    }
}
- (void)flushTail {
    _flushOnly=true;_core->flushTail(_delay.load());_flushOnly=false;
}
- (void)stopIfUnused {
    if(!_playing.load()&&!_recording.load()&&!_fileWanted.load()) {
        [self stopUnit];[self flushTail];self.freshStart=YES;[self releaseSession];
    }
}
- (void)rebuildForRoute {
    BOOL wanted=_playing.load()||_recording.load()||_fileWanted.load();
    if(!wanted)return;
    [self stopUnit];[self flushTail];
    [_delegate notifyAudioInputInterrupted];[_delegate notifyAudioOutputInterrupted];
    if(_unit){AudioUnitUninitialize(_unit);AudioComponentInstanceDispose(_unit);_unit=NULL;}
    _core->reset();self.prepared=[self configureSession]&&[self createUnit];
    [_delegate notifyAudioInputParametersChange];[_delegate notifyAudioOutputParametersChange];
    if(self.prepared)[self startIfNeeded];
}
- (void)observe {
    __weak GovarDuplexDevice *weak=self;
    for(NSNotificationName name in @[AVAudioSessionRouteChangeNotification,AVAudioSessionInterruptionNotification,AVAudioSessionMediaServicesWereResetNotification]) {
        id observer=[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note){
            GovarDuplexDevice *device=weak;if(!device||!device->_delegate)return;
            [device->_delegate dispatchAsync:^{
                GovarDuplexDevice *d=weak;if(!d||!d.initialized)return;
                if([note.name isEqualToString:AVAudioSessionInterruptionNotification]) {
                    BOOL began=[note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue]==AVAudioSessionInterruptionTypeBegan;
                    d.interrupted=began;
                    if(began) { [d stopUnit];[d flushTail];[d->_delegate notifyAudioInputInterrupted];[d->_delegate notifyAudioOutputInterrupted]; }
                    else [d rebuildForRoute];
                } else if([note.name isEqualToString:AVAudioSessionMediaServicesWereResetNotification]) {
                    d.sessionHeld=NO;[d rebuildForRoute];
                } else {
                    NSUInteger reason=[note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
                    if(reason==AVAudioSessionRouteChangeReasonCategoryChange) {
                        if(![AVAudioSession.sharedInstance.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
                            [d stopUnit];[d flushTail];
                        } else if(!d.running) [d rebuildForRoute];
                    } else if(reason==AVAudioSessionRouteChangeReasonNewDeviceAvailable||reason==AVAudioSessionRouteChangeReasonOldDeviceUnavailable||reason==AVAudioSessionRouteChangeReasonRouteConfigurationChange)
                        [d rebuildForRoute];
                }
            }];
        }];
        [self.observers addObject:observer];
    }
}
- (BOOL)initializeWithDelegate:(id<RTCAudioDeviceDelegate>)delegate {
    if(self.initialized)return NO;
    if(!self.prepared&&![self prepare])return NO;
    _delegate=delegate;self.initialized=YES;[self observe];
    self.diskTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,self.diskQueue);
    dispatch_source_set_timer(self.diskTimer,dispatch_time(DISPATCH_TIME_NOW,20000000),20000000,5000000);
    __weak GovarDuplexDevice *weak=self;
    dispatch_source_set_event_handler(self.diskTimer,^{ GovarDuplexDevice *d=weak;if(d)d->_wav->flush(); });
    dispatch_resume(self.diskTimer);return self.prepared;
}
- (BOOL)terminateDevice {
    _playing=false;_recording=false;[self stopUnit];[self flushTail];_fileWanted=false;
    dispatch_sync(self.diskQueue,^{self->_wav->stop();});
    if(self.diskTimer){dispatch_source_cancel(self.diskTimer);self.diskTimer=nil;}
    for(id observer in self.observers)[NSNotificationCenter.defaultCenter removeObserver:observer];[self.observers removeAllObjects];
    if(_unit){AudioUnitUninitialize(_unit);AudioComponentInstanceDispose(_unit);_unit=NULL;}
    [self releaseSession];self.prepared=NO;self.initialized=NO;self.playoutInitialized=NO;self.recordingInitialized=NO;self.interrupted=NO;self.freshStart=YES;_delegate=nil;return YES;
}
- (BOOL)isInitialized{return self.initialized;}
- (BOOL)isPlayoutInitialized{return self.playoutInitialized;}
- (BOOL)isRecordingInitialized{return self.recordingInitialized;}
- (BOOL)isPlaying{return _playing.load();}
- (BOOL)isRecording{return _recording.load();}
- (BOOL)initializePlayout{self.playoutInitialized=YES;return YES;}
- (BOOL)initializeRecording{self.recordingInitialized=YES;return YES;}
- (BOOL)startPlayout{_playing=true;if([self startIfNeeded])return YES;_playing=false;return NO;}
- (BOOL)startRecording{_recording=true;if([self startIfNeeded])return YES;_recording=false;return NO;}
- (BOOL)stopPlayout{_playing=false;[self stopIfUnused];return YES;}
- (BOOL)stopRecording{_recording=false;[self stopIfUnused];return YES;}
- (double)deviceInputSampleRate{return 48000;}
- (double)deviceOutputSampleRate{return 48000;}
- (NSInteger)inputNumberOfChannels{return 1;}
- (NSInteger)outputNumberOfChannels{return 1;}
- (NSTimeInterval)inputIOBufferDuration{NSTimeInterval d=AVAudioSession.sharedInstance.IOBufferDuration;return d>0?d:.01;}
- (NSTimeInterval)outputIOBufferDuration{return self.inputIOBufferDuration;}
- (NSTimeInterval)inputLatency{return AVAudioSession.sharedInstance.inputLatency;}
- (NSTimeInterval)outputLatency{return AVAudioSession.sharedInstance.outputLatency;}
- (void)startFile:(NSString *)path completion:(void (^)(NSError *))completion {
    if(!_delegate){completion(Failure(1,@"Unified audio device is not initialized"));return;}
    [_delegate dispatchAsync:^{
        if(self->_fileWanted.load()) { dispatch_async(dispatch_get_main_queue(),^{completion(Failure(2,@"Capture already active"));});return; }
        __block BOOL okay=NO;
        dispatch_sync(self.diskQueue,^{okay=self->_wav->start(path.fileSystemRepresentation);});
        self->_fileWanted=okay;
        if(okay)okay=[self startIfNeeded];
        if(!okay){self->_fileWanted=false;dispatch_sync(self.diskQueue,^{self->_wav->stop();});}
        dispatch_async(dispatch_get_main_queue(),^{completion(okay?nil:Failure(3,@"Unified WAV start failed"));});
    }];
}
- (void)stopFile:(void (^)(void))completion {
    if(!_delegate){dispatch_sync(self.diskQueue,^{self->_wav->stop();});_fileWanted=false;completion();return;}
    [_delegate dispatchAsync:^{
        // Stop callbacks before flushing a partial 10 ms frame. No microphone
        // samples already captured are lost from the final WAV tail.
        BOOL restart=self.running;[self stopUnit];[self flushTail];
        self->_fileWanted=false;dispatch_sync(self.diskQueue,^{self->_wav->stop();});
        if(restart&&(self->_playing.load()||self->_recording.load()))[self startIfNeeded];else[self releaseSession];
        dispatch_async(dispatch_get_main_queue(),completion);
    }];
}
- (NSDictionary *)status {
    return @{@"deviceInitialized":@(self.initialized),@"unitRunning":@(self.running),
             @"recording":@(_wav->enabled.load()&&self.running),@"fileWanted":@(_fileWanted.load()),@"seconds":@(_wav->seconds()),
             @"renderCallbacks":@(_renderCallbacks.load()),@"captureCallbacks":@(_captureCallbacks.load()),
             @"renderSamples":@(_core->renderSamples.load()),@"captureSamples":@(_core->captureSamples.load()),
             @"processedSamples":@(_core->processedSamples.load()),@"apmErrors":@(_core->errors.load()),
             @"callbackErrors":@(_callbackErrors.load()),@"wavError":@(_wav->error.load()),@"wavOverruns":@(_wav->overruns.load()),
             @"delayMs":@(_delay.load()),@"lastDeviceError":@(self.lastError),
             @"sampleRate":@48000,@"fileSampleRate":@48000,@"fileChannels":@1,
             @"aec":@YES,@"ns":@NO,@"agc":@NO,@"hpf":@NO,
             @"gainPolicy":@"post_aec_mic8_playback2_peak_limiter",
             @"microphoneGainDb":@18.0618,@"playbackGainDb":@6.0206,
             @"microphoneLimitedSamples":@(_microphoneLimited.load()),@"playbackLimitedSamples":@(_playbackLimited.load()),
             @"audioUnit":@"RemoteIO",@"wavSource":@"same_post_aec_pcm_as_webrtc"};
}
@end

typedef id (*FactoryFn)(id __attribute__((ns_consumed)),SEL,id,id,id) __attribute__((ns_returns_retained));
typedef BOOL (*ModeFn)(id,SEL,RTCAudioSessionConfiguration *,NSError **);
typedef RTCAudioSource *(*SourceFn)(id,SEL,RTCMediaConstraints *);
static FactoryFn originalFactory;
static ModeFn originalMode;
static SourceFn originalSource;
static BOOL Mode(id self,SEL selector,RTCAudioSessionConfiguration *config,NSError **error) {
    GovarDuplexDevice *device=Current();
    if(device.prepared&&[config.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        RTCAudioSessionConfiguration *copy=[RTCAudioSessionConfiguration new];
        copy.category=config.category;copy.categoryOptions=config.categoryOptions|AVAudioSessionCategoryOptionDefaultToSpeaker;
        copy.mode=AVAudioSessionModeMeasurement;copy.sampleRate=48000;copy.ioBufferDuration=.01;
        copy.inputNumberOfChannels=1;copy.outputNumberOfChannels=1;
        return originalMode(self,selector,copy,error);
    }
    return originalMode(self,selector,config,error);
}
static id Factory(id self __attribute__((ns_consumed)),SEL selector,id encoder,id decoder,id suppliedDevice) __attribute__((ns_returns_retained));
static id Factory(id self __attribute__((ns_consumed)),SEL selector,id encoder,id decoder,id suppliedDevice) {
    // Never replace an explicitly supplied device, or request microphone
    // permission early. Govar's call permission gate grants access first.
    if(suppliedDevice||AVAudioSession.sharedInstance.recordPermission!=AVAudioSessionRecordPermissionGranted) {
        [selectionLock lock];factorySelected=YES;currentDevice=nil;
        selectionReason=suppliedDevice?@"existing_custom_device_preserved":@"microphone_not_authorized_using_stock";
        [selectionLock unlock];return originalFactory(self,selector,encoder,decoder,suppliedDevice);
    }
    GovarDuplexDevice *device=[GovarDuplexDevice new];
    BOOL ready=[device prepare];
    [selectionLock lock];factorySelected=YES;currentDevice=ready?device:nil;
    selectionReason=ready?@"remote_io_aec3_selected":@"remote_io_preparation_failed_using_stock";[selectionLock unlock];
    if(!ready)return originalFactory(self,selector,encoder,decoder,nil);
    return originalFactory(self,selector,encoder,decoder,device);
}
static RTCAudioSource *Source(id self,SEL selector,RTCMediaConstraints *constraints) {
    if(Current().prepared) {
        NSDictionary *off=@{@"googEchoCancellation":@"false",@"googAutoGainControl":@"false",@"googNoiseSuppression":@"false",@"googHighpassFilter":@"false"};
        // Pinned M124 stores both original dictionaries in these checked
        // Objective-C ivars. Preserve network-adaptor and other source options;
        // override only the four processing switches handled by our AEC3.
        NSDictionary *mandatory=constraints?object_getIvar(constraints,mandatoryConstraintsIvar):nil;
        NSDictionary *optional=constraints?object_getIvar(constraints,optionalConstraintsIvar):nil;
        if((mandatory&&![mandatory isKindOfClass:NSDictionary.class])||(optional&&![optional isKindOfClass:NSDictionary.class]))
            return originalSource(self,selector,constraints);
        NSMutableDictionary *m=[mandatory mutableCopy]?:[NSMutableDictionary new];
        NSMutableDictionary *o=[optional mutableCopy]?:[NSMutableDictionary new];
        for(NSString *key in off){if(m[key])m[key]=off[key];o[key]=off[key];}
        constraints=[[RTCMediaConstraints alloc] initWithMandatoryConstraints:m optionalConstraints:o];
    }
    return originalSource(self,selector,constraints);
}
@implementation GovarUnifiedAudio
+ (BOOL)install {
    static dispatch_once_t once;dispatch_once(&once,^{
        selectionLock=[NSLock new];
        Method factory=class_getInstanceMethod(RTCPeerConnectionFactory.class,@selector(initWithEncoderFactory:decoderFactory:audioDevice:));
        Method source=class_getInstanceMethod(RTCPeerConnectionFactory.class,@selector(audioSourceWithConstraints:));
        Method mode=class_getInstanceMethod(NSClassFromString(@"AudioMode"),NSSelectorFromString(@"setConfigWithoutLock:error:"));
        mandatoryConstraintsIvar=class_getInstanceVariable(RTCMediaConstraints.class,"_mandatory");
        optionalConstraintsIvar=class_getInstanceVariable(RTCMediaConstraints.class,"_optional");
        if(!factory||!source||!mode||!mandatoryConstraintsIvar||!optionalConstraintsIvar||method_getNumberOfArguments(factory)!=5||method_getNumberOfArguments(source)!=3||method_getNumberOfArguments(mode)!=4){selectionReason=@"integration_method_missing_using_stock";factorySelected=YES;return;}
        originalFactory=(FactoryFn)method_getImplementation(factory);originalSource=(SourceFn)method_getImplementation(source);originalMode=(ModeFn)method_getImplementation(mode);
        method_setImplementation(factory,(IMP)Factory);method_setImplementation(source,(IMP)Source);method_setImplementation(mode,(IMP)Mode);
        installed=YES;selectionReason=@"waiting_for_factory";
    });return installed;
}
+ (NSDictionary<NSString *,id> *)diagnostics {
    [self install];[selectionLock lock];GovarDuplexDevice *device=currentDevice;
    BOOL selected=factorySelected;NSString *why=selectionReason;[selectionLock unlock];
    NSMutableDictionary *d=[NSMutableDictionary dictionaryWithDictionary:device?[device status]:@{}];
    d[@"installed"]=@(installed);d[@"factorySelected"]=@(selected);d[@"customDevice"]=@(device!=nil);d[@"selectionReason"]=why;
    d[@"audioPolicy"]=device?@"unified_remote_io_aec3":@"stock_system_aec_fallback";
    return d;
}
+ (void)startRecordingAtPath:(NSString *)path completion:(void (^)(NSError *))completion {
    GovarDuplexDevice *device=Current();
    if(!device){completion(Failure(4,@"Custom audio device unavailable"));return;}[device startFile:path completion:completion];
}
+ (void)stopRecordingWithCompletion:(void (^)(void))completion {
    GovarDuplexDevice *device=Current();if(!device){completion();return;}[device stopFile:completion];
}
@end
