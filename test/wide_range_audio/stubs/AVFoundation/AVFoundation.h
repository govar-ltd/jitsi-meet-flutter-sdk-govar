#import <Foundation/Foundation.h>
#define AVAudioSession GovarTestAudioSession
static NSString *const AVAudioSessionCategoryPlayAndRecord = @"playAndRecord";
static NSString *const AVAudioSessionModeDefault = @"default";
static NSString *const AVAudioSessionModeVideoChat = @"videoChat";
static NSString *const AVAudioSessionModeVoiceChat = @"voiceChat";
static NSString *const AVAudioSessionRouteChangeNotification = @"routeChanged";
static const NSUInteger AVAudioSessionCategoryOptionDefaultToSpeaker = 8;
@interface AVAudioSession : NSObject
@property NSString *category;
@property NSString *mode;
@property BOOL capable;
@property BOOL honorsPreference;
@property BOOL rejectPreference;
@property BOOL prefers;
@property BOOL rejectMode;
@property BOOL forceChatConfiguration;
@property BOOL rejectDefaultConfiguration;
@property NSUInteger preferenceRequests;
@property(readonly) BOOL isEchoCancelledInputAvailable;
@property(readonly) BOOL isEchoCancelledInputEnabled;
+ (instancetype)sharedInstance;
- (BOOL)setPrefersEchoCancelledInput:(BOOL)value error:(NSError **)error;
@end
