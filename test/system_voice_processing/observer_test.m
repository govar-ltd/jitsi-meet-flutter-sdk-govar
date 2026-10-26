#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>
#import "../../ios/Classes/GovarSystemVoiceProcessing.h"
int main(int argc, char **argv) { @autoreleasepool {
    BOOL missing = !strcmp(argv[1], "missing"), partial = !strcmp(argv[1], "partial");
    void *handle = missing ? NULL : dlopen(argv[2], RTLD_NOW|RTLD_GLOBAL);
    NSCAssert(missing || handle, @"Mock loaded");
    if (missing || partial) {
        NSCAssert(![GovarSystemVoiceProcessing install], @"Incomplete observer stays inactive");
        if (partial) {
            OSStatus (*initialize)(AudioUnit)=dlsym(handle,"RTCTestInitialize");
            struct MockUnit u={.subtype=2,.gain=1};
            NSCAssert(initialize(&u)==0 && u.setCalls==0, @"Partial observer preserves behavior");
        }
        puts("PASS: unavailable/partial observer is harmless"); return 0;
    }
    OSStatus (*initialize)(AudioUnit)=dlsym(handle,"RTCTestInitialize");
    OSStatus (*set)(AudioUnit,UInt32,UInt32,UInt32)=dlsym(handle,"RTCTestSet");
    OSStatus (*start)(AudioUnit)=dlsym(handle,"RTCTestStart");
    NSCAssert([GovarSystemVoiceProcessing install] && [GovarSystemVoiceProcessing install], @"Idempotent observer");
    struct MockUnit u={.subtype=2,.gain=1};
    NSCAssert(initialize(&u)==0 && start(&u)==0 && u.setCalls==0 && u.bypass==0 && u.gain==1, @"No property writes");
    NSCAssert([[GovarSystemVoiceProcessing diagnostics][@"confirmedProcessingStarts"] intValue]==1, @"Confirm processing is not bypassed");
    NSCAssert(set(&u,2100,0,1)==0 && u.bypass==1 && start(&u)==0, @"Forward existing writes unchanged");
    NSCAssert([[GovarSystemVoiceProcessing diagnostics][@"confirmedProcessingStarts"] intValue]==1, @"Do not count bypassed processing as enabled");
    NSCAssert(set(&u,777,9,55)==0 && u.lastProperty==777 && u.lastValue==55, @"Unrelated writes untouched");
    struct MockUnit failed={.subtype=2,.gain=1,.initStatus=-55,.startStatus=-66};
    NSCAssert(initialize(&failed)==-55 && start(&failed)==-66 && failed.setCalls==0, @"Exact failures preserved");
    struct MockUnit other={.subtype=99,.gain=1};
    NSCAssert(initialize(&other)==0 && start(&other)==0 && other.setCalls==0, @"Other unit types untouched");
    struct MockUnit unreadable={.subtype=2,.gain=1,.rejectRead=true};
    NSCAssert(initialize(&unreadable)==0 && start(&unreadable)==0 && unreadable.setCalls==0, @"Readback failure cannot affect audio");
    NSCAssert([[GovarSystemVoiceProcessing diagnostics][@"lastBypassReadback"] intValue]==-1, @"Readback failure visible");
    puts("PASS: read-only observer, accurate confirmation, forwarding and error paths");
} return 0; }
