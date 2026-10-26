#import "GovarSystemVoiceProcessing.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import "vendor/fishhook/fishhook.h"

// Observe only WebRTC's init/start calls, preserving their exact return values.
// Never write bypass, gain, session mode or sample-rate preferences.
typedef OSStatus (*AudioUnitFn)(AudioUnit);
static AudioUnitFn originalInitialize, originalStart;
static atomic_bool enabled;
static BOOL attempted;
static size_t initSlots, startSlots;
static NSUInteger initializations, starts, confirmedStarts;
static NSInteger bypass = -1, gain = -1;
static OSStatus lastInitStatus, lastStartStatus, lastReadStatus;
static NSString *installFailure = @"not_installed";

static BOOL IsVoiceUnit(AudioUnit unit) {
    if (!unit) return NO;
    AudioComponent component = AudioComponentInstanceGetComponent(unit);
    AudioComponentDescription description = {0};
    return component && AudioComponentGetDescription(component, &description) == noErr
        && description.componentType == kAudioUnitType_Output
        && description.componentSubType == kAudioUnitSubType_VoiceProcessingIO;
}
static BOOL ReadState(AudioUnit unit) {
    UInt32 value = 0, agc = 0, size = sizeof(value);
    OSStatus status = AudioUnitGetProperty(unit, kAUVoiceIOProperty_BypassVoiceProcessing,
                                          kAudioUnitScope_Global, 1, &value, &size);
    size = sizeof(agc);
    OSStatus gainStatus = AudioUnitGetProperty(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC,
                                              kAudioUnitScope_Global, 1, &agc, &size);
    @synchronized (GovarSystemVoiceProcessing.class) {
        lastReadStatus = status;
        bypass = status == noErr ? (NSInteger)value : -1;
        gain = gainStatus == noErr ? (NSInteger)agc : -1;
    }
    return status == noErr && value == 0;
}
static OSStatus ObserveInitialize(AudioUnit unit) {
    OSStatus status = originalInitialize(unit);
    if (!atomic_load(&enabled) || !IsVoiceUnit(unit)) return status;
    @synchronized (GovarSystemVoiceProcessing.class) {
        initializations++; lastInitStatus = status;
    }
    if (status == noErr) ReadState(unit);
    return status;
}
static OSStatus ObserveStart(AudioUnit unit) {
    OSStatus status = originalStart(unit);
    if (!atomic_load(&enabled) || !IsVoiceUnit(unit)) return status;
    BOOL confirmed = status == noErr && ReadState(unit);
    @synchronized (GovarSystemVoiceProcessing.class) {
        starts++; lastStartStatus = status;
        if (confirmed) confirmedStarts++;
    }
    return status;
}
@implementation GovarSystemVoiceProcessing
+ (BOOL)install {
    @synchronized (self) {
        if (attempted) return atomic_load(&enabled);
        attempted = YES;
        originalInitialize = (AudioUnitFn)dlsym(RTLD_DEFAULT, "AudioUnitInitialize");
        originalStart = (AudioUnitFn)dlsym(RTLD_DEFAULT, "AudioOutputUnitStart");
        if (!originalInitialize || !originalStart) {
            installFailure = @"system_symbols_missing"; return NO;
        }
        const char *suffix = "/WebRTC.framework/WebRTC";
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name || strlen(name) < strlen(suffix)
                || strcmp(name + strlen(name) - strlen(suffix), suffix)) continue;
            struct rebinding bindings[] = {
                {"AudioUnitInitialize", (void *)ObserveInitialize, NULL, &initSlots},
                {"AudioOutputUnitStart", (void *)ObserveStart, NULL, &startSlots}
            };
            int result = rebind_symbols_image((void *)_dyld_get_image_header(i),
                                              _dyld_get_image_vmaddr_slide(i), bindings, 2);
            BOOL ready = result == 0 && initSlots > 0 && startSlots > 0;
            atomic_store(&enabled, ready);
            installFailure = ready ? @"" : @"webrtc_import_observer_unavailable";
            return ready;
        }
        installFailure = @"webrtc_image_missing";
        return NO;
    }
}
+ (NSDictionary<NSString *, id> *)diagnostics {
    @synchronized (self) {
        return @{@"observerInstalled": @(atomic_load(&enabled)),
                 @"policy": @"system_voice_processing", @"installFailure": installFailure,
                 @"voiceUnitInitializations": @(initializations), @"voiceUnitStarts": @(starts),
                 @"confirmedProcessingStarts": @(confirmedStarts),
                 @"lastBypassReadback": @(bypass), @"lastGainReadback": @(gain),
                 @"lastInitStatus": @(lastInitStatus), @"lastStartStatus": @(lastStartStatus),
                 @"lastReadStatus": @(lastReadStatus)};
    }
}
@end
