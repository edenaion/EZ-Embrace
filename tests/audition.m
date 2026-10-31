#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import "AuditionPlayer.h"
#import "AuditionRoute.h"
#import "Preferences.h"
#import "HugAudioDevice.h"

NSString * const EmbraceMappedEffect10BandEQ = @"Test EQ";
NSString * const PlayerWillConfigureOutputNotification = @"PlayerWillConfigureOutput";
NSString *GetAppBuildString(void) { return @"1261"; }
NSUInteger GetCombinedBuildNumber(NSString *s) { return s.integerValue; }
void EmbraceLog(NSString *category, NSString *format, ...)
{
    va_list args; va_start(args, format);
    NSLog(@"%@: %@", category, [[NSString alloc] initWithFormat:format arguments:args]);
    va_end(args);
}

static AudioDeviceID sMainDevice;
@implementation HugAudioDevice
+ (instancetype) placeholderDevice { return [self new]; }
+ (instancetype) bestDefaultDevice { return [self new]; }
+ (instancetype) archivedDeviceWithDeviceUID:(NSString *)uid name:(NSString *)name { return [self new]; }
- (NSString *) name { return @"Test main device"; }
- (NSString *) deviceUID { return @"BuiltInSpeakerDevice"; }
- (AudioObjectID) objectID { return sMainDevice; }
@end

@interface AuditionPlayer (TestAccess)
- (AVAudioPlayer *) _makePlayerForURL:(NSURL *)url error:(NSError **)error;
- (void) _shutdown;
@end
@interface DelayedAuditionPlayer : AuditionPlayer
@property dispatch_semaphore_t entered;
@property dispatch_semaphore_t released;
@end
@implementation DelayedAuditionPlayer
- (AVAudioPlayer *) _makePlayerForURL:(NSURL *)url error:(NSError **)error
{
    dispatch_semaphore_signal(self.entered);
    dispatch_semaphore_wait(self.released, DISPATCH_TIME_FOREVER);
    return [super _makePlayerForURL:url error:error];
}
@end

static NSUInteger sAssertions;
static AudioDeviceID sAggregate;
static void Check(BOOL condition, NSString *message)
{
    sAssertions++;
    if (!condition) {
        if (sAggregate) AudioHardwareDestroyAggregateDevice(sAggregate);
        NSLog(@"FAIL: %@", message); exit(1);
    }
}
static void Pump(NSTimeInterval seconds)
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    do { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]]; }
    while (end.timeIntervalSinceNow > 0);
}
static BOOL Wait(BOOL (^predicate)(void), NSTimeInterval seconds)
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    do { if (predicate()) return YES; Pump(.02); } while (end.timeIntervalSinceNow > 0);
    return predicate();
}
static NSURL *Fixture(NSString *name)
{
    NSString *folder = @EZ_EMBRACE_TEST_ROOT "/dev-docs/computer-use-qa/261015_134000_ez-embrace_tahoe-baseline/fixtures/";
    return [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];
}
static NSUUID *StartAt(AuditionPlayer *player, NSURL *url, NSTimeInterval startTime)
{
    NSUUID *request = [player previewURL:url title:url.lastPathComponent artist:@"Synthetic QA" startTime:startTime endTime:0];
    Check(request != nil, @"Preview returns an ownership identifier");
    Check(Wait(^BOOL{ return player.state == AuditionStatePlaying || player.state == AuditionStateError; }, 5), @"Preparation completes");
    Check(player.state == AuditionStatePlaying, [@"Preview starts: " stringByAppendingString:player.message]);
    return request;
}

static void Start(AuditionPlayer *player, NSURL *url) { StartAt(player, url, 0); }

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:@"com.ezscape.EZEmbrace.AuditionQA"];
        NSArray *devices = AuditionOutputDevices();
        AudioDeviceID preview = 0;
        for (NSDictionary *device in devices) {
            if ([device[@"uid"] isEqual:@"BuiltInSpeakerDevice"]) sMainDevice = [device[@"deviceID"] unsignedIntValue];
            if ([device[@"uid"] isEqual:@"BlackHole2ch_UID"]) preview = [device[@"deviceID"] unsignedIntValue];
        }
        Check(sMainDevice && preview, @"Explicit built-in and BlackHole 2ch fixtures available");
        NSError *error = nil;
        Check(!AuditionResolveOutput(@"", sMainDevice, &error) && error.localizedDescription.length, @"Disabled refuses playback");
        Check(!AuditionResolveOutput(@"missing.qa.uid", sMainDevice, NULL), @"Missing UID refuses playback");
        Check(!AuditionResolveOutput(@"BuiltInSpeakerDevice", sMainDevice, NULL), @"Same device refused");
        Check(!AuditionResolveOutput(@"BlackHole2ch_UID", 0, NULL), @"Unavailable main refused");
        Check(AuditionResolveOutput(@"BlackHole2ch_UID", sMainDevice, NULL) == preview, @"Exact distinct route accepted");
        Check(AuditionOutputsOverlap(0, preview), @"Unknown endpoint fails closed");
        NSString *uid = [NSString stringWithFormat:@"com.ezscape.ezembrace.audition-qa.%d", getpid()];
        NSDictionary *composition = @{
            @kAudioAggregateDeviceNameKey:@"EZ-Embrace Audition QA Output", @kAudioAggregateDeviceUIDKey:uid,
            @kAudioAggregateDeviceIsPrivateKey:@NO, @kAudioAggregateDeviceMasterSubDeviceKey:@"BlackHole2ch_UID",
            @kAudioAggregateDeviceSubDeviceListKey:@[@{@kAudioSubDeviceUIDKey:@"BlackHole2ch_UID"}]
        };
        Check(AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition, &sAggregate) == noErr, @"Create disposable aggregate");
        Pump(.5);
        Check(AuditionOutputsOverlap(sAggregate, preview), @"Aggregate backing overlap refused");
        Check(!AuditionResolveOutput(uid, preview, NULL), @"Aggregate cannot share main endpoint");

        Preferences *preferences = [Preferences sharedInstance];
        Check(preferences.auditionOutputDeviceUID.length == 0 && preferences.auditionVolumePercent == 25, @"Safe persistent defaults");
        __block NSUInteger genericChanges = 0, auditionChanges = 0;
        id generic = [[NSNotificationCenter defaultCenter] addObserverForName:PreferencesDidChangeNotification object:preferences queue:nil usingBlock:^(NSNotification *note){ genericChanges++; }];
        id audition = [[NSNotificationCenter defaultCenter] addObserverForName:AuditionPreferencesDidChangeNotification object:preferences queue:nil usingBlock:^(NSNotification *note){ auditionChanges++; }];
        preferences.auditionOutputDeviceUID = @"BlackHole2ch_UID";
        preferences.auditionVolumePercent = 12;
        Check(genericChanges == 0 && auditionChanges == 2, @"Preview settings do not notify main reconfiguration");
        Preferences *reloaded = [Preferences new];
        Check([reloaded.auditionOutputDeviceUID isEqual:@"BlackHole2ch_UID"] && reloaded.auditionVolumePercent == 12, @"UID and volume persist");
        [[NSNotificationCenter defaultCenter] removeObserver:generic];
        [[NSNotificationCenter defaultCenter] removeObserver:audition];
        NSDictionary *mainBefore = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        AuditionPlayer *player = [[AuditionPlayer alloc] initWithPreferences:preferences];
        NSUUID *offsetRequest = StartAt(player, Fixture(@"01_WAV_44k_stereo.wav"), 8);
        Check(player.position >= 8 && player.position < 9, @"Offset preview begins at the requested absolute file time");
        [player stopPreviewWithIdentifier:NSUUID.UUID];
        Pump(.2);
        Check(player.state == AuditionStatePlaying && [player.requestIdentifier isEqual:offsetRequest], @"Unknown owner cannot stop active preview");
        NSUUID *replacementRequest = StartAt(player, Fixture(@"02_AIFF_48k_mono.aiff"), 4);
        [player stopPreviewWithIdentifier:offsetRequest];
        Pump(.2);
        Check(player.state == AuditionStatePlaying && [player.requestIdentifier isEqual:replacementRequest], @"Replaced owner cannot stop newer preview");
        [player stopPreviewWithIdentifier:replacementRequest];
        Check(Wait(^BOOL{ return player.state == AuditionStateStopped; }, 2), @"Current owner stops its preview");
        [player previewURL:Fixture(@"01_WAV_44k_stereo.wav") title:@"Bounded preview" artist:@"Synthetic QA" startTime:8 endTime:8.25];
        Check(Wait(^BOOL{ return player.state == AuditionStateStopped; }, 2), @"Bounded preview stops at the track playback endpoint");
        Check([player.message isEqual:@"Preview finished"] && fabs(player.position - 8.25) < .02, @"Bounded preview reports its exact natural endpoint");
        for (NSString *file in @[@"01_WAV_44k_stereo.wav", @"02_AIFF_48k_mono.aiff", @"03_AAC_44k_stereo.m4a", @"04_MP3_48k_stereo.mp3", @"05_FLAC_48k_stereo.flac"]) {
            Start(player, Fixture(file));
            Check(Wait(^BOOL{ return player.position > .2; }, 2), @"Position advances");
            [player pause];
            Check(Wait(^BOOL{ return player.state == AuditionStatePaused; }, 2), @"Pause published");
            NSTimeInterval paused = player.position;
            Pump(.2);
            Check(fabs(player.position - paused) < .08, @"Paused position holds");
            [player seekToTime:8];
            Check(Wait(^BOOL{ return fabs(player.position - 8) < .15; }, 2) && player.state == AuditionStatePaused, @"Seek preserves pause");
            [player resume];
            Check(Wait(^BOOL{ return player.state == AuditionStatePlaying && player.position > 8.15; }, 2), @"Resume advances from seek");
            [player seekToTime:-5];
            Check(Wait(^BOOL{ return player.position < 1; }, 2), @"Backward seek clamps to zero");
            [player seekToTime:player.duration - .2];
            Check(Wait(^BOOL{ return player.state == AuditionStateStopped; }, 3), @"Natural end releases preview");
            Check([player.message isEqual:@"Preview finished"], @"Natural end is not an error");
        }
        Start(player, Fixture(@"01_WAV_44k_stereo.wav"));
        [player pause];
        Check(Wait(^BOOL{ return player.state == AuditionStatePaused; }, 2), @"Pause before end-boundary seek");
        [player seekToTime:100000];
        Check(Wait(^BOOL{ return player.position >= player.duration - .1; }, 2), @"Past-end seek clamps to file end");
        [player resume];
        Check(Wait(^BOOL{ return player.state == AuditionStateStopped; }, 3), @"Resuming at end finishes instead of restarting at zero");
        [player previewURL:[NSURL fileURLWithPath:@"/nonexistent/qa.wav"] title:@"Missing" artist:@""];
        Check(Wait(^BOOL{ return player.state == AuditionStateError; }, 3), @"Missing file reports error");
        NSString *corrupt = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        [@"Not an audio file" writeToFile:corrupt atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [player previewURL:[NSURL fileURLWithPath:corrupt] title:@"Corrupt" artist:@""];
        Check(Wait(^BOOL{ return player.state == AuditionStateError; }, 3), @"Corrupt file reports error");
        [[NSFileManager defaultManager] removeItemAtPath:corrupt error:NULL];
        for (NSUInteger index = 0; index < 12; index++) [player previewURL:Fixture(@"01_WAV_44k_stereo.wav") title:@(index).stringValue artist:@""];
        Check(Wait(^BOOL{ return player.state == AuditionStatePlaying && [player.title isEqual:@"11"]; }, 5), @"Rapid replacement publishes only newest generation");
        [player stop];
        Check(Wait(^BOOL{ return player.state == AuditionStateStopped; }, 2), @"Stop releases current player");
        preferences.auditionOutputDeviceUID = uid;
        for (NSUInteger round = 0; round < 5; round++) {
            Start(player, Fixture(@"01_WAV_44k_stereo.wav"));
            if (round % 2) Check(Wait(^BOOL{ return player.position > .2; }, 2), @"Advance before loss");
            if (round == 4) {
                [player pause];
                Check(Wait(^BOOL{ return player.state == AuditionStatePaused; }, 2), @"Pause before loss");
            }
            Check(AudioHardwareDestroyAggregateDevice(sAggregate) == noErr, @"Remove active disposable output");
            sAggregate = 0;
            BOOL lossStopped = Wait(^BOOL{ return player.state == AuditionStateError; }, 3);
            if (!lossStopped) NSLog(@"Loss state %ld: %@; route %u; devices %@", (long)player.state, player.message,
                (unsigned)AuditionResolveOutput(uid, sMainDevice, NULL), AuditionOutputDevices());
            Check(lossStopped, @"Device loss stops production preview");
            Check(AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition, &sAggregate) == noErr, @"Recreate output");
            Pump(.6);
            Check(player.state == AuditionStateError, @"Reconnection never auto-resumes");
        }
        Start(player, Fixture(@"01_WAV_44k_stereo.wav"));
        [player pause];
        Check(Wait(^BOOL{ return player.state == AuditionStatePaused; }, 2), @"Pause before output change");
        preferences.auditionOutputDeviceUID = @"BlackHole2ch_UID";
        Check(Wait(^BOOL{ return player.state == AuditionStateStopped; }, 2), @"Output change stops paused decoder");
        Start(player, Fixture(@"01_WAV_44k_stereo.wav"));
        [[NSNotificationCenter defaultCenter] postNotificationName:PlayerWillConfigureOutputNotification object:nil userInfo:@{@"deviceID":@(sMainDevice)}];
        Check([player valueForKey:@"player"] != nil && player.state == AuditionStatePlaying, @"Separate main configuration preserves preview");
        [[NSNotificationCenter defaultCenter] postNotificationName:PlayerWillConfigureOutputNotification object:nil userInfo:@{@"deviceID":@(preview)}];
        Check([player valueForKey:@"player"] == nil, @"Preview hardware released before main configuration notification returns");
        Check(Wait(^BOOL{ return player.state == AuditionStateStopped; }, 2), @"Conflicting main hardware configuration stops preview first");
        [player _shutdown];
        AudioHardwareDestroyAggregateDevice(sAggregate); sAggregate = 0;

        DelayedAuditionPlayer *delayed = [[DelayedAuditionPlayer alloc] initWithPreferences:preferences];
        delayed.entered = dispatch_semaphore_create(0); delayed.released = dispatch_semaphore_create(0);
        [delayed previewURL:Fixture(@"01_WAV_44k_stereo.wav") title:@"Cancelled" artist:@""];
        Check(dispatch_semaphore_wait(delayed.entered, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0, @"Delayed preparation reached");
        [delayed stop];
        dispatch_semaphore_signal(delayed.released);
        Check(Wait(^BOOL{ return delayed.state == AuditionStateStopped; }, 3), @"Stop cancels in-flight decoder preparation");
        Pump(.5);
        Check(delayed.state == AuditionStateStopped && delayed.position == 0, @"Stale preparation cannot restart preview");
        [delayed _shutdown];
        NSDictionary *after = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        for (NSString *key in @[@"mainOutputAudioDevice", @"mainOutputSampleRate", @"mainOutputFrames", @"mainOutputUsesHogMode", @"mainOutputResetsVolume", @"effects", @"volume"]) {
            Check([mainBefore[key] isEqual:after[key]] || (!mainBefore[key] && !after[key]), [@"Main preference unchanged: " stringByAppendingString:key]);
        }
        printf("Audition routing/lifecycle: %lu assertions passed.\n", (unsigned long)sAssertions);
    }
    return 0;
}
