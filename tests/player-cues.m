#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Player.h"
#import "Track.h"
#import "Effect.h"
#import "EffectAdditions.h"
#import "HugAudioDevice.h"
#import "HugAudioEngine.h"
#import "HugAudioFile.h"
#import "HugAudioSettings.h"

#import <objc/runtime.h>

@interface Player (CueRegressionTesting)
- (void)setCurrentTrack:(Track *)track;
- (void)_setupAndStartPlayback;
- (void)_handleEngineUpdate;
@end

static NSUInteger sAssertions;

static void Check(BOOL condition, NSString *message)
{
    sAssertions++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static void CheckNear(NSTimeInterval actual, NSTimeInterval expected, NSString *message)
{
    Check(isfinite(actual) && fabs(actual - expected) < 0.001,
          [NSString stringWithFormat:@"%@ (expected %.3f, got %.3f)", message, expected, actual]);
}

NSString *GetStringForTime(NSTimeInterval time)
{
    return [NSString stringWithFormat:@"%.0f", time];
}

void EmbraceLog(NSString *category, NSString *format, ...) {}
void _EmbraceLogMethod(const char *function) {}
HugAudioSettings const HugAudioSettingSampleRate = @"HugAudioSettingSampleRate";
HugAudioSettings const HugAudioSettingFrameSize = @"HugAudioSettingFrameSize";
NSArray<Effect *> *EmbraceEffectsBySettingParametricEQEnabled(NSArray<Effect *> *effects, BOOL enabled)
{
    return effects;
}
NSString * const EmbraceMappedEffect10BandEQ = @"EmbraceGraphicEQ10";
NSString * const EmbraceEffectParametricEQ = @"EmbraceParametricEQ";
NSString *EmbraceEqualizerEffectName(EqualizerType type)
{
    return type == EqualizerTypeGraphic10Band ? EmbraceMappedEffect10BandEQ : EmbraceEffectParametricEQ;
}
NSArray<Effect *> *EmbraceEffectsBySettingEqualizerEnabled(NSArray<Effect *> *effects, EqualizerType type, BOOL enabled)
{
    return effects;
}
Effect *EmbraceEqualizerEffectWithState(NSDictionary *state, EqualizerType type) { return nil; }

@interface CueFakeTrack : NSObject {
    NSTimeInterval _testCueStartTime;
    NSTimeInterval _testCueOffset;
    NSTimeInterval _testPlayDuration;
    NSUInteger _testCueRevision;
    TrackStatus _testTrackStatus;
    BOOL _testStopsAfterPlaying;
    BOOL _testIgnoresAutoGap;
}
@property (nonatomic, readonly) NSTimeInterval testCueStartTime;
@property (nonatomic, readonly) NSUInteger testCueRevision;
- (instancetype)initWithCue:(NSTimeInterval)cue duration:(NSTimeInterval)duration;
@end

@implementation CueFakeTrack
- (instancetype)initWithCue:(NSTimeInterval)cue duration:(NSTimeInterval)duration
{
    if ((self = [super init])) {
        _testCueStartTime = cue;
        _testCueOffset = cue;
        _testPlayDuration = duration;
        _testCueRevision = 1;
    }
    return self;
}
- (NSTimeInterval)cueStartTime { return _testCueStartTime; }
- (void)setCueStartTime:(NSTimeInterval)value
{
    if (_testCueStartTime == value) return;
    _testCueStartTime = value;
    _testCueOffset = value;
    _testCueRevision++;
}
- (NSTimeInterval)cueOffset { return _testCueOffset; }
- (NSTimeInterval)playDuration { return _testPlayDuration; }
- (NSTimeInterval)startTime { return 0; }
- (NSTimeInterval)stopTime { return _testPlayDuration; }
- (NSUInteger)cueRevision { return _testCueRevision; }
- (void)clearCueForPlaybackRevision:(NSUInteger)revision
{
    if (revision == _testCueRevision) self.cueStartTime = 0;
}
- (BOOL)isResolvingURLs { return NO; }
- (BOOL)didAnalyzeLoudness { return YES; }
- (NSURL *)internalURL { return [NSURL fileURLWithPath:@"/tmp/player-cue-fixture.wav"]; }
- (NSError *)error { return nil; }
- (double)trackLoudness { return -18; }
- (double)trackPeak { return 0.5; }
- (TrackStatus)trackStatus { return _testTrackStatus; }
- (void)setTrackStatus:(TrackStatus)value { _testTrackStatus = value; }
- (BOOL)stopsAfterPlaying { return _testStopsAfterPlaying; }
- (void)setStopsAfterPlaying:(BOOL)value { _testStopsAfterPlaying = value; }
- (BOOL)ignoresAutoGap { return _testIgnoresAutoGap; }
- (void)setIgnoresAutoGap:(BOOL)value { _testIgnoresAutoGap = value; }
- (NSString *)description { return @"cue-test-track"; }
@end

@implementation HugAudioFile {
    NSURL *_testFileURL;
}
- (instancetype)initWithFileURL:(NSURL *)url { if ((self = [super init])) _testFileURL = url; return self; }
- (BOOL)open { return YES; }
- (NSURL *)fileURL { return _testFileURL; }
@end

@interface HugAudioEngine ()
@property (nonatomic) HugPlaybackStatus testPlaybackStatus;
@property (nonatomic) NSTimeInterval testTimeElapsed;
@property (nonatomic) NSTimeInterval testTimeRemaining;
@property (nonatomic) NSTimeInterval receivedInitialTime;
@end

static HugAudioEngine *sLastEngine;

@implementation HugAudioEngine
- (instancetype)init { if ((self = [super init])) sLastEngine = self; return self; }
- (BOOL)playAudioFile:(HugAudioFile *)file startTime:(NSTimeInterval)startTime stopTime:(NSTimeInterval)stopTime padding:(NSTimeInterval)padding initialTime:(NSTimeInterval)initialTime
{
    self.receivedInitialTime = initialTime;
    self.testPlaybackStatus = HugPlaybackStatusPreparing;
    return YES;
}
- (void)stopPlayback { self.testPlaybackStatus = HugPlaybackStatusStopped; }
- (BOOL)seekToTime:(NSTimeInterval)time { return YES; }
- (void)stopHardware {}
- (void)updatePreGain:(float)value {}
- (void)updateVolume:(float)value {}
- (void)updateStereoWidth:(float)value {}
- (void)updateStereoBalance:(float)value {}
- (void)updateEffectAudioUnits:(NSArray<AUAudioUnit *> *)units {}
- (HugPlaybackStatus)playbackStatus { return self.testPlaybackStatus; }
- (NSTimeInterval)timeElapsed { return self.testTimeElapsed; }
- (NSTimeInterval)timeRemaining { return self.testTimeRemaining; }
- (HugMeterData *)leftMeterData { return nil; }
- (HugMeterData *)rightMeterData { return nil; }
- (float)dangerLevel { return 0; }
- (NSTimeInterval)lastOverloadTime { return 0; }
@end

@implementation HugAudioDevice
+ (NSArray<HugAudioDevice *> *)allDevices { return @[]; }
@end

@implementation Effect
+ (instancetype)effectWithStateDictionary:(NSDictionary *)state { return nil; }
@end

static Player *MakePlayerWithTrack(CueFakeTrack *track)
{
    Player *player = [Player new];
    [player setCurrentTrack:(Track *)track];
    [player _setupAndStartPlayback];
    Check(sLastEngine != nil, @"production Player initialized its fake engine");
    return player;
}

int main(void)
{
    @autoreleasepool {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in @[@"effects", @"match-loudness", @"pre-amp", @"stereo-level", @"stereo-balance", @"volume"]) {
            [defaults removeObjectForKey:key];
        }

        CueFakeTrack *finishedTrack = [[CueFakeTrack alloc] initWithCue:25 duration:120];
        Player *finishedPlayer = MakePlayerWithTrack(finishedTrack);
        CheckNear(sLastEngine.receivedInitialTime, 25, @"production Player passes the cue offset to initial playback");
        finishedPlayer.preventNextTrack = YES;
        sLastEngine.testPlaybackStatus = HugPlaybackStatusFinished;
        [finishedPlayer _handleEngineUpdate];
        CheckNear(finishedTrack.cueStartTime, 0, @"natural production Player completion clears the cue in use");

        CueFakeTrack *nearEndTrack = [[CueFakeTrack alloc] initWithCue:119 duration:120];
        Player *nearEndPlayer = MakePlayerWithTrack(nearEndTrack);
        sLastEngine.testPlaybackStatus = HugPlaybackStatusFinished;
        [nearEndPlayer _handleEngineUpdate];
        Check(nearEndPlayer.currentTrack == nil && nearEndTrack.trackStatus == TrackStatusPlayed,
              @"natural completion of a one-second cued tail stays played at queue end");
        CheckNear(nearEndTrack.cueStartTime, 0, @"one-second cued tail clears its used cue");

        CueFakeTrack *updatedTrack = [[CueFakeTrack alloc] initWithCue:25 duration:120];
        Player *updatedPlayer = MakePlayerWithTrack(updatedTrack);
        NSUInteger startedRevision = updatedTrack.cueRevision;
        updatedTrack.cueStartTime = 40;
        Check(updatedTrack.cueRevision != startedRevision, @"test installs a newer pending cue revision");
        updatedPlayer.preventNextTrack = YES;
        sLastEngine.testPlaybackStatus = HugPlaybackStatusFinished;
        [updatedPlayer _handleEngineUpdate];
        CheckNear(updatedTrack.cueStartTime, 40, @"old playback completion preserves a newer cue saved during playback");

        CueFakeTrack *earlyTrack = [[CueFakeTrack alloc] initWithCue:75 duration:150];
        Player *earlyPlayer = MakePlayerWithTrack(earlyTrack);
        CheckNear(sLastEngine.receivedInitialTime, 75, @"cue-75 track starts at offset 75");
        sLastEngine.testPlaybackStatus = HugPlaybackStatusPlaying;
        sLastEngine.testTimeElapsed = 79;
        sLastEngine.testTimeRemaining = 71;
        [earlyPlayer _handleEngineUpdate];
        [earlyPlayer hardStop];
        Check(earlyTrack.trackStatus == TrackStatusQueued, @"stopping four seconds after cue 75 remarks the track queued");
        CheckNear(earlyTrack.cueStartTime, 75, @"manual stop retains the saved cue");

        CueFakeTrack *skipTrack = [[CueFakeTrack alloc] initWithCue:30 duration:120];
        Player *skipPlayer = MakePlayerWithTrack(skipTrack);
        [skipPlayer hardSkip];
        CheckNear(skipTrack.cueStartTime, 30, @"manual skip retains the saved cue");
        Check(skipTrack.trackStatus == TrackStatusPlayed, @"explicit skip remains played even before five seconds");

        printf("PASS: %lu production Player cue assertions\n", (unsigned long)sAssertions);
    }
    return 0;
}
