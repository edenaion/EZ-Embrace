// Local QA utility. Captures only the named Embrace process through a private Core Audio tap.
#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <stdatomic.h>
#include <signal.h>
#include <sys/statvfs.h>
#include <libproc.h>
#include <mach/mach_time.h>

#define RING_SAMPLES (1u << 20)
#define MAX_CAPTURE_SECONDS 23100
#define DEFAULT_STARTUP_TIMEOUT_SECONDS 300
#define MAX_STARTUP_TIMEOUT_SECONDS 900
typedef struct {
    float *samples;
    atomic_uint_fast64_t head;
    atomic_uint_fast64_t tail;
    atomic_uint_fast64_t droppedFrames;
    atomic_bool unsupportedLayout;
    atomic_uint_fast64_t firstHostTime;
    UInt32 channels;
} CaptureRing;

static volatile sig_atomic_t interrupted;
static void HandleSignal(int sig) { interrupted = 1; }

static OSStatus CaptureAudio(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *user)
{
    CaptureRing *ring = user;
    if (!input || input->mNumberBuffers == 0) return noErr;
    const AudioBuffer *first = &input->mBuffers[0];
    if (!first->mDataByteSize) return noErr;
    if (!first->mNumberChannels) {
        atomic_store(&ring->unsupportedLayout, true);
        return noErr;
    }
    UInt32 frames = first->mDataByteSize / (sizeof(float) * first->mNumberChannels);
    UInt32 channels = 0;
    for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
        const AudioBuffer *buffer = &input->mBuffers[b];
        if (!buffer->mData || !buffer->mNumberChannels || buffer->mDataByteSize < frames * buffer->mNumberChannels * sizeof(float)) {
            atomic_store(&ring->unsupportedLayout, true);
            return noErr;
        }
        channels += buffer->mNumberChannels;
    }
    if (channels != ring->channels) {
        atomic_store(&ring->unsupportedLayout, true);
        return noErr;
    }
    uint_fast64_t unseen = 0;
    atomic_compare_exchange_strong(&ring->firstHostTime, &unseen, mach_absolute_time());
    uint64_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    uint64_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
    if (head - tail + frames * channels > RING_SAMPLES) {
        atomic_fetch_add(&ring->droppedFrames, frames);
        return noErr;
    }
    for (UInt32 f = 0; f < frames; f++) {
        for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
            const AudioBuffer *buffer = &input->mBuffers[b];
            const float *samples = buffer->mData;
            for (UInt32 c = 0; c < buffer->mNumberChannels; c++) {
                ring->samples[(head++) & (RING_SAMPLES - 1)] = samples[f * buffer->mNumberChannels + c];
            }
        }
    }
    atomic_store_explicit(&ring->head, head, memory_order_release);
    return noErr;
}

static void Require(BOOL condition, NSString *stage)
{
    if (!condition) @throw [NSException exceptionWithName:@"CaptureFailure" reason:stage userInfo:nil];
}
static void Status(OSStatus status, NSString *stage)
{
    Require(status == noErr, [NSString stringWithFormat:@"%@: OSStatus %d", stage, (int)status]);
}
static void WriteJSON(FILE *file, NSDictionary *value)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
    fwrite(data.bytes, 1, data.length, file);
    fputc('\n', file);
    fflush(file);
}

static double HostSeconds(uint64_t start, uint64_t end)
{
    if (!start || end < start) return 0;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    return ((double)(end - start) * timebase.numer / timebase.denom) / 1e9;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 4 || argc > 7) { fprintf(stderr, "Usage: capture EMBRACE_PID SECONDS OUTPUT_DIRECTORY [DEVICE_UID [BUNDLE_ID [STARTUP_TIMEOUT_SECONDS]]]\n"); return 64; }
        pid_t pid = (pid_t)atoi(argv[1]);
        double seconds = atof(argv[2]);
        NSString *directory = @(argv[3]);
        NSString *deviceUID = argc >= 5 ? @(argv[4]) : nil;
        NSString *bundleID = argc >= 6 ? @(argv[5]) : @"com.ezscape.EZEmbrace";
        double startupTimeout = argc >= 7 ? atof(argv[6]) : DEFAULT_STARTUP_TIMEOUT_SECONDS;
        if (![@[@"com.ezscape.EZEmbrace", @"com.ezscape.EZEmbrace.RouteProbe"] containsObject:bundleID]) return 64;
        if (!(pid > 1 && seconds > 0 && seconds <= MAX_CAPTURE_SECONDS)) { fprintf(stderr, "Invalid PID or duration (maximum 6h25m).\n"); return 64; }
        if (!(startupTimeout > 0 && startupTimeout <= MAX_STARTUP_TIMEOUT_SECONDS)) { fprintf(stderr, "Invalid startup timeout (maximum 15m).\n"); return 64; }
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        FILE *stats = fopen([[directory stringByAppendingPathComponent:@"audio-stats.jsonl"] fileSystemRepresentation], "w");
        if (!stats) { perror("Open capture statistics"); return 1; }
        FILE *silences = fopen([[directory stringByAppendingPathComponent:@"silence-intervals.jsonl"] fileSystemRepresentation], "w");
        if (!silences) { perror("Open silence intervals"); fclose(stats); return 1; }
        CaptureRing ring = {0};
        ring.samples = calloc(RING_SAMPLES, sizeof(float));
        atomic_init(&ring.head, 0); atomic_init(&ring.tail, 0);
        atomic_init(&ring.droppedFrames, 0); atomic_init(&ring.unsupportedLayout, false);
        atomic_init(&ring.firstHostTime, 0);
        AudioObjectID tap = kAudioObjectUnknown, aggregate = kAudioObjectUnknown;
        AudioDeviceIOProcID io = NULL;
        ExtAudioFileRef captureFile = NULL;
        BOOL ioRunning = NO;
        int exitCode = 0;
        uint64_t frames = 0, firstSignal = UINT64_MAX, lastSignal = 0, signalFrames = 0;
        uint64_t silenceRun = 0, longestCompletedSilence = 0, nonfinite = 0, clipped = 0;
        float overallPeak = 0;
        double rate = 0;
        NSTimeInterval setupStartedUnix = NSDate.date.timeIntervalSince1970;
        double startedUnix = 0;
        double finishedUnix = 0;
        uint64_t setupStartedHost = mach_absolute_time();
        uint64_t captureStartedHost = 0;
        uint64_t captureFinishedHost = 0;
        NSString *failure = nil;
        signal(SIGINT, HandleSignal); signal(SIGTERM, HandleSignal);
        @try {
            Require(ring.samples != NULL, @"Allocate capture ring");
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            Require([app.bundleIdentifier isEqualToString:bundleID], @"PID belongs to the requested EZ-Embrace QA process");
            AudioObjectPropertyAddress address = {kAudioHardwarePropertyTranslatePIDToProcessObject, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            AudioObjectID process = kAudioObjectUnknown;
            UInt32 size = sizeof(process);
            Status(AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, sizeof(pid), &pid, &size, &process), @"Resolve Embrace audio process");
            Require(process != kAudioObjectUnknown, @"Embrace is connected to Core Audio");
            CATapDescription *description = deviceUID.length
                ? [[CATapDescription alloc] initWithProcesses:@[@(process)] andDeviceUID:deviceUID withStream:0]
                : [[CATapDescription alloc] initStereoMixdownOfProcesses:@[@(process)]];
            description.name = @"EZ-Embrace private QA capture";
            description.privateTap = YES;
            description.muteBehavior = CATapUnmuted;
            if (@available(macOS 26.0, *)) description.processRestoreEnabled = NO;
            Status(AudioHardwareCreateProcessTap(description, &tap), @"Create Embrace-only audio tap");
            address.mSelector = kAudioTapPropertyFormat;
            AudioStreamBasicDescription format = {0}; size = sizeof(format);
            Status(AudioObjectGetPropertyData(tap, &address, 0, NULL, &size, &format), @"Read tap format");
            Require(format.mFormatID == kAudioFormatLinearPCM && (format.mFormatFlags & kAudioFormatFlagIsFloat) && format.mBitsPerChannel == 32 && format.mChannelsPerFrame > 0 && format.mChannelsPerFrame <= 32, @"Tap supplies supported float32 channels");
            ring.channels = format.mChannelsPerFrame;
            rate = format.mSampleRate;
            Require(isfinite(rate) && rate > 0, @"Tap sample rate is valid");
            struct statvfs disk;
            Require(statvfs(directory.fileSystemRepresentation, &disk) == 0, @"Measure capture disk space");
            uint64_t reserve = 10ull * 1024 * 1024 * 1024;
            Require((uint64_t)disk.f_bavail * disk.f_frsize > reserve + 64 * 1024 * 1024, @"Capture starts above the 10 GiB reserve");
            NSDictionary *composition = @{
                @kAudioAggregateDeviceNameKey: @"EZ-Embrace private QA tap",
                @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
                @kAudioAggregateDeviceIsPrivateKey: @YES,
                @kAudioAggregateDeviceTapAutoStartKey: @YES,
                @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapUIDKey: description.UUID.UUIDString, @kAudioSubTapDriftCompensationKey: @YES}]
            };
            Status(AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition, &aggregate), @"Create private tap aggregate");
            AudioStreamBasicDescription pcm = {rate, kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, ring.channels * 2, 1, ring.channels * 2, ring.channels, 16, 0};
            AudioStreamBasicDescription lossless = {0};
            lossless.mSampleRate = rate;
            lossless.mFormatID = kAudioFormatAppleLossless;
            lossless.mFormatFlags = kAppleLosslessFormatFlag_16BitSourceData;
            lossless.mChannelsPerFrame = ring.channels;
            NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"embrace-output.caf"]];
            Status(ExtAudioFileCreateWithURL((__bridge CFURLRef)url, kAudioFileCAFType, &lossless, NULL, kAudioFileFlags_EraseFile, &captureFile), @"Create lossless output CAF");
            UInt32 pcmSize = sizeof(pcm);
            Status(ExtAudioFileSetProperty(captureFile, kExtAudioFileProperty_ClientDataFormat, pcmSize, &pcm), @"Set capture client format");
            Status(AudioDeviceCreateIOProcID(aggregate, CaptureAudio, &ring, &io), @"Register capture callback");
            setupStartedUnix = NSDate.date.timeIntervalSince1970;
            setupStartedHost = mach_absolute_time();
            Status(AudioDeviceStart(aggregate, io), @"Start private audio capture");
            ioRunning = YES;
            WriteJSON(stdout, @{@"status": @"setup", @"pid": @(pid), @"sample_rate": @(rate), @"tap": @(tap), @"aggregate": @(aggregate), @"seconds": @(seconds), @"startup_timeout_seconds": @(startupTimeout), @"setup_started_unix_seconds": @(setupStartedUnix), @"device_uid": deviceUID ?: @"all-process-outputs", @"bundle_id": bundleID});

            while (!interrupted && !(captureStartedHost = atomic_load(&ring.firstHostTime))) {
                Require(kill(pid, 0) == 0, @"Embrace process remains alive during capture startup");
                Require(!atomic_load(&ring.unsupportedLayout), @"Capture buffer layout remains valid during startup");
                Require(HostSeconds(setupStartedHost, mach_absolute_time()) < startupTimeout,
                        @"First audio callback did not arrive before the startup timeout");
                usleep(10000);
            }

            if (!interrupted) {
                startedUnix = setupStartedUnix + HostSeconds(setupStartedHost, captureStartedHost);
                WriteJSON(stdout, @{@"status": @"active", @"pid": @(pid), @"sample_rate": @(rate), @"seconds": @(seconds), @"started_unix_seconds": @(startedUnix), @"first_sample_unix_seconds": @(startedUnix), @"setup_delay_seconds": @(HostSeconds(setupStartedHost, captureStartedHost)), @"device_uid": deviceUID ?: @"all-process-outputs", @"bundle_id": bundleID});
            }

            int16_t converted[65536];
            double lastReportElapsed = 0;
            double sumSquares = 0;
            uint64_t windowSamples = 0;
            float windowPeak = 0;
            BOOL reachedDuration = NO;
            while (!interrupted && captureStartedHost) {
                @autoreleasepool {
                    Require(kill(pid, 0) == 0, @"Embrace process remains alive");
                    Require(!atomic_load(&ring.unsupportedLayout), @"Capture buffer layout remains valid");
                    uint64_t nowHost = mach_absolute_time();
                    double elapsed = HostSeconds(captureStartedHost, nowHost);
                    if (!reachedDuration && elapsed >= seconds) {
                        Status(AudioDeviceStop(aggregate, io), @"Stop private audio capture at requested duration");
                        ioRunning = NO;
                        reachedDuration = YES;
                        captureFinishedHost = mach_absolute_time();
                        finishedUnix = setupStartedUnix + HostSeconds(setupStartedHost, captureFinishedHost);
                    }
                    uint64_t tail = atomic_load_explicit(&ring.tail, memory_order_relaxed);
                    uint64_t head = atomic_load_explicit(&ring.head, memory_order_acquire);
                    UInt32 count = (UInt32)MIN(head - tail, (uint64_t)65536);
                    count -= count % ring.channels;
                    for (UInt32 i = 0; i < count; i += ring.channels) {
                        float peak = 0;
                        for (UInt32 c = 0; c < ring.channels; c++) {
                            float sample = ring.samples[(tail + i + c) & (RING_SAMPLES - 1)];
                            if (!isfinite(sample)) { nonfinite++; sample = 0; }
                            float magnitude = fabsf(sample);
                            if (magnitude >= 1) clipped++;
                            peak = MAX(peak, magnitude);
                            sumSquares += (double)sample * sample;
                            converted[i + c] = (int16_t)lrintf(MAX(-1, MIN(1, sample)) * 32767);
                        }
                        if (peak > 0.000001) {
                            if (firstSignal == UINT64_MAX) firstSignal = frames;
                            lastSignal = frames;
                            signalFrames++;
                            if (silenceRun >= rate * 0.05) {
                                WriteJSON(silences, @{@"start_frame": @(frames - silenceRun), @"end_frame": @(frames), @"start_seconds": @((frames - silenceRun) / rate), @"end_seconds": @(frames / rate), @"duration_seconds": @(silenceRun / rate)});
                            }
                            longestCompletedSilence = MAX(longestCompletedSilence, silenceRun);
                            silenceRun = 0;
                        } else if (firstSignal != UINT64_MAX) silenceRun++;
                        frames++;
                        windowPeak = MAX(windowPeak, peak);
                        overallPeak = MAX(overallPeak, peak);
                    }
                    if (count) {
                        AudioBufferList bufferList = {0};
                        bufferList.mNumberBuffers = 1;
                        bufferList.mBuffers[0].mNumberChannels = ring.channels;
                        bufferList.mBuffers[0].mDataByteSize = count * sizeof(int16_t);
                        bufferList.mBuffers[0].mData = converted;
                        Status(ExtAudioFileWrite(captureFile, count / ring.channels, &bufferList), @"Write lossless captured output");
                        windowSamples += count;
                        atomic_store_explicit(&ring.tail, tail + count, memory_order_release);
                    }
                    if (elapsed - lastReportElapsed >= 1) {
                        struct proc_taskinfo task = {0};
                        proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task));
                        WriteJSON(stats, @{@"elapsed": @(elapsed), @"frames": @(frames), @"rms": @(windowSamples ? sqrt(sumSquares / windowSamples) : 0), @"peak": @(windowPeak), @"rss_bytes": @(task.pti_resident_size), @"dropped_frames": @(atomic_load(&ring.droppedFrames)), @"max_completed_silence_seconds": @(longestCompletedSilence / rate)});
                        lastReportElapsed = elapsed; sumSquares = 0; windowSamples = 0; windowPeak = 0;
                        Require(statvfs(directory.fileSystemRepresentation, &disk) == 0 && (uint64_t)disk.f_bavail * disk.f_frsize > reserve + 32 * 1024 * 1024, @"Maintain 10 GiB capture reserve");
                    }
                    if (reachedDuration && !count && atomic_load_explicit(&ring.tail, memory_order_relaxed) == atomic_load_explicit(&ring.head, memory_order_acquire)) break;
                    if (!count) usleep(10000);
                }
            }
        } @catch (NSException *exception) {
            failure = exception.reason;
            exitCode = 1;
        } @finally {
            if (io && ioRunning) {
                AudioDeviceStop(aggregate, io);
                ioRunning = NO;
            }
            if (!captureFinishedHost) {
                captureFinishedHost = mach_absolute_time();
                finishedUnix = setupStartedUnix + HostSeconds(setupStartedHost, captureFinishedHost);
            }
            if (io) AudioDeviceDestroyIOProcID(aggregate, io);
            if (aggregate) AudioHardwareDestroyAggregateDevice(aggregate);
            if (tap) AudioHardwareDestroyProcessTap(tap);
            if (captureFile) ExtAudioFileDispose(captureFile);
            free(ring.samples);
            fclose(stats);
            fclose(silences);
        }
        uint64_t firstHost = atomic_load(&ring.firstHostTime);
        double firstSampleUnix = firstHost ? setupStartedUnix + HostSeconds(setupStartedHost, firstHost) : 0;
        double elapsed = firstHost ? HostSeconds(firstHost, captureFinishedHost) : 0;
        double setupElapsed = HostSeconds(setupStartedHost, firstHost ? firstHost : captureFinishedHost);
        NSString *outputPath = [directory stringByAppendingPathComponent:@"embrace-output.caf"];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:outputPath error:NULL];
        NSDictionary *summary = @{@"status": failure ? @"error" : (interrupted ? @"interrupted" : @"finished"), @"failure": failure ?: @"", @"pid": @(pid), @"requested_seconds": @(seconds), @"startup_timeout_seconds": @(startupTimeout), @"setup_started_unix_seconds": @(setupStartedUnix), @"setup_elapsed_seconds": @(setupElapsed), @"elapsed": @(elapsed), @"started_unix_seconds": @(firstSampleUnix), @"first_sample_unix_seconds": @(firstSampleUnix), @"finished_unix_seconds": @(finishedUnix), @"sample_rate": @(rate), @"captured_frames": @(frames), @"captured_duration_seconds": @(rate ? frames / rate : 0), @"file_encoding": @"Apple Lossless CAF (16-bit source)", @"output_bytes": attributes[NSFileSize] ?: @0, @"first_signal_frame": @(firstSignal == UINT64_MAX ? 0 : firstSignal), @"last_signal_frame": @(lastSignal), @"signal_frames": @(signalFrames), @"signal_span_seconds": @(firstSignal == UINT64_MAX ? 0 : (lastSignal - firstSignal) / rate), @"signal_seconds": @(rate ? signalFrames / rate : 0), @"peak": @(overallPeak), @"nonfinite_samples": @(nonfinite), @"clipped_samples": @(clipped), @"dropped_frames": @(atomic_load(&ring.droppedFrames)), @"max_completed_silence_seconds": @(rate ? longestCompletedSilence / rate : 0)};
        NSMutableDictionary *identifiedSummary = [summary mutableCopy];
        identifiedSummary[@"device_uid"] = deviceUID ?: @"all-process-outputs";
        identifiedSummary[@"bundle_id"] = bundleID;
        identifiedSummary[@"channels"] = @(ring.channels);
        summary = identifiedSummary;
        NSData *data = [NSJSONSerialization dataWithJSONObject:summary options:NSJSONWritingPrettyPrinted error:NULL];
        [data writeToFile:[directory stringByAppendingPathComponent:@"capture-summary.json"] atomically:YES];
        WriteJSON(stdout, summary);
        return interrupted && !failure ? 130 : exitCode;
    }
}
