#import <Foundation/Foundation.h>
#import "HugAudioFile.h"
#import "HugAudioSource.h"
#import "HugAudioSettings.h"
#import "HugUtils.h"

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

static HugPlaybackInfo Render(HugAudioSource *source, AudioBufferList *buffers)
{
    HugPlaybackInfo info = {0};
    for (UInt32 b = 0; b < buffers->mNumberBuffers; b++) buffers->mBuffers[b].mDataByteSize = 512 * sizeof(float);
    Check(source.inputBlock(512, buffers, &info) == noErr, @"Render succeeds");
    return info;
}

static void TestInitialPosition(NSString *path, double outputRate)
{
    for (NSNumber *padding in @[@0, @1]) {
        HugAudioFile *file = [[HugAudioFile alloc] initWithFileURL:[NSURL fileURLWithPath:path]];
        HugAudioSource *source = [[HugAudioSource alloc] initWithAudioFile:file settings:@{
            HugAudioSettingSampleRate: @(outputRate), HugAudioSettingFrameSize: @512
        }];
        __block BOOL decoded = NO;
        Check([source prepareWithStartTime:2 stopTime:12 padding:padding.doubleValue initialTime:5 completionHandler:^(HugAudioSource *s) {
            decoded = YES;
        }], @"Cue prepares at an initial position within the existing trim");
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!decoded && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        Check(decoded && !source.error, @"Cued source finishes decoding");
        Check(fabs(source.duration - 10) < 0.001, @"Cue preserves the full seekable duration");
        AudioBufferList *buffers = HugAudioBufferListCreate(2, 512, YES);
        HugPlaybackInfo info = Render(source, buffers);
        if (padding.boolValue) {
            Check(info.status == HugPlaybackStatusWaiting && fabs(info.timeRemaining - 5) < 0.001,
                @"Auto gap reports the duration remaining after the cue");
            for (NSUInteger cycle = 0; cycle < 300 && info.status == HugPlaybackStatusWaiting; cycle++) info = Render(source, buffers);
        }
        Check(info.status == HugPlaybackStatusPlaying && fabs(info.timeElapsed - 5) < 0.1,
            @"First playback starts from the cue, including after auto gap");
        if ([path.lastPathComponent isEqualToString:@"position-ramp.wav"]) {
            Render(source, buffers);
            float sample = ((float *)buffers->mBuffers[0].mData)[256];
            Check(sample > 0.069 && sample < 0.072, @"First cued audio is absolute second 7, without an intro buffer");
        }
        UInt32 generation = [source seekToTime:1];
        Render(source, buffers);
        info = Render(source, buffers);
        Check(info.seekGeneration == generation && fabs(info.timeElapsed - 1) < 0.1,
            @"Seeking can reach audio before the one-time cue");
        for (NSUInteger cycle = 0; cycle < 1500 && info.status != HugPlaybackStatusFinished; cycle++) info = Render(source, buffers);
        Check(info.status == HugPlaybackStatusFinished, @"Cued source completes normally after a backward seek");
        HugAudioBufferListFree(buffers, YES);
    }
}

static void TestLateInitialPosition(NSString *path, double outputRate)
{
    HugAudioFile *file = [[HugAudioFile alloc] initWithFileURL:[NSURL fileURLWithPath:path]];
    Check([file open], @"Open late-cue fixture");
    double duration = file.fileLengthFrames / file.sampleRate;
    if (duration < 340) return;
    HugAudioSource *source = [[HugAudioSource alloc] initWithAudioFile:file settings:@{
        HugAudioSettingSampleRate: @(outputRate), HugAudioSettingFrameSize: @512
    }];
    __block BOOL decoded = NO;
    double started = NSDate.timeIntervalSinceReferenceDate;
    Check([source prepareWithStartTime:0 stopTime:0 padding:0 initialTime:330 completionHandler:^(HugAudioSource *s) {
        decoded = YES;
    }], @"Late cue primes within the production five-second limit");
    double priming = NSDate.timeIntervalSinceReferenceDate - started;
    printf("LATE-CUE %s %.0fHz prime=%.3fs\n", path.lastPathComponent.UTF8String, outputRate, priming);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!decoded && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    Check(decoded && !source.error, @"Late cue decoding finishes without error");
    Check(fabs(source.duration - duration) < 0.01, @"Late cue retains the complete seek range");
    AudioBufferList *buffers = HugAudioBufferListCreate(2, 512, YES);
    HugPlaybackInfo info = Render(source, buffers);
    Check(info.status == HugPlaybackStatusPlaying && fabs(info.timeElapsed - 330) < 0.1, @"Late cue begins at 5:30");
    Check([source seekToTime:1] != 0, @"Late-cued track still accepts a backward seek");
    Render(source, buffers);
    info = Render(source, buffers);
    Check(fabs(info.timeElapsed - 1) < 0.1, @"Backward seek reaches the opening after a late cue");
    HugAudioBufferListFree(buffers, YES);
}

static void TestFile(NSString *path, double outputRate)
{
    HugAudioFile *file = [[HugAudioFile alloc] initWithFileURL:[NSURL fileURLWithPath:path]];
    HugAudioSource *source = [[HugAudioSource alloc] initWithAudioFile:file settings:@{
        HugAudioSettingSampleRate: @(outputRate), HugAudioSettingFrameSize: @512
    }];
    __block BOOL finished = NO;
    Check([source prepareWithStartTime:2 stopTime:12 padding:1 completionHandler:^(HugAudioSource *s) {
        finished = YES;
    }], @"Prepare trimmed source");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!finished && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    Check(finished && !source.error, @"Background decoding completes");
    Check(fabs(source.duration - 10) < 0.001, @"Trim duration preserved");
    AudioBufferList *buffers = HugAudioBufferListCreate(2, 512, YES);
    HugPlaybackInfo info = Render(source, buffers);
    Check(info.status == HugPlaybackStatusWaiting && info.timeElapsed < 0, @"Initial gap is present");
    Check(![source seekToTime:NAN] && ![source seekToTime:INFINITY], @"Nonfinite positions rejected");

    UInt32 generation = [source seekToTime:5];
    Render(source, buffers);
    Check(fabs(((float *)buffers->mBuffers[0].mData)[511]) < 0.000001, @"Seek fades old audio to zero");
    info = Render(source, buffers);
    Check(fabs(((float *)buffers->mBuffers[0].mData)[0]) < 0.000001, @"Seek fades new audio from zero");
    Check(info.seekGeneration == generation && fabs(info.timeElapsed - 5) < 0.1, @"Seek uses playable-relative time and clears gap");
    Check(fabs(info.timeElapsed + info.timeRemaining - 10) < 0.001, @"Elapsed plus remaining equals trimmed duration");
    Render(source, buffers);
    float peak = 0;
    if ([path.lastPathComponent isEqualToString:@"position-ramp.wav"]) {
        float sample = ((float *)buffers->mBuffers[0].mData)[0];
        Check(sample > 0.069 && sample < 0.072, @"Decoded sample comes from absolute second 7, including the 2-second trim");
    }
    for (UInt32 f = 0; f < 512; f++) {
        float l = ((float *)buffers->mBuffers[0].mData)[f];
        float r = ((float *)buffers->mBuffers[1].mData)[f];
        Check(isfinite(l) && isfinite(r), @"Finite audio after seek");
        peak = MAX(peak, fabsf(l));
    }
    Check(peak > 0, @"Seek produces audio");

    for (NSUInteger i = 0; i < 200; i++) generation = [source seekToTime:(i % 8) + 0.25];
    Render(source, buffers);
    info = Render(source, buffers);
    Check(info.seekGeneration == generation && fabs(info.timeElapsed - 7.25) < 0.1, @"Latest rapid seek wins");
    Check(source.audioFile == file, @"Seeks retain the existing decoder");

    generation = [source seekToTime:-200];
    Render(source, buffers);
    info = Render(source, buffers);
    Check(info.seekGeneration == generation && info.timeElapsed < 0.1, @"Negative time clamps to playable start");
    generation = [source seekToTime:10000];
    Render(source, buffers);
    info = Render(source, buffers);
    Check(info.seekGeneration == generation && info.status == HugPlaybackStatusFinished, @"Beyond-end time clamps to playable end");
    generation = [source seekToTime:2];
    Render(source, buffers);
    info = Render(source, buffers);
    Check(info.seekGeneration == generation && info.status == HugPlaybackStatusPlaying && fabs(info.timeElapsed - 2) < 0.1,
        @"Backward seek can recover a just-finished render buffer");
    HugAudioBufferListFree(buffers, YES);
    printf("PASS: %s at %.0f Hz output\n", path.lastPathComponent.UTF8String, outputRate);
    TestInitialPosition(path, outputRate);
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        Check(argc > 1, @"Pass at least one audio fixture");
        for (int i = 1; i < argc; i++) {
            TestFile(@(argv[i]), 44100);
            TestFile(@(argv[i]), 48000);
            TestLateInitialPosition(@(argv[i]), 44100);
            TestLateInitialPosition(@(argv[i]), 48000);
        }
        NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        Check([[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL], @"Create temporary marker fixture");
        NSURL *url = [directory URLByAppendingPathComponent:@"position-ramp.wav"];
        AudioStreamBasicDescription format = {48000, kAudioFormatLinearPCM, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 4, 1, 4, 1, 32, 0};
        AudioFileID marker;
        Check(AudioFileCreateWithURL((__bridge CFURLRef)url, kAudioFileWAVEType, &format, kAudioFileFlags_EraseFile, &marker) == noErr, @"Create position-encoded WAV");
        UInt32 count = 48000 * 18;
        float *samples = calloc(count, sizeof(float));
        for (UInt32 f = 0; f < count; f++) samples[f] = (float)f / 48000 / 100;
        UInt32 bytes = count * sizeof(float);
        Check(AudioFileWriteBytes(marker, NO, 0, &bytes, samples) == noErr, @"Write position markers");
        AudioFileClose(marker);
        free(samples);
        TestFile(url.path, 44100);
        TestFile(url.path, 48000);
        [[NSFileManager defaultManager] removeItemAtURL:directory error:NULL];
        printf("PASS: %lu audio assertions\n", (unsigned long)checks);
    }
    return 0;
}
