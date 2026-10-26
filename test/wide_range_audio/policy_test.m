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
- (BOOL)setPrefersEchoCancelledInput:(BOOL)value error:(NSError **)error { if (self.rejectPreference && value) return NO; self.prefers=value; return YES; }
@end
@implementation RTCAudioSessionConfiguration
@end
@implementation RTCAudioSession
+ (instancetype)sharedInstance { static id session; if (!session) session=[self new]; return session; }
- (void)lockForConfiguration {}
- (void)unlockForConfiguration {}
- (BOOL)setConfiguration:(RTCAudioSessionConfiguration *)config error:(NSError **)error { AVAudioSession.sharedInstance.category=config.category; AVAudioSession.sharedInstance.mode=config.mode; return YES; }
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
  NSCAssert(module.received==original && initialize(&unit)==0 && start(&unit)==0 && unit.bypass==0, @"Unsupported API retains original config and AEC");
  NSCAssert(![[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Do not report wide processing");
 } else if ([scenario isEqual:@"running_first"]) {
  NSCAssert(unit.bypass==1 && [[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Existing running unit reconciled");
 } else {
  NSCAssert([module.received.mode isEqual:AVAudioSessionModeDefault] && module.received.sampleRate==48000 && module.received.categoryOptions==10, @"Wide mode preserves speaker and 48k request");
  if ([scenario isEqual:@"bypass_rejected"]) unit.rejectBypass=true;
  if ([scenario isEqual:@"read_failed"]) unit.rejectRead=true;
  if ([scenario isEqual:@"start_failed"]) unit.startStatus=-66;
  NSCAssert(initialize(&unit)==0, @"Initialization result retained");
  OSStatus result=start(&unit);
  if ([scenario isEqual:@"start_failed"]) NSCAssert(result==-66 && ![[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Start errors remain errors");
  else if ([scenario isEqual:@"not_enabled"] || [scenario isEqual:@"bypass_rejected"] || [scenario isEqual:@"read_failed"]) {
   NSCAssert(result==0 && unit.bypass==0 && ![[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Unconfirmed wide mode immediately restores VPIO");
  } else {
   NSCAssert(result==0 && unit.bypass==1 && [[GovarWideRangeAudio diagnostics][@"confirmed"] boolValue], @"Confirm API and bypass before reporting wide mode");
   NSCAssert(set(&unit,777,9,55)==0 && unit.lastProperty==777 && unit.lastValue==55, @"Unrelated property unchanged");
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
 printf("PASS: %s\n",argv[1]);
} return 0; }
