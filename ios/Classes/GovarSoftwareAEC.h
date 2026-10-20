#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface GovarSoftwareAEC : NSObject
+ (void)installDiagnostics;
+ (NSDictionary<NSString *, id> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
