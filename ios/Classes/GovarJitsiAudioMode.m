#import "GovarJitsiAudioMode.h"
#import <AVFoundation/AVFoundation.h>
#import <WebRTC/WebRTC.h>
#import <objc/runtime.h>

// Jitsi 12.0.0 AudioMode.m routes initial, device selection, and route-change
// configurations through this method. Keep the original method's RTC lock and
// activation behavior. This changes our third-party SDK, never Apple classes.
typedef BOOL (*GovarSetConfig)(id, SEL, RTCAudioSessionConfiguration *, NSError **);
static GovarSetConfig originalSetConfig;
static BOOL installed;
static NSUInteger applied;
static NSString *lastOriginalMode;
static NSString *installFailure = @"not_installed";

static BOOL GovarApplyConfig(id receiver, SEL selector,
                            RTCAudioSessionConfiguration *config, NSError **error) {
    RTCAudioSessionConfiguration *chosen = config;
    if ([config.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        // Don't mutate Jitsi's shared configuration objects: preserve them for
        // route selection and allow future calls to start from their originals.
        chosen = [[RTCAudioSessionConfiguration alloc] init];
        chosen.category = config.category;
        chosen.categoryOptions = config.categoryOptions;
        // videoChat implicitly selects speaker. Measurement does not, so make
        // that same default explicit; voiceChat/earpiece requests keep theirs.
        if ([config.mode isEqualToString:AVAudioSessionModeVideoChat]) {
            chosen.categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
        }
        chosen.mode = AVAudioSessionModeMeasurement;
        chosen.sampleRate = 48000;
        chosen.ioBufferDuration = config.ioBufferDuration;
        chosen.inputNumberOfChannels = config.inputNumberOfChannels;
        chosen.outputNumberOfChannels = config.outputNumberOfChannels;
        @synchronized (GovarJitsiAudioMode.class) {
            applied++;
            lastOriginalMode = config.mode;
        }
    }
    // Forward the exact success/failure and NSError from Jitsi/WebRTC. Ambient
    // teardown configuration passes through untouched. No timer-driven setters.
    return originalSetConfig(receiver, selector, chosen, error);
}

@implementation GovarJitsiAudioMode
+ (BOOL)install {
    @synchronized (self) {
        if (installed) return YES;
        Class cls = NSClassFromString(@"AudioMode");
        SEL sel = NSSelectorFromString(@"setConfigWithoutLock:error:");
        Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (!method) { installFailure = @"jitsi_method_missing"; return NO; }
        char *ret = method_copyReturnType(method);
        char *arg2 = method_copyArgumentType(method, 2);
        char *arg3 = method_copyArgumentType(method, 3);
        BOOL compatible = method_getNumberOfArguments(method) == 4
            && ret && (!strcmp(ret, @encode(BOOL)))
            && arg2 && arg2[0] == '@' && arg3 && !strcmp(arg3, "^@");
        free(ret); free(arg2); free(arg3);
        if (!compatible) { installFailure = @"jitsi_signature_mismatch"; return NO; }
        originalSetConfig = (GovarSetConfig)method_getImplementation(method);
        method_setImplementation(method, (IMP)GovarApplyConfig);
        installed = YES;
        installFailure = @"";
        return YES;
    }
}
+ (NSDictionary<NSString *, id> *)diagnostics {
    @synchronized (self) {
        return @{@"installed": @(installed), @"applications": @(applied),
                 @"lastOriginalMode": lastOriginalMode ?: @"",
                 @"requestedMode": @"measurement", @"installFailure": installFailure};
    }
}
@end
