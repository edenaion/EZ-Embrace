#import <Foundation/Foundation.h>

@class Preferences;

typedef NS_ENUM(NSInteger, AuditionState) {
    AuditionStateStopped,
    AuditionStatePreparing,
    AuditionStatePlaying,
    AuditionStatePaused,
    AuditionStateError
};

extern NSString * const AuditionPlayerDidChangeNotification;

@interface AuditionPlayer : NSObject
+ (instancetype) sharedInstance;
+ (void) shutdownIfLoaded;
- (instancetype) initWithPreferences:(Preferences *)preferences;
- (NSUUID *) previewURL:(NSURL *)url title:(NSString *)title artist:(NSString *)artist;
- (NSUUID *) previewURL:(NSURL *)url title:(NSString *)title artist:(NSString *)artist
              startTime:(NSTimeInterval)startTime endTime:(NSTimeInterval)endTime;
- (void) stopPreviewWithIdentifier:(NSUUID *)identifier;
- (void) pause;
- (void) resume;
- (void) stop;
- (void) seekToTime:(NSTimeInterval)time;

// Published together on the main thread. Hardware and decoder work run on a separate serial queue.
@property (nonatomic, readonly) AuditionState state;
@property (nonatomic, readonly) NSString *message;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSString *artist;
@property (nonatomic, readonly) NSURL *fileURL;
@property (nonatomic, readonly) NSUUID *requestIdentifier;
@property (nonatomic, readonly) NSTimeInterval position;
@property (nonatomic, readonly) NSTimeInterval duration;
@end
