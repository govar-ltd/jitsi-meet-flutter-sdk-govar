#import <Foundation/Foundation.h>
@interface RTCAudioSessionConfiguration : NSObject
+ (instancetype)webRTCConfiguration;
+ (void)setWebRTCConfiguration:(RTCAudioSessionConfiguration *)configuration;
@property NSString *category;
@property NSString *mode;
@property NSUInteger categoryOptions;
@property double sampleRate;
@property double ioBufferDuration;
@property NSInteger inputNumberOfChannels;
@property NSInteger outputNumberOfChannels;
@end
@interface RTCAudioSession : NSObject
+ (instancetype)sharedInstance;
- (void)lockForConfiguration;
- (void)unlockForConfiguration;
- (BOOL)setConfiguration:(RTCAudioSessionConfiguration *)config error:(NSError **)error;
@end
