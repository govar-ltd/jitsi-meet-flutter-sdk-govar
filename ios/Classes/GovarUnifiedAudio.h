#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface GovarUnifiedAudio : NSObject
+ (BOOL)install;
+ (NSDictionary<NSString *,id> *)diagnostics;
+ (void)startRecordingAtPath:(NSString *)path completion:(void (^)(NSError * _Nullable error))completion NS_SWIFT_NAME(startRecording(path:completion:));
+ (void)stopRecordingWithCompletion:(void (^)(void))completion NS_SWIFT_NAME(stopRecording(completion:));
@end
NS_ASSUME_NONNULL_END
