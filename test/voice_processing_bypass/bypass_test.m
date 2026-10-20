#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>
#import "../../ios/Classes/GovarVoiceProcessingBypass.h"
int main(int argc, char **argv) { @autoreleasepool {
    BOOL missing = !strcmp(argv[1],"missing"), partial = !strcmp(argv[1],"partial");
    void *handle = missing ? NULL : dlopen(argv[2],RTLD_NOW|RTLD_GLOBAL);
    NSCAssert(missing || handle, @"Load mock WebRTC image");
    if (missing || partial) {
        NSCAssert(![GovarVoiceProcessingBypass install], @"Incomplete binding must stay inactive");
        if (partial) {
            OSStatus (*initialize)(AudioUnit)=dlsym(handle,"RTCTestInitialize");
            struct MockUnit u={.subtype=2,.gain=1};
            NSCAssert(initialize(&u)==0 && u.bypass==0 && u.gain==1, @"Partial interception forwards without changes");
        }
        puts("PASS: unavailable or partial binding is safe");return 0;
    }
    OSStatus (*initialize)(AudioUnit)=dlsym(handle,"RTCTestInitialize");
    OSStatus (*set)(AudioUnit,UInt32,UInt32,UInt32)=dlsym(handle,"RTCTestSet");
    OSStatus (*start)(AudioUnit)=dlsym(handle,"RTCTestStart");
    NSCAssert(initialize && set && start, @"Mock functions exported");
    NSCAssert([GovarVoiceProcessingBypass install] && [GovarVoiceProcessingBypass install], @"Idempotent actual binding");
    struct MockUnit u={.subtype=2,.gain=1};
    NSCAssert(initialize(&u)==0 && u.bypass==1 && u.gain==0, @"Enable and verify bypass");
    NSCAssert(set(&u,2101,0,1)==0 && u.gain==0, @"Prevent RTC re-enabling AGC only after verified bypass");
    NSCAssert(set(&u,2100,0,0)==0 && u.bypass==1, @"Keep bypass for subsequent RTC writes");
    NSCAssert(set(&u,777,9,55)==0 && u.lastProperty==777 && u.lastValue==55, @"Forward unrelated properties unchanged");
    NSCAssert(start(&u)==0 && [[GovarVoiceProcessingBypass diagnostics][@"verifiedBypassStarts"] intValue]==1, @"Verify after actual output-unit start");
    u.resetOnStart=true;
    NSCAssert(start(&u)==0 && [[GovarVoiceProcessingBypass diagnostics][@"lastBypassReadback"] intValue]==0, @"Detect flags reset during start rather than claim success");
    u.startStatus=-66;
    NSCAssert(start(&u)==-66, @"Forward start failure");
    UInt32 on=1;
    AudioUnitSetProperty(&u,2101,0,1,&on,4);
    NSCAssert(u.gain==1, @"Other images are not intercepted");
    struct MockUnit denied={.subtype=2,.gain=1,.rejectBypass=true};
    NSCAssert(initialize(&denied)==0 && denied.bypass==0 && denied.gain==1, @"Rejected preference cannot break startup or gain");
    NSCAssert(set(&denied,2101,0,1)==0 && denied.gain==1, @"Retain normal gain if bypass unavailable");
    struct MockUnit failed={.subtype=2,.gain=1,.initStatus=-55};
    NSCAssert(initialize(&failed)==-55 && failed.setCalls==0, @"Forward init failure without extra writes");
    struct MockUnit nonVoice={.subtype=99,.gain=1};
    NSCAssert(initialize(&nonVoice)==0 && nonVoice.setCalls==0, @"Leave other audio unit types unchanged");
    struct MockUnit unreadable={.subtype=2,.gain=1,.rejectRead=true};
    NSCAssert(initialize(&unreadable)==0 && unreadable.gain==1, @"Unverified bypass cannot disable gain");
    NSDictionary *d=[GovarVoiceProcessingBypass diagnostics];
    NSCAssert([d[@"verifiedBypassInitializations"] unsignedIntegerValue]==1, @"Count confirmed starts only");
    NSCAssert([d[@"lastBypassReadback"] integerValue]==-1 && [d[@"lastReadStatus"] intValue]==-88, @"Expose readback failure");
    puts("PASS: image-only bypass, readback, error paths and unchanged unrelated audio");
} return 0; }
