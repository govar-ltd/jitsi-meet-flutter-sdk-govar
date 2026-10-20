#import "GovarVoiceProcessingBypass.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import "vendor/fishhook/fishhook.h"

typedef OSStatus (*InitializeFn)(AudioUnit);
typedef OSStatus (*SetPropertyFn)(AudioUnit, AudioUnitPropertyID, AudioUnitScope,
                                 AudioUnitElement, const void *, UInt32);
static InitializeFn systemInitialize, systemStart;
static SetPropertyFn systemSetProperty;
static atomic_bool enabled;
static BOOL attempted;
static size_t initSlots, propertySlots, startSlots;
static NSUInteger initializations, verifiedInitializations, forcedGainWrites, starts, verifiedStarts;
static NSInteger lastBypass = -1, lastGain = -1;
static OSStatus lastInitStatus, lastSetStatus, lastReadStatus, lastStartStatus;
static NSString *installFailure = @"not_installed";

static BOOL IsVoiceUnit(AudioUnit unit) {
    if (!unit) return NO;
    AudioComponent c = AudioComponentInstanceGetComponent(unit);
    AudioComponentDescription d = {0};
    return c && AudioComponentGetDescription(c, &d) == noErr
        && d.componentType == kAudioUnitType_Output
        && d.componentSubType == kAudioUnitSubType_VoiceProcessingIO;
}
static OSStatus ReadFlag(AudioUnit unit, AudioUnitPropertyID property, UInt32 *value) {
    UInt32 size = sizeof(*value);
    // Same input bus used by the existing WebRTC M124 bypass implementation.
    return AudioUnitGetProperty(unit, property, kAudioUnitScope_Global, 1, value, &size);
}
static void StoreReadback(AudioUnit unit, OSStatus writeStatus, BOOL updateWrite) {
    UInt32 bypass = 0, gain = 0;
    OSStatus read = ReadFlag(unit, kAUVoiceIOProperty_BypassVoiceProcessing, &bypass);
    OSStatus gainRead = ReadFlag(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, &gain);
    @synchronized (GovarVoiceProcessingBypass.class) {
        if (updateWrite) lastSetStatus = writeStatus;
        lastReadStatus = read;
        lastBypass = read == noErr ? (NSInteger)bypass : -1;
        lastGain = gainRead == noErr ? (NSInteger)gain : -1;
    }
}
static OSStatus GovarInitialize(AudioUnit unit) {
    OSStatus result = systemInitialize(unit);
    if (!atomic_load(&enabled) || !IsVoiceUnit(unit)) return result;
    @synchronized (GovarVoiceProcessingBypass.class) {
        initializations++; lastInitStatus = result;
    }
    if (result != noErr) return result;
    UInt32 bypass = 1;
    OSStatus set = systemSetProperty(unit, kAUVoiceIOProperty_BypassVoiceProcessing,
                                    kAudioUnitScope_Global, 1, &bypass, sizeof(bypass));
    UInt32 actual = 0;
    if (set == noErr && ReadFlag(unit, kAUVoiceIOProperty_BypassVoiceProcessing, &actual) == noErr && actual == 1) {
        UInt32 gain = 0;
        systemSetProperty(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC,
                          kAudioUnitScope_Global, 1, &gain, sizeof(gain));
        @synchronized (GovarVoiceProcessingBypass.class) { verifiedInitializations++; }
    }
    StoreReadback(unit, set, YES);
    // A rejected experimental preference must not turn successful RTC startup
    // into a failure. Diagnostics distinguish requested from verified bypass.
    return result;
}
static OSStatus GovarStart(AudioUnit unit) {
    OSStatus result = systemStart(unit);
    if (!atomic_load(&enabled) || !IsVoiceUnit(unit)) return result;
    UInt32 actual = 0;
    OSStatus read = result == noErr ? ReadFlag(unit, kAUVoiceIOProperty_BypassVoiceProcessing, &actual) : result;
    @synchronized (GovarVoiceProcessingBypass.class) {
        starts++; lastStartStatus = result;
        if (result == noErr && read == noErr && actual == 1) verifiedStarts++;
    }
    if (result == noErr) StoreReadback(unit, noErr, NO);
    return result;
}
static OSStatus GovarSetProperty(AudioUnit unit, AudioUnitPropertyID property,
                                AudioUnitScope scope, AudioUnitElement bus,
                                const void *data, UInt32 size) {
    if (!atomic_load(&enabled) || scope != kAudioUnitScope_Global
        || !data || size != sizeof(UInt32)
        || (property != kAUVoiceIOProperty_VoiceProcessingEnableAGC
            && property != kAUVoiceIOProperty_BypassVoiceProcessing)
        || !IsVoiceUnit(unit)) {
        return systemSetProperty(unit, property, scope, bus, data, size);
    }
    UInt32 value;
    memcpy(&value, data, sizeof(value));
    if (property == kAUVoiceIOProperty_BypassVoiceProcessing) {
        value = 1;
    } else {
        UInt32 bypass = 0;
        // Preserve WebRTC's normal gain setup if hardware refused bypass.
        if (ReadFlag(unit, kAUVoiceIOProperty_BypassVoiceProcessing, &bypass) != noErr || bypass != 1)
            return systemSetProperty(unit, property, scope, bus, data, size);
        value = 0;
        @synchronized (GovarVoiceProcessingBypass.class) { forcedGainWrites++; }
    }
    OSStatus result = systemSetProperty(unit, property, scope, bus, &value, sizeof(value));
    StoreReadback(unit, result, YES);
    return result;
}
@implementation GovarVoiceProcessingBypass
+ (BOOL)install {
    @synchronized (self) {
        if (attempted) return atomic_load(&enabled);
        attempted = YES;
        systemInitialize = (InitializeFn)dlsym(RTLD_DEFAULT, "AudioUnitInitialize");
        systemSetProperty = (SetPropertyFn)dlsym(RTLD_DEFAULT, "AudioUnitSetProperty");
        systemStart = (InitializeFn)dlsym(RTLD_DEFAULT, "AudioOutputUnitStart");
        if (!systemInitialize || !systemSetProperty || !systemStart) { installFailure = @"system_symbols_missing"; return NO; }
        const char *suffix = "/WebRTC.framework/WebRTC";
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name || strlen(name) < strlen(suffix)
                || strcmp(name + strlen(name) - strlen(suffix), suffix)) continue;
            struct rebinding bindings[] = {
                {"AudioUnitInitialize", (void *)GovarInitialize, NULL, &initSlots},
                {"AudioUnitSetProperty", (void *)GovarSetProperty, NULL, &propertySlots},
                {"AudioOutputUnitStart", (void *)GovarStart, NULL, &startSlots}
            };
            int result = rebind_symbols_image((void *)_dyld_get_image_header(i),
                                              _dyld_get_image_vmaddr_slide(i), bindings, 3);
            BOOL ready = result == 0 && initSlots > 0 && propertySlots > 0 && startSlots > 0;
            atomic_store(&enabled, ready);
            installFailure = ready ? @"" : @"webrtc_import_rebinding_failed";
            return ready;
        }
        installFailure = @"webrtc_image_missing";
        return NO;
    }
}
+ (NSDictionary<NSString *, id> *)diagnostics {
    @synchronized (self) {
        return @{@"installed": @(atomic_load(&enabled)), @"installFailure": installFailure,
                 @"initializeSlots": @(initSlots), @"propertySlots": @(propertySlots), @"startSlots": @(startSlots),
                 @"voiceUnitStarts": @(starts), @"verifiedBypassStarts": @(verifiedStarts),
                 @"lastStartStatus": @(lastStartStatus),
                 @"voiceUnitInitializations": @(initializations),
                 @"verifiedBypassInitializations": @(verifiedInitializations),
                 @"forcedGainWrites": @(forcedGainWrites),
                 @"lastInitStatus": @(lastInitStatus), @"lastSetStatus": @(lastSetStatus),
                 @"lastReadStatus": @(lastReadStatus),
                 @"lastBypassReadback": @(lastBypass), @"lastGainReadback": @(lastGain)};
    }
}
@end
