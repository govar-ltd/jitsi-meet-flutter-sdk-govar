#import <Foundation/Foundation.h>
@interface GovarWideRangeAudio : NSObject
+ (BOOL)install;
+ (void)beginConference;
+ (NSDictionary<NSString *, id> *)diagnostics;
@end
