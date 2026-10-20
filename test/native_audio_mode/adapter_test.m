#import "../../ios/Classes/GovarJitsiAudioMode.h"
#import <WebRTC/WebRTC.h>
#import <AVFoundation/AVFoundation.h>
@implementation RTCAudioSessionConfiguration
@end
#if !defined(TEST_MISSING)
@interface AudioMode : NSObject
@property RTCAudioSessionConfiguration *received;
@end
@implementation AudioMode
#if defined(TEST_BAD_SIGNATURE)
- (int)setConfigWithoutLock:(id)config error:(NSError **)error { return 1; }
#else
- (BOOL)setConfigWithoutLock:(RTCAudioSessionConfiguration *)config error:(NSError **)error {
    self.received = config;
    if (error) *error = [NSError errorWithDomain:@"test" code:42 userInfo:nil];
    return NO;
}
#endif
@end
#endif
int main(void) {
    @autoreleasepool {
#if defined(TEST_MISSING) || defined(TEST_BAD_SIGNATURE)
        NSCAssert(![GovarJitsiAudioMode install], @"Unsupported Jitsi must remain unmodified");
        NSCAssert(![[GovarJitsiAudioMode diagnostics][@"installed"] boolValue], @"Failure must be observable");
#else
        NSCAssert([GovarJitsiAudioMode install] && [GovarJitsiAudioMode install], @"Idempotent install");
        AudioMode *module = [AudioMode new];
        RTCAudioSessionConfiguration *original = [RTCAudioSessionConfiguration new];
        original.category = AVAudioSessionCategoryPlayAndRecord;
        original.mode = @"AVAudioSessionModeVideoChat";
        original.categoryOptions = 2; original.sampleRate = 44100;
        original.ioBufferDuration = .01; original.inputNumberOfChannels = 1; original.outputNumberOfChannels = 2;
        NSError *error;
        NSCAssert(![module setConfigWithoutLock:original error:&error] && error.code == 42, @"Forward result and error");
        NSCAssert(module.received != original && [module.received.mode isEqual:AVAudioSessionModeMeasurement], @"Adapt a copy");
        NSCAssert([original.mode isEqual:@"AVAudioSessionModeVideoChat"] && original.sampleRate == 44100, @"Don't mutate original");
        NSCAssert(module.received.categoryOptions == 10 && module.received.inputNumberOfChannels == 1 && module.received.outputNumberOfChannels == 2 && module.received.ioBufferDuration == .01, @"Preserve routing and buffer settings");
        NSCAssert(module.received.sampleRate == 48000, @"Request 48kHz");
        original.mode = @"AVAudioSessionModeVoiceChat";
        [module setConfigWithoutLock:original error:nil];
        NSCAssert([module.received.mode isEqual:AVAudioSessionModeMeasurement] && module.received.categoryOptions == 2, @"Adapt voice mode without forcing speaker");
        original.category = @"AVAudioSessionCategoryAmbient";
        [module setConfigWithoutLock:original error:nil];
        NSCAssert(module.received == original, @"Ambient teardown unchanged");
        NSCAssert([[GovarJitsiAudioMode diagnostics][@"applications"] unsignedIntegerValue] == 2, @"Count only adapted requests");
#endif
        puts("PASS: native AudioMode adapter");
    }
}
