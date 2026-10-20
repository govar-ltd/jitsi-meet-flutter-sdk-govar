#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Local experiment: adapt only imports of the pinned WebRTC framework.
@interface GovarVoiceProcessingBypass : NSObject
+ (BOOL)install;
+ (NSDictionary<NSString *, id> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
