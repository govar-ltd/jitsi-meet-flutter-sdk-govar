#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <WebRTC/WebRTC.h>
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>
#import <unistd.h>
#import "../../ios/Classes/GovarWideRangeAudio.h"
@implementation AVAudioSession
+ (instancetype)sharedInstance { static id session; if (!session) session=[self new]; return session; }
- (BOOL)isEchoCancelledInputAvailable { return self.capable && [self.category isEqual:AVAudioSessionCategoryPlayAndRecord] && [self.mode isEqual:AVAudioSessionModeDefault]; }
- (BOOL)isEchoCancelledInputEnabled { return self.isEchoCancelledInputAvailable && self.prefers && self.honorsPreference; }
- (BOOL)setPrefersEchoCancelledInput:(BOOL)value error:(NSError **)error { if (value) self.preferenceRequests++; if (self.rejectPreference && value) { if (error) *error=[NSError errorWithDomain:@"TestPreference" code:17 userInfo:nil]; return NO; } self.prefers=value; return YES; }
@end
static RTCAudioSessionConfiguration *rtcConfig;
@implementation RTCAudioSessionConfiguration
+ (instancetype)webRTCConfiguration {
 if (!rtcConfig) { rtcConfig=[self new]; rtcConfig.category=AVAudioSessionCategoryPlayAndRecord; rtcConfig.mode=AVAudioSessionModeVoiceChat; }
 return rtcConfig;
}
+ (void)setWebRTCConfiguration:(RTCAudioSessionConfiguration *)configuration { rtcConfig=configuration; }
@end
static _Thread_local BOOL rtcLocked;
@implementation RTCAudioSession
+ (instancetype)sharedInstance { static id session; if (!session) session=[self new]; return session; }
- (void)lockForConfiguration { NSCAssert(!rtcLocked, @"RTC lock is non-recursive"); rtcLocked=YES; }
- (void)unlockForConfiguration { NSCAssert(rtcLocked, @"Lock owned before unlock"); rtcLocked=NO; }
- (BOOL)setMode:(NSString *)mode error:(NSError **)error { NSCAssert(rtcLocked, @"Mode setter requires RTC lock"); if (AVAudioSession.sharedInstance.rejectMode) { if (error) *error=[NSError errorWithDomain:@"TestMode" code:18 userInfo:nil]; return NO; } AVAudioSession.sharedInstance.mode=mode; return YES; }
- (BOOL)setConfiguration:(RTCAudioSessionConfiguration *)config error:(NSError **)error { if (AVAudioSession.sharedInstance.rejectDefaultConfiguration && [config.mode isEqual:AVAudioSessionModeDefault]) { if (error) *error=[NSError errorWithDomain:@"TestConfiguration" code:19 userInfo:nil]; return NO; } AVAudioSession.sharedInstance.category=config.category; AVAudioSession.sharedInstance.mode=AVAudioSession.sharedInstance.forceChatConfiguration ? AVAudioSessionModeVoiceChat : config.mode; return YES; }
@end
@interface AudioMode : NSObject
@property RTCAudioSessionConfiguration *received;
@end
@implementation AudioMode
- (BOOL)setConfigWithoutLock:(RTCAudioSessionConfiguration *)config error:(NSError **)error {
 self.received=config;
 return [RTCAudioSession.sharedInstance setConfiguration:config error:error];
}
@end
int main(int argc, char **argv) { @autoreleasepool {
 NSString *scenario=[NSString stringWithUTF8String:argv[1]];
 BOOL partial=[scenario isEqual:@"partial"], missing=[scenario isEqual:@"missing"];
 void *handle=missing?NULL:dlopen(argv[2],RTLD_NOW|RTLD_GLOBAL);
 NSCAssert(missing || handle, @"Mock framework loaded");
 if (partial || missing) {
  NSCAssert(![GovarWideRangeAudio install], @"Incomplete hooks cannot change policy");
  puts("PASS: absent/incomplete hook installation leaves policy unchanged"); return 0;
 }
 OSStatus (*initialize)(AudioUnit)=dlsym(handle,"RTCTestInitialize");
 OSStatus (*start)(AudioUnit)=dlsym(handle,"RTCTestStart");
 OSStatus (*dispose)(AudioUnit)=dlsym(handle,"RTCTestDispose");
 OSStatus (*set)(AudioUnit,UInt32,UInt32,UInt32)=dlsym(handle,"RTCTestSet");
 NSCAssert(initialize && start && dispose && set, @"Mock functions available");
 AVAudioSession *session=AVAudioSession.sharedInstance;
 session.capable=![scenario isEqual:@"unavailable"];
 session.honorsPreference=![scenario isEqual:@"not_enabled"];
 session.rejectPreference=[scenario isEqual:@"rejected"];
 NSCAssert([GovarWideRangeAudio install] && [GovarWideRangeAudio install], @"Idempotent install");
 [GovarWideRangeAudio beginConference];
 AudioMode *module=[AudioMode new];
 RTCAudioSessionConfiguration *original=[RTCAudioSessionConfiguration new];
 original.category=AVAudioSessionCategoryPlayAndRecord; original.mode=AVAudioSessionModeVideoChat;
 original.categoryOptions=2; original.sampleRate=44100; original.ioBufferDuration=.01;
 original.inputNumberOfChannels=1;original.outputNumberOfChannels=2;
 struct MockUnit unit={.subtype=2,.gain=1};
 if ([scenario isEqual:@"running_first"]) {
  NSCAssert(initialize(&unit)==0 && start(&unit)==0 && unit.bypass==0, @"Start standard processing before config");
 }
 NSCAssert([module setConfigWithoutLock:original error:nil], @"Call configuration succeeds");
 NSCAssert([original.mode isEqual:AVAudioSessionModeVideoChat] && original.sampleRate==44100, @"Original config untouched");
 if ([scenario isEqual:@"unavailable"] || [scenario isEqual:@"rejected"]) {
  NSCAssert(![[GovarWideRangeAudio diagnostics][@"fallback"] boolValue], @"No permanent failure before the pre-start decision");
  NSCAssert(initialize(&unit)==0 && start(&unit)==0 && unit.bypass==0, @"Unsupported API starts only with protected VPIO");
  NSCAssert([[GovarWideRangeAudio diagnostics][@"preStartRepairs"] integerValue]==1, @"Even an initially rejected preference reaches pre-start verification");
  NSCAssert([[GovarWideRangeAudio diagnostics][@"fallback"] boolValue] && ![[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Unavailable or rejected API falls back at the final decision");
  usleep(20000);
  NSCAssert([[RTCAudioSessionConfiguration webRTCConfiguration].mode isEqual:AVAudioSessionModeVoiceChat], @"Unsupported hardware restores global preference");
 } else if ([scenario isEqual:@"running_first"]) {
  NSCAssert(unit.bypass==1 && [[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Existing running unit reconciled");
 } else {
  NSCAssert([[RTCAudioSessionConfiguration webRTCConfiguration].mode isEqual:AVAudioSessionModeDefault], @"WebRTC cannot overwrite wide session with voiceChat");
  NSCAssert(([RTCAudioSessionConfiguration webRTCConfiguration].categoryOptions & 8) != 0, @"Global WebRTC template cannot silently reroute speaker calls to receiver");
  NSCAssert([module.received.mode isEqual:AVAudioSessionModeDefault] && module.received.sampleRate==48000 && module.received.categoryOptions==10, @"Wide mode preserves speaker and 48k request");
  if ([scenario isEqual:@"bypass_rejected"]) unit.rejectBypass=true;
  if ([scenario isEqual:@"read_failed"]) unit.rejectRead=true;
  if ([scenario isEqual:@"start_failed"]) unit.startStatus=-66;
  // Actual M124 initialization can hold the non-recursive session lock.
  [RTCAudioSession.sharedInstance lockForConfiguration];
  NSCAssert(initialize(&unit)==0, @"Initialization result retained");
  [RTCAudioSession.sharedInstance unlockForConfiguration];
  BOOL implicitMode=[scenario isEqual:@"implicit_voicechat"] || [scenario isEqual:@"repair_rejected"];
  if (implicitMode) { session.mode=AVAudioSessionModeVoiceChat; session.prefers=NO; }
  if ([scenario isEqual:@"repair_rejected"]) session.rejectMode=YES;
  BOOL transient=[scenario isEqual:@"transient_preference"] || [scenario isEqual:@"repeated_voicechat"] || [scenario isEqual:@"transient_config_error"];
  if (transient) {
   session.rejectPreference=[scenario isEqual:@"transient_preference"];
   session.forceChatConfiguration=[scenario isEqual:@"repeated_voicechat"];
   session.rejectDefaultConfiguration=[scenario isEqual:@"transient_config_error"];
   for (int n=0;n<3;n++) NSCAssert([module setConfigWithoutLock:original error:nil], @"Repeated Jitsi configurations preserve startup");
   NSDictionary *pending=[GovarWideRangeAudio diagnostics];
   NSCAssert([pending[@"requested"] boolValue] && ![pending[@"fallback"] boolValue] && [pending[@"preStartRepairs"] integerValue]==0, @"440 regression: early rejection cannot cancel the pre-start repair");
   if (session.rejectPreference) NSCAssert([pending[@"configurationAttempt"][@"preferenceErrorCode"] integerValue]==17, @"Record exact preference error");
   if (session.rejectDefaultConfiguration) NSCAssert([pending[@"configurationAttempt"][@"configurationErrorCode"] integerValue]==19, @"Record exact configuration error");
   session.rejectPreference=NO; session.rejectDefaultConfiguration=NO;
  }
  NSUInteger requests=session.preferenceRequests;
  OSStatus result=start(&unit);
  if ([scenario isEqual:@"start_failed"]) NSCAssert(result==-66 && unit.bypass==0 && ![[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Start errors remain errors");
  else if ([scenario isEqual:@"not_enabled"] || [scenario isEqual:@"bypass_rejected"] || [scenario isEqual:@"read_failed"] || [scenario isEqual:@"repair_rejected"]) {
   NSCAssert(result==0 && unit.bypass==0 && ![[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Unconfirmed wide mode immediately restores VPIO");
  } else {
   NSCAssert(result==0 && unit.bypass==1 && [[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Confirm API and bypass before reporting wide mode");
   if ([scenario isEqual:@"implicit_voicechat"]) {
    NSDictionary *diagnostics=[GovarWideRangeAudio diagnostics];
    NSCAssert([session.mode isEqual:AVAudioSessionModeDefault] && session.preferenceRequests>requests, @"Reapply default mode and request AFTER implicit voiceChat");
    NSCAssert([diagnostics[@"preStartRepairs"] integerValue]==1 && [diagnostics[@"modeBeforePreStartRepair"] isEqual:AVAudioSessionModeVoiceChat], @"Durable initialization order diagnostics");
   }
   if (transient) NSCAssert([[GovarWideRangeAudio diagnostics][@"preStartRepairs"] integerValue]==1 && session.preferenceRequests>requests, @"Final retry really ran and confirmed after transient rejection");
   NSCAssert(set(&unit,777,9,55)==0 && unit.lastProperty==777 && unit.lastValue==55, @"Unrelated property unchanged");
   if ([scenario isEqual:@"capture_lost"]) {
    session.honorsPreference=NO;
    NSCAssert(![[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue] && unit.bypass==0, @"Recorder status detects lost API and restores VPIO");
   }
   if ([scenario isEqual:@"route_lost"]) {
    session.honorsPreference=NO;
    [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionRouteChangeNotification object:nil];
    NSCAssert(unit.bypass==0 && ![[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Lost route immediately restores system processing");
   }
  }
 }
 NSCAssert(dispose(&unit)==0, @"Dispose result preserved");
 unsigned writes=unit.setCalls;
 // After removal, route changes cannot read or write this disposed unit.
 session.honorsPreference=NO;
 [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionRouteChangeNotification object:nil];
 usleep(20000);
 NSCAssert(unit.setCalls==writes, @"Disposed units never touched");
 original.category=@"ambient";
 NSCAssert([module setConfigWithoutLock:original error:nil], @"Teardown succeeds");
 NSCAssert([[RTCAudioSessionConfiguration webRTCConfiguration].mode isEqual:AVAudioSessionModeVoiceChat], @"Teardown restores global WebRTC preference");
 printf("PASS: %s\n",argv[1]);
} return 0; }
