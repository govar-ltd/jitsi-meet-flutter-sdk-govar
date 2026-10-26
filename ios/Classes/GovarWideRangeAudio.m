#import "GovarWideRangeAudio.h"
#import <AVFoundation/AVFoundation.h>
#import <WebRTC/WebRTC.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import "vendor/fishhook/fishhook.h"

// Restrict interception to the pinned WebRTC image. A live unit is removed
// before disposal; every property read/write of tracked units holds stateLock.
typedef OSStatus (*UnitFn)(AudioUnit);
typedef OSStatus (*SetFn)(AudioUnit, AudioUnitPropertyID, AudioUnitScope,
                         AudioUnitElement, const void *, UInt32);
typedef BOOL (*ConfigFn)(id, SEL, RTCAudioSessionConfiguration *, NSError **);
static UnitFn systemInitialize, systemStart, systemDispose;
static SetFn systemSet;
static ConfigFn originalConfig;
static atomic_bool hooksEnabled;
static NSObject *stateLock;
static NSMutableSet<NSValue *> *units, *runningUnits;
static size_t nInit, nStart, nDispose, nSet;
static BOOL attempted, installed, candidate, wideActive, disabled;
static NSUInteger generation, starts, wideStarts, fallbacks;
static NSInteger lastBypass = -1;
static OSStatus lastPropertyStatus;
static NSString *reason = @"not_installed";
static RTCAudioSessionConfiguration *fallbackConfig;
static id routeObserver;
static dispatch_queue_t policyQueue;

static BOOL Available(void) {
    if (@available(iOS 18.2, *)) return AVAudioSession.sharedInstance.isEchoCancelledInputAvailable;
    return NO;
}
static BOOL Enabled(void) {
    if (@available(iOS 18.2, *)) return AVAudioSession.sharedInstance.isEchoCancelledInputEnabled;
    return NO;
}
static BOOL PreferWide(BOOL value) {
    if (@available(iOS 18.2, *)) {
        NSError *error = nil;
        return [AVAudioSession.sharedInstance setPrefersEchoCancelledInput:value error:&error];
    }
    return NO;
}
static BOOL VoiceUnit(AudioUnit unit) {
    AudioComponent component = unit ? AudioComponentInstanceGetComponent(unit) : NULL;
    AudioComponentDescription description = {0};
    return component && AudioComponentGetDescription(component, &description) == noErr
        && description.componentType == kAudioUnitType_Output
        && description.componentSubType == kAudioUnitSubType_VoiceProcessingIO;
}
static BOOL ApplyBypass(AudioUnit unit, BOOL bypass) {
    UInt32 value = bypass ? 1 : 0, actual = 0, size = sizeof(actual);
    OSStatus read = AudioUnitGetProperty(unit, kAUVoiceIOProperty_BypassVoiceProcessing,
                                        kAudioUnitScope_Global, 1, &actual, &size);
    OSStatus set = noErr;
    if (read != noErr || actual != value) {
        set = systemSet(unit, kAUVoiceIOProperty_BypassVoiceProcessing,
                        kAudioUnitScope_Global, 1, &value, sizeof(value));
        size = sizeof(actual);
        read = AudioUnitGetProperty(unit, kAUVoiceIOProperty_BypassVoiceProcessing,
                                    kAudioUnitScope_Global, 1, &actual, &size);
    }
    lastPropertyStatus = set != noErr ? set : read;
    lastBypass = read == noErr ? (NSInteger)actual : -1;
    return set == noErr && read == noErr && actual == value;
}
static void RestoreUnits(void) {
    for (NSValue *value in units) ApplyBypass((AudioUnit)value.pointerValue, NO);
}
// Called with stateLock held. Return to protected VPIO immediately; the queued
// session configuration follows the same RTC->state lock ordering as Jitsi.
static void FallBack(NSString *why) {
    candidate = NO; wideActive = NO; disabled = YES; fallbacks++; reason = why;
    RestoreUnits();
    NSUInteger token = generation;
    dispatch_async(policyQueue, ^{
        RTCAudioSession *rtc = RTCAudioSession.sharedInstance;
        [rtc lockForConfiguration];
        RTCAudioSessionConfiguration *restore = nil;
        @synchronized (stateLock) {
            if (token == generation && disabled && fallbackConfig) {
                RestoreUnits(); restore = fallbackConfig;
            }
        }
        if (restore) {
            PreferWide(NO);
            NSError *error = nil;
            if (![rtc setConfiguration:restore error:&error]) {
                @synchronized (stateLock) { reason = @"system_fallback_config_failed"; }
            }
        }
        [rtc unlockForConfiguration];
    });
}
static OSStatus Initialize(AudioUnit unit) {
    OSStatus result = systemInitialize(unit);
    if (!atomic_load(&hooksEnabled) || result != noErr || !VoiceUnit(unit)) return result;
    @synchronized (stateLock) {
        [units addObject:[NSValue valueWithPointer:unit]];
        if (candidate && !disabled && !ApplyBypass(unit, YES)) FallBack(@"vpio_bypass_rejected");
        else if (!candidate || disabled) ApplyBypass(unit, NO);
    }
    return result;
}
static OSStatus Start(AudioUnit unit) {
    if (!atomic_load(&hooksEnabled) || !VoiceUnit(unit)) return systemStart(unit);
    @synchronized (stateLock) {
        [units addObject:[NSValue valueWithPointer:unit]];
        if (!ApplyBypass(unit, candidate && !disabled) && candidate) FallBack(@"vpio_bypass_rejected");
    }
    OSStatus result = systemStart(unit);
    @synchronized (stateLock) {
        if (result == noErr) [runningUnits addObject:[NSValue valueWithPointer:unit]];
        starts++;
        if (result == noErr && candidate && !disabled) {
            if (Enabled() && ApplyBypass(unit, YES)) {
                wideActive = YES; wideStarts++; reason = @"wide_range_confirmed";
            } else {
                FallBack(@"echo_cancelled_input_not_enabled_after_start");
            }
        }
    }
    return result;
}
static OSStatus Dispose(AudioUnit unit) {
    if (atomic_load(&hooksEnabled)) {
        @synchronized (stateLock) { [units removeObject:[NSValue valueWithPointer:unit]];
            [runningUnits removeObject:[NSValue valueWithPointer:unit]]; }
    }
    return systemDispose(unit);
}
static OSStatus SetProperty(AudioUnit unit, AudioUnitPropertyID property,
                            AudioUnitScope scope, AudioUnitElement bus,
                            const void *data, UInt32 size) {
    if (!atomic_load(&hooksEnabled) || property != kAUVoiceIOProperty_BypassVoiceProcessing
        || scope != kAudioUnitScope_Global || !data || size != sizeof(UInt32) || !VoiceUnit(unit))
        return systemSet(unit, property, scope, bus, data, size);
    @synchronized (stateLock) {
        UInt32 value = candidate && !disabled ? 1 : 0;
        return systemSet(unit, property, scope, bus, &value, sizeof(value));
    }
}
static RTCAudioSessionConfiguration *DefaultCopy(RTCAudioSessionConfiguration *config) {
    RTCAudioSessionConfiguration *copy = [RTCAudioSessionConfiguration new];
    copy.category = config.category; copy.categoryOptions = config.categoryOptions;
    if ([config.mode isEqualToString:AVAudioSessionModeVideoChat])
        copy.categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
    copy.mode = AVAudioSessionModeDefault;
    copy.sampleRate = 48000; copy.ioBufferDuration = config.ioBufferDuration;
    copy.inputNumberOfChannels = config.inputNumberOfChannels;
    copy.outputNumberOfChannels = config.outputNumberOfChannels;
    return copy;
}
static BOOL Configure(id receiver, SEL selector, RTCAudioSessionConfiguration *config, NSError **error) {
    BOOL tryWide = NO;
    @synchronized (stateLock) {
        if (![config.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
            candidate = NO; wideActive = NO; RestoreUnits(); generation++;
        } else {
            fallbackConfig = config;
            tryWide = !disabled && [config.mode isEqualToString:AVAudioSessionModeVideoChat];
            if (!tryWide) { candidate = NO; wideActive = NO; RestoreUnits(); }
        }
    }
    if (!tryWide) return originalConfig(receiver, selector, config, error);
    // Jitsi already holds its RTC configuration lock. Never hold stateLock
    // across session setters: those may synchronously deliver route callbacks.
    BOOL accepted = NO;
    if (@available(iOS 18.2, *)) {
        NSError *trialError = nil;
        accepted = originalConfig(receiver, selector, DefaultCopy(config), &trialError)
            && Available() && PreferWide(YES);
    }
    BOOL confirmedExisting = YES;
    @synchronized (stateLock) {
        if (accepted) {
            candidate = YES; reason = @"wide_range_requested";
            // Jitsi may configure its mode after WebRTC has already started.
            if (runningUnits.count > 0) {
                for (NSValue *value in runningUnits)
                    confirmedExisting = ApplyBypass((AudioUnit)value.pointerValue, YES) && confirmedExisting;
                confirmedExisting = confirmedExisting && Enabled();
                if (confirmedExisting) { wideActive = YES; reason = @"wide_range_confirmed"; }
            }
        }
        if (!accepted || !confirmedExisting) {
            candidate = NO; wideActive = NO; disabled = YES; RestoreUnits();
            reason = accepted ? @"wide_range_not_enabled_on_running_unit" : @"wide_range_unavailable_or_rejected";
            if (accepted) fallbacks++;
        }
    }
    if (accepted && confirmedExisting) { if (error) *error = nil; return YES; }
    PreferWide(NO);
    return originalConfig(receiver, selector, config, error);
}

@implementation GovarWideRangeAudio
+ (BOOL)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stateLock = [NSObject new]; units = [NSMutableSet new]; runningUnits = [NSMutableSet new];
        policyQueue = dispatch_queue_create("online.govar.wide-range-audio", DISPATCH_QUEUE_SERIAL);
    });
    @synchronized (stateLock) {
        if (attempted) return installed;
        attempted = YES;
        Class cls = NSClassFromString(@"AudioMode");
        Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(@"setConfigWithoutLock:error:")) : NULL;
        if (!method) { reason = @"jitsi_method_missing"; return NO; }
        char *ret = method_copyReturnType(method), *arg = method_copyArgumentType(method, 3);
        BOOL compatible = method_getNumberOfArguments(method) == 4 && ret && !strcmp(ret, @encode(BOOL))
            && arg && !strcmp(arg, "^@");
        free(ret); free(arg);
        if (!compatible) { reason = @"jitsi_signature_mismatch"; return NO; }
        systemInitialize = (UnitFn)dlsym(RTLD_DEFAULT, "AudioUnitInitialize");
        systemStart = (UnitFn)dlsym(RTLD_DEFAULT, "AudioOutputUnitStart");
        systemDispose = (UnitFn)dlsym(RTLD_DEFAULT, "AudioComponentInstanceDispose");
        systemSet = (SetFn)dlsym(RTLD_DEFAULT, "AudioUnitSetProperty");
        if (!systemInitialize || !systemStart || !systemDispose || !systemSet) {
            reason = @"system_symbols_missing"; return NO;
        }
        const char *suffix = "/WebRTC.framework/WebRTC";
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name || strlen(name) < strlen(suffix) || strcmp(name + strlen(name) - strlen(suffix), suffix)) continue;
            struct rebinding bindings[] = {
                {"AudioUnitInitialize", (void *)Initialize, NULL, &nInit},
                {"AudioOutputUnitStart", (void *)Start, NULL, &nStart},
                {"AudioComponentInstanceDispose", (void *)Dispose, NULL, &nDispose},
                {"AudioUnitSetProperty", (void *)SetProperty, NULL, &nSet}
            };
            int result = rebind_symbols_image((void *)_dyld_get_image_header(i),
                                              _dyld_get_image_vmaddr_slide(i), bindings, 4);
            if (result != 0 || !nInit || !nStart || !nDispose || !nSet) { reason = @"webrtc_binding_incomplete"; return NO; }
            atomic_store(&hooksEnabled, true);
            originalConfig = (ConfigFn)method_getImplementation(method);
            method_setImplementation(method, (IMP)Configure);
            installed = YES; reason = @"ready";
            routeObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionRouteChangeNotification
                object:nil queue:nil usingBlock:^(NSNotification *note) {
                    @synchronized (stateLock) {
                        if (wideActive && (!Available() || !Enabled())) FallBack(@"wide_range_lost_after_route_change");
                    }
                }];
            return YES;
        }
        reason = @"webrtc_image_missing"; return NO;
    }
}
+ (void)beginConference {
    [self install];
    RTCAudioSession *rtc = RTCAudioSession.sharedInstance;
    [rtc lockForConfiguration];
    @synchronized (stateLock) {
        generation++; candidate = NO; wideActive = NO; disabled = NO; fallbackConfig = nil;
        RestoreUnits();
    }
    [rtc unlockForConfiguration];
}
+ (NSDictionary<NSString *, id> *)diagnostics {
    [self install];
    @synchronized (stateLock) {
        return @{@"installed": @(installed), @"policy": @"wide_range_with_system_fallback",
                 @"requested": @(candidate), @"confirmed": @(wideActive && Enabled()),
                 @"available": @(Available()), @"enabled": @(Enabled()), @"fallback": @(disabled),
                 @"reason": reason, @"voiceUnitStarts": @(starts), @"wideRangeStartsConfirmed": @(wideStarts),
                 @"fallbackCount": @(fallbacks), @"lastBypassReadback": @(lastBypass),
                 @"lastPropertyStatus": @(lastPropertyStatus)};
    }
}
@end
