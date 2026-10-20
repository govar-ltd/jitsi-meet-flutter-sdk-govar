#import "GovarSoftwareAEC.h"
#import <WebRTC/RTCCallbackLogger.h>

@implementation GovarSoftwareAEC
static RTCCallbackLogger *logger;
static NSObject *stateLock;
static NSUInteger requestedCount;
static NSUInteger engineEnabledCount;
static NSString *lastAppliedConfig;

+ (void)installDiagnostics {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stateLock = [NSObject new];
        logger = [RTCCallbackLogger new];
        logger.severity = RTCLoggingSeverityWarning;
        [logger start:^(NSString *message) {
            // Never persist SDP, room names, tokens or arbitrary WebRTC logs.
            BOOL requested = [message containsString:@"Govar 431: requesting software AEC"];
            BOOL enabled = [message containsString:@"Force software AEC on iOS."];
            BOOL applied = [message containsString:@"Govar 431 APM applied:"];
            if (!requested && !enabled && !applied) return;
            @synchronized(stateLock) {
                if (requested) requestedCount++;
                if (enabled) engineEnabledCount++;
                if (applied) {
                    NSRange start = [message rangeOfString:@"Govar 431 APM applied:"];
                    NSString *config = [message substringFromIndex:start.location];
                    lastAppliedConfig = [config substringToIndex:MIN(config.length, 200)];
                }
            }
        }];
    });
}

+ (NSDictionary<NSString *, id> *)diagnostics {
    [self installDiagnostics];
    @synchronized(stateLock) {
        return @{@"loggerInstalled": @(logger != nil),
                 @"sourceRequests": @(requestedCount),
                 @"engineForceSoftwareAEC": @(engineEnabledCount),
                 @"lastAppliedConfig": lastAppliedConfig ?: @"not observed"};
    }
}
@end
