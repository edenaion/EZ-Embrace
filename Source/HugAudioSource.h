// (c) 2018-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@class HugAudioFile, HugAudioSource;

typedef NS_ENUM(NSInteger, HugPlaybackStatus) {
    HugPlaybackStatusStopped = 0,
    HugPlaybackStatusPreparing,
    HugPlaybackStatusWaiting,
    HugPlaybackStatusPlaying,
    HugPlaybackStatusFinished
};

typedef struct HugPlaybackInfo {
    UInt32 seekGeneration;
    HugPlaybackStatus status;
    NSTimeInterval timeElapsed;
    NSTimeInterval timeRemaining;
} HugPlaybackInfo;

typedef OSStatus (^HugAudioSourceInputBlock)(
    AUAudioFrameCount frameCount,
    AudioBufferList *inputData,
    HugPlaybackInfo *outInfo
);


typedef void (^HugAudioSourceCompletionHandler)(HugAudioSource *source);

@interface HugAudioSource : NSObject

- (instancetype) initWithAudioFile: (HugAudioFile *) file
                          settings: (NSDictionary *) settings;

// Primes the audio buffer. If this returns YES, completionHandler will be invoked
// after the buffer is completely prepared.
//
- (BOOL) prepareWithStartTime: (NSTimeInterval) startTime
                     stopTime: (NSTimeInterval) stopTime
                      padding: (NSTimeInterval) padding
            completionHandler: (HugAudioSourceCompletionHandler) completionHandler;

// Initial position is relative to the playable region, without changing seek bounds.
- (BOOL) prepareWithStartTime:(NSTimeInterval)startTime
                    stopTime:(NSTimeInterval)stopTime
                     padding:(NSTimeInterval)padding
                 initialTime:(NSTimeInterval)initialTime
           completionHandler:(HugAudioSourceCompletionHandler)completionHandler;

@property (nonatomic, readonly) HugAudioFile *audioFile;
@property (nonatomic, readonly) NSDictionary *settings;

@property (nonatomic, readonly) NSError *error;

@property (nonatomic, readonly) HugAudioSourceInputBlock inputBlock;
@property (nonatomic, readonly) NSTimeInterval duration;

// Main thread only. Position is relative to the trimmed playable region.
// Returns a generation used to discard playback reports from before the seek.
- (UInt32) seekToTime:(NSTimeInterval)time;

@end

