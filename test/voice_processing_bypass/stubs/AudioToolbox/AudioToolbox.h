#ifndef GOVAR_MOCK_AUDIO
#define GOVAR_MOCK_AUDIO
#include <stdint.h>
#include <MacTypes.h>
#include <stdbool.h>
typedef UInt32 AudioUnitPropertyID, AudioUnitScope, AudioUnitElement;
typedef struct MockUnit {
    UInt32 subtype, bypass, gain, lastProperty, lastValue;
    bool rejectBypass, rejectRead, resetOnStart;
    OSStatus initStatus, startStatus;
    int initializeCalls, setCalls;
} *AudioUnit;
typedef AudioUnit AudioComponent;
typedef struct { UInt32 componentType, componentSubType, componentManufacturer, componentFlags, componentFlagsMask; } AudioComponentDescription;
enum { kAudioUnitType_Output=1, kAudioUnitSubType_VoiceProcessingIO=2,
       kAudioUnitScope_Global=0, kAUVoiceIOProperty_BypassVoiceProcessing=2100,
       kAUVoiceIOProperty_VoiceProcessingEnableAGC=2101 };
OSStatus AudioUnitInitialize(AudioUnit);
OSStatus AudioOutputUnitStart(AudioUnit);
OSStatus AudioUnitSetProperty(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);
OSStatus AudioUnitGetProperty(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, void *, UInt32 *);
AudioComponent AudioComponentInstanceGetComponent(AudioUnit);
OSStatus AudioComponentGetDescription(AudioComponent, AudioComponentDescription *);
#endif
