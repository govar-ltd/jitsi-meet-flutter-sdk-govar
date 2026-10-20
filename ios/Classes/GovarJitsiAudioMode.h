#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Experimental adapter for the pinned JitsiMeetSDK 12.0.0 AudioMode module.
@interface GovarJitsiAudioMode : NSObject
+ (BOOL)install;
+ (NSDictionary<NSString *, id> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
