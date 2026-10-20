#include <AudioToolbox/AudioToolbox.h>
OSStatus RTCTestInitialize(AudioUnit u) { return AudioUnitInitialize(u); }
#ifndef TEST_PARTIAL
OSStatus RTCTestStart(AudioUnit u) { return AudioOutputUnitStart(u); }
OSStatus RTCTestSet(AudioUnit u, UInt32 property, UInt32 scope, UInt32 value) {
    return AudioUnitSetProperty(u,property,scope,1,&value,sizeof(value));
}
#endif
