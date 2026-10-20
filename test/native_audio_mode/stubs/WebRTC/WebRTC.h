#import <Foundation/Foundation.h>
@interface RTCAudioSessionConfiguration : NSObject
@property NSString *category;
@property NSString *mode;
@property NSUInteger categoryOptions;
@property double sampleRate;
@property double ioBufferDuration;
@property NSInteger inputNumberOfChannels;
@property NSInteger outputNumberOfChannels;
@end
