#import <Foundation/Foundation.h>
#import "HugAudioFile.h"
#import "HugAudioSource.h"
#import "HugAudioSettings.h"
#import "HugError.h"
#import "HugUtils.h"

typedef NS_ENUM(NSUInteger, DecoderMode) {
    DecoderOpenFailure,
    DecoderTrimFailure,
    DecoderFirstReadFailure,
    DecoderDelayedSuccess,
    DecoderFailureAfterPrime,
    DecoderShortEOF,
    DecoderPrimeTimeout
};

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

// A deterministic decoder double exercises the production source without device I/O.
@interface ControlledAudioFile : HugAudioFile
@property (atomic) NSError *injectedError;
@property (atomic) NSUInteger openCount;
@property (atomic) NSUInteger readCount;
@property (atomic) NSUInteger seekCount;
@property (nonatomic, readonly) dispatch_semaphore_t paused;
@property (nonatomic, readonly) dispatch_semaphore_t resume;
- (instancetype)initWithMode:(DecoderMode)mode;
@end

@implementation ControlledAudioFile {
    DecoderMode _mode;
    UInt32 _decodedFrames;
    BOOL _resumed;
}
- (instancetype)initWithMode:(DecoderMode)mode
{
    if ((self = [super initWithFileURL:[NSURL fileURLWithPath:@"/decoder-fixture.wav"]])) {
        _mode = mode;
        _paused = dispatch_semaphore_create(0);
        _resume = dispatch_semaphore_create(0);
    }
    return self;
}
- (NSError *)error { return self.injectedError; }
- (BOOL)failWithCode:(NSInteger)code
{
    self.injectedError = [NSError errorWithDomain:HugErrorDomain code:code userInfo:nil];
    return NO;
}
- (BOOL)open
{
    self.openCount++;
    return _mode != DecoderOpenFailure || [self failWithCode:HugErrorOpenFailed];
}
- (void)close {}
- (SInt64)fileLengthFrames { return 48000 * 20; }
- (AudioStreamBasicDescription)format
{
    return (AudioStreamBasicDescription){48000, kAudioFormatLinearPCM,
        kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
        sizeof(float), 1, sizeof(float), 1, 32, 0};
}
- (BOOL)seekToFrame:(SInt64)frame
{
    self.seekCount++;
    _decodedFrames = (UInt32)frame;
    return _mode != DecoderTrimFailure || [self failWithCode:HugErrorReadFailed];
}
- (BOOL)readFrames:(UInt32 *)count intoBufferList:(AudioBufferList *)buffers
{
    self.readCount++;
    if (_mode == DecoderFirstReadFailure) return [self failWithCode:HugErrorReadFailed];
    BOOL shouldPause = _mode == DecoderPrimeTimeout || _decodedFrames >= 16 * 32768;
    if (shouldPause && !_resumed) {
        dispatch_semaphore_signal(_paused);
        Check(dispatch_semaphore_wait(_resume, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0,
            @"Test releases paused decoder");
        _resumed = YES;
        if (_mode == DecoderFailureAfterPrime) return [self failWithCode:HugErrorReadFailed];
        if (_mode == DecoderShortEOF) { *count = 0; return YES; }
    }
    *count = MIN(*count, (UInt32)self.fileLengthFrames - _decodedFrames);
    for (UInt32 b = 0; b < buffers->mNumberBuffers; b++) {
        float *samples = buffers->mBuffers[b].mData;
        for (UInt32 f = 0; f < *count; f++) samples[f] = (_decodedFrames + f) / 48000.0f / 100;
    }
    _decodedFrames += *count;
    return YES;
}
@end

static HugAudioSource *Source(ControlledAudioFile *file, double rate)
{
    return [[HugAudioSource alloc] initWithAudioFile:file settings:@{
        HugAudioSettingSampleRate: @(rate), HugAudioSettingFrameSize: @512
    }];
}

static HugPlaybackInfo Render(HugAudioSource *source, AudioBufferList *buffers)
{
    HugPlaybackInfo info = {0};
    Check(source.inputBlock(512, buffers, &info) == noErr, @"Render succeeds during decoder fault test");
    for (UInt32 b = 0; b < buffers->mNumberBuffers; b++) {
        float *samples = buffers->mBuffers[b].mData;
        for (UInt32 f = 0; f < 512; f++) Check(isfinite(samples[f]), @"Fault path renders finite samples");
    }
    return info;
}

static void AwaitCompletion(BOOL *finished)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!*finished && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    Check(*finished, @"Decoder completion arrives on main run loop");
}

static void TestEarlyFailure(DecoderMode mode)
{
    ControlledAudioFile *file = [[ControlledAudioFile alloc] initWithMode:mode];
    HugAudioSource *source = Source(file, 48000);
    Check(![source prepareWithStartTime:mode == DecoderTrimFailure ? 2 : 0 stopTime:0 padding:0 completionHandler:nil],
        @"Open, initial trim, and first-read failures reject preparation");
    Check(source.error != nil && source.inputBlock == nil, @"Preparation preserves error and exposes no render block");
    Check([source seekToTime:10] == 0, @"Unprepared source rejects seeking");
}

static void TestDeferredSeek(DecoderMode mode, double rate)
{
    ControlledAudioFile *file = [[ControlledAudioFile alloc] initWithMode:mode];
    HugAudioSource *source = Source(file, rate);
    __block BOOL finished = NO;
    Check([source prepareWithStartTime:0 stopTime:0 padding:0 completionHandler:^(HugAudioSource *s) { finished = YES; }],
        @"Source primes before delayed read");
    Check(dispatch_semaphore_wait(file.paused, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
        @"Decoder pauses beyond primed region");
    NSUInteger reads = file.readCount;
    UInt32 generation = [source seekToTime:18];
    Check(generation != 0, @"Seek request accepted while target is decoding");
    AudioBufferList *buffers = HugAudioBufferListCreate(2, 512, YES);
    HugPlaybackInfo info = {0};
    for (NSUInteger i = 0; i < 10; i++) info = Render(source, buffers);
    Check(info.seekGeneration == 0 && info.timeElapsed < 1, @"Pending seek keeps playing prepared audio without blocking");
    Check(file.readCount == reads && file.openCount == 1 && file.seekCount == 0,
        @"Seeking performs no decoder open, read, or seek operation");
    dispatch_semaphore_signal(file.resume);
    AwaitCompletion(&finished);
    if (mode == DecoderFailureAfterPrime) {
        Check(source.error.code == HugErrorReadFailed, @"Read failure preserved after priming");
        Check([source seekToTime:1] == 0, @"Failed decoder rejects further seeks");
    } else {
        Check(source.error == nil, @"Delayed decoder or early EOF completes without error");
        Render(source, buffers);
        info = Render(source, buffers);
        Check(info.seekGeneration == generation && fabs(info.timeElapsed - 18) < 0.1,
            @"Pending seek applies once decoding completes");
        if (mode == DecoderDelayedSuccess) {
            Render(source, buffers);
            float sample = ((float *)buffers->mBuffers[0].mData)[0];
            Check(sample > 0.179 && sample < 0.182, @"Delayed seek reaches requested source samples");
        } else {
            generation = [source seekToTime:source.duration];
            Render(source, buffers);
            info = Render(source, buffers);
            Check(info.seekGeneration == generation && info.status == HugPlaybackStatusFinished,
                @"Short EOF does not leave end seek waiting forever");
        }
    }
    HugAudioBufferListFree(buffers, YES);
}

static void TestPrimeTimeout(void)
{
    ControlledAudioFile *file = [[ControlledAudioFile alloc] initWithMode:DecoderPrimeTimeout];
    HugAudioSource *source = Source(file, 48000);
    Check(![source prepareWithStartTime:0 stopTime:0 padding:0 completionHandler:nil], @"Stalled initial read times out");
    Check(source.error.code == HugErrorReadTooSlow && [source seekToTime:10] == 0,
        @"Prime timeout retains read-too-slow error and rejects seeking");
    dispatch_semaphore_signal(file.resume);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    Check(source.error.code == HugErrorReadTooSlow, @"Late decoder completion preserves timeout error");
}

int main(void)
{
    @autoreleasepool {
        TestEarlyFailure(DecoderOpenFailure);
        TestEarlyFailure(DecoderTrimFailure);
        TestEarlyFailure(DecoderFirstReadFailure);
        for (NSUInteger mode = DecoderDelayedSuccess; mode <= DecoderShortEOF; mode++) {
            TestDeferredSeek(mode, 44100);
            TestDeferredSeek(mode, 48000);
        }
        TestPrimeTimeout();
        printf("PASS: %lu decoder-fault assertions\n", (unsigned long)checks);
    }
    return 0;
}
