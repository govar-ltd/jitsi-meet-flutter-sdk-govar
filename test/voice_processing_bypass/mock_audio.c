#include <AudioToolbox/AudioToolbox.h>
#include <string.h>
OSStatus AudioUnitInitialize(AudioUnit u) { u->initializeCalls++; return u->initStatus; }
OSStatus AudioUnitSetProperty(AudioUnit u, UInt32 p, UInt32 s, UInt32 b, const void *v, UInt32 n) {
    u->setCalls++; u->lastProperty=p;
    if (p==kAUVoiceIOProperty_BypassVoiceProcessing && u->rejectBypass) return -77;
    if (!v || n!=4) return -99;
    UInt32 x; memcpy(&x,v,4); u->lastValue=x;
    if (p==kAUVoiceIOProperty_BypassVoiceProcessing) u->bypass=x;
    if (p==kAUVoiceIOProperty_VoiceProcessingEnableAGC) u->gain=x;
    return 0;
}
OSStatus AudioUnitGetProperty(AudioUnit u, UInt32 p, UInt32 s, UInt32 b, void *v, UInt32 *n) {
    if (u->rejectRead) return -88;
    UInt32 x=p==kAUVoiceIOProperty_BypassVoiceProcessing?u->bypass:u->gain;
    memcpy(v,&x,4);*n=4;return 0;
}
AudioComponent AudioComponentInstanceGetComponent(AudioUnit u) { return u; }
OSStatus AudioComponentGetDescription(AudioComponent u, AudioComponentDescription *d) {
    d->componentType=kAudioUnitType_Output;d->componentSubType=u->subtype;return 0;
}

OSStatus AudioOutputUnitStart(AudioUnit u) { if(u->resetOnStart)u->bypass=0; return u->startStatus; }
