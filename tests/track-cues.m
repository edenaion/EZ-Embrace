#import <Cocoa/Cocoa.h>
#import <stdarg.h>
#import "Track.h"
#import "TrackKeys.h"
#import "MusicAppManager.h"
#import "AppDelegate.h"
#import "ScriptsManager.h"
#import "WorkerService.h"
#import "Utils.h"
#import "Log.h"

NSString * const MusicAppManagerDidUpdateLibraryMetadataNotification = @"MusicAppManagerDidUpdateLibraryMetadataNotification";

@implementation MusicAppLibraryMetadata
@end

@interface Track (TrackGenreTestPrivate)
- (void)_readMetadataViaManagerWithFileURL:(NSURL *)fileURL;
@end

static NSString *sSupportDirectory;
static AppDelegate *sAppDelegate;
static NSUInteger sAssertions;

@interface MusicAppManager ()
@property (nonatomic) MusicAppLibraryMetadata *testLibraryMetadata;
@end

@implementation MusicAppManager
+ (instancetype)sharedInstance
{
    static MusicAppManager *result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ result = [MusicAppManager new]; });
    return result;
}
- (MusicAppLibraryMetadata *)libraryMetadataForFileURL:(NSURL *)url { return self.testLibraryMetadata; }
- (BOOL)didParseLibrary { return self.testLibraryMetadata != nil; }
- (MusicAppPasteboardMetadata *)pasteboardMetadataForFileURL:(NSURL *)url { return nil; }
@end

@implementation ScriptsManager
+ (instancetype)sharedInstance
{
    static ScriptsManager *result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ result = [ScriptsManager new]; });
    return result;
}
- (void)callMetadataAvailableWithTrack:(Track *)track {}
@end

@interface CueTestWorker : NSObject <WorkerProtocol>
@end
@implementation CueTestWorker
- (void)cancelUUID:(NSUUID *)uuid {}
- (void)performTrackCommand:(WorkerTrackCommand)command UUID:(NSUUID *)uuid
               bookmarkData:(NSData *)bookmarkData originalFilename:(NSString *)originalFilename
                      reply:(void (^)(NSDictionary *))reply
{
    // Keep this harness independent of the app worker and metadata readers.
}
- (void)performLibraryParseWithReply:(void (^)(NSDictionary *))reply {}
- (void)performMusicLibraryFetchWithReply:(void (^)(NSDictionary *, NSString *))reply {}
@end

@implementation AppDelegate
- (id<WorkerProtocol>)workerProxyWithErrorHandler:(void (^)(NSError *))handler
{
    static CueTestWorker *worker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ worker = [CueTestWorker new]; });
    return worker;
}
@end

NSString *GetApplicationSupportDirectory(void) { return sSupportDirectory; }
AppDelegate *GetAppDelegate(void) { return sAppDelegate; }
NSString *GetSimplifiedString(NSString *string) { return [string lowercaseString]; }
Tonality GetTonalityForString(NSString *string) { return Tonality_Unknown; }
void EmbraceLog(NSString *category, NSString *format, ...) {}

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

static BOOL WaitUntilResolved(Track *track, NSTimeInterval timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (track.isResolvingURLs && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return !track.isResolvingURLs;
}

static Track *MakeTrack(NSURL *url)
{
    Track *track = [Track trackWithFileURL:url];
    Check(track != nil, @"create production Track from disposable fixture");
    Check(WaitUntilResolved(track, 5), @"resolve disposable fixture without app services");
    Check(track.error == nil, @"fixture resolves without track error");
    [track setValue:@120.0 forKey:@"decodedDuration"];
    [track setValue:@0.0 forKey:@"startTime"];
    [track setValue:@0.0 forKey:@"stopTime"];
    return track;
}

int main(void)
{
    @autoreleasepool {
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"EZ-Embrace-track-cues-%@", NSUUID.UUID.UUIDString]];
        sSupportDirectory = directory;
        sAppDelegate = [AppDelegate new];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"songTypeOverrides"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"songRowColorOverrides"];
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
        Check(error == nil, @"create isolated support directory");

        NSString *fixturePath = [directory stringByAppendingPathComponent:@"cue-fixture.wav"];
        [@"disposable cue fixture" writeToFile:fixturePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        Check(error == nil, @"create disposable file for bookmark/persistence path");
        Track *track = MakeTrack([NSURL fileURLWithPath:fixturePath]);

        Check(track.genreHighlightOverride == TrackGenreHighlightOverrideAutomatic,
            @"new tracks use automatic genre highlighting");
        track.genreHighlightOverride = TrackGenreHighlightOverrideGreen;
        Check(track.genreHighlightOverride == TrackGenreHighlightOverrideGreen,
            @"track accepts manual green highlight override");
        Track *sameSong = MakeTrack([NSURL fileURLWithPath:fixturePath]);
        Check(sameSong.genreHighlightOverride == TrackGenreHighlightOverrideGreen,
            @"a new Set List entry for the same song inherits its saved song type");
        sameSong.genreHighlightOverride = TrackGenreHighlightOverrideNormal;
        Track *laterSetEntry = MakeTrack([NSURL fileURLWithPath:fixturePath]);
        Check(laterSetEntry.genreHighlightOverride == TrackGenreHighlightOverrideNormal,
            @"traditional Tango correction survives a later Set List addition");
        track.setListColorOverride = [NSColor colorWithSRGBRed:0.20 green:0.55 blue:0.85 alpha:0.40];
        Check(fabs(track.setListColorOverride.alphaComponent - 1) < 0.001,
            @"per-track cosmetic color stores as an opaque Set List background");
        Track *sameSongColor = MakeTrack([NSURL fileURLWithPath:fixturePath]);
        NSColor *sameSongSavedColor = [sameSongColor.setListColorOverride colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        Check(sameSongSavedColor && fabs(sameSongSavedColor.redComponent - 0.20) < 0.001 &&
              fabs(sameSongSavedColor.greenComponent - 0.55) < 0.001,
            @"a new Set List entry for the same song inherits its saved row color");

        CheckNear(track.cueStartTime, 0, @"new tracks default to cue zero");
        CheckNear(track.cueOffset, 0, @"zero cue has no imported-play offset");
        CheckNear(track.queuedPlayDuration, 120, @"zero cue preserves full queue duration");

        [track setValue:@10.0 forKey:@"startTime"];
        [track setValue:@100.0 forKey:@"stopTime"];
        CheckNear(track.playDuration, 90, @"Music trims define existing playDuration");
        track.cueStartTime = NAN;
        CheckNear(track.cueStartTime, 0, @"nonfinite cue is sanitized to zero");
        track.cueStartTime = INFINITY;
        CheckNear(track.cueStartTime, 0, @"infinite cue is sanitized to zero");
        track.cueStartTime = -5;
        CheckNear(track.cueStartTime, 0, @"negative cue is sanitized to zero");
        track.cueStartTime = 5;
        CheckNear(track.cueStartTime, 10, @"cue before imported trim clamps to trim start");
        CheckNear(track.cueOffset, 0, @"clamped cue does not add queue offset");

        track.cueStartTime = 50;
        CheckNear(track.cueStartTime, 50, @"valid cue is kept as absolute file time");
        CheckNear(track.cueOffset, 40, @"cue offset is relative to Music trim start");
        CheckNear(track.playDuration, 90, @"cue leaves existing Music-trim playDuration unchanged");
        CheckNear(track.queuedPlayDuration, 50, @"queued duration subtracts cue offset once");
        track.cueStartTime = 100;
        CheckNear(track.cueStartTime, 0, @"cue at the exclusive playable end is cleared");
        track.cueStartTime = 99;
        CheckNear(track.cueOffset, 89, @"cue immediately before playable end remains valid");
        CheckNear(track.queuedPlayDuration, 1, @"near-end cue leaves positive queued duration");

        track.cueStartTime = 50;
        NSUInteger playedRevision = track.cueRevision;
        track.cueStartTime = 60;
        Check(track.cueRevision != playedRevision, @"saving a different cue creates a new playback revision");
        [track clearCueForPlaybackRevision:playedRevision];
        CheckNear(track.cueStartTime, 60, @"completion from an older playback preserves a newer pending cue");
        NSUInteger currentRevision = track.cueRevision;
        [track clearCueForPlaybackRevision:currentRevision];
        CheckNear(track.cueStartTime, 0, @"completion for the cue revision in use clears that cue");

        track.cueStartTime = 50;
        NSString *statePath = [directory stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"Tracks/%@.plist", track.UUID.UUIDString]];
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:statePath];
        Check([saved[@"genreHighlightOverride"] integerValue] == TrackGenreHighlightOverrideGreen,
            @"genre highlight override is serialized with the Set List entry");
        Check([saved[@"setListColorOverride"] count] == 4,
            @"per-track cosmetic color is serialized as portable sRGB components");
        CheckNear([saved[@"cueStartTime"] doubleValue], 50, @"nonzero cue is serialized with the per-entry state");
        Track *reloaded = [Track trackWithUUID:track.UUID];
        Check(reloaded != nil && WaitUntilResolved(reloaded, 5), @"reload per-entry state through production initializer");
        CheckNear(reloaded.cueStartTime, 50, @"cue survives a persisted-state reload");
        Check(reloaded.genreHighlightOverride == TrackGenreHighlightOverrideNormal,
            @"latest song-level correction wins over an older per-entry value after reload");
        NSColor *reloadedColor = [reloaded.setListColorOverride colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        Check(reloadedColor && fabs(reloadedColor.redComponent - 0.20) < 0.001 &&
              fabs(reloadedColor.greenComponent - 0.55) < 0.001 &&
              fabs(reloadedColor.blueComponent - 0.85) < 0.001,
            @"per-track cosmetic color survives persisted-state reload");

        MusicAppManager *manager = [MusicAppManager sharedInstance];
        MusicAppLibraryMetadata *metadata = [MusicAppLibraryMetadata new];
        metadata.startTime = 20;
        metadata.stopTime = 90;
        metadata.genre = @"Tango- inst";
        metadata.persistentIdentifier = @"TEST-MUSIC-ID-1";
        manager.testLibraryMetadata = metadata;
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateLibraryMetadataNotification object:manager];
        CheckNear(reloaded.startTime, 20, @"library metadata refresh updates imported trim start");
        CheckNear(reloaded.stopTime, 90, @"library metadata refresh updates imported trim stop");
        Check([reloaded.genre isEqualToString:@"Tango- inst"],
            @"library metadata refresh makes Music genre authoritative in Set List");
        NSString *movedFixturePath = [directory stringByAppendingPathComponent:@"cue-fixture-moved.wav"];
        [@"same Music song at a moved path" writeToFile:movedFixturePath atomically:YES
            encoding:NSUTF8StringEncoding error:&error];
        Check(error == nil, @"create moved-path identity fixture");
        Track *movedLibrarySong = MakeTrack([NSURL fileURLWithPath:movedFixturePath]);
        Check(movedLibrarySong.genreHighlightOverride == TrackGenreHighlightOverrideNormal,
            @"Apple Music persistent ID keeps the traditional correction after a file move");
        NSColor *movedSavedColor = [movedLibrarySong.setListColorOverride colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        Check(movedSavedColor && fabs(movedSavedColor.blueComponent - 0.85) < 0.001,
            @"Apple Music persistent ID keeps the saved row color after a file move");
        movedLibrarySong.setListColorOverride = nil;
        NSString *resetFixturePath = [directory stringByAppendingPathComponent:@"cue-fixture-reset.wav"];
        [@"same Music song after row color reset" writeToFile:resetFixturePath atomically:YES
            encoding:NSUTF8StringEncoding error:&error];
        Check(error == nil, @"create row-color reset fixture");
        Track *resetLibrarySong = MakeTrack([NSURL fileURLWithPath:resetFixturePath]);
        Check(resetLibrarySong.setListColorOverride == nil,
            @"reset row color remains automatic for a later Set List entry");
        [reloaded setValue:@"Electronic" forKey:@"genre"];
        [reloaded _readMetadataViaManagerWithFileURL:reloaded.externalURL];
        Check([reloaded.genre isEqualToString:@"Tango- inst"],
            @"Music genre wins again after embedded metadata is read");
        metadata.genre = @"";
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateLibraryMetadataNotification object:manager];
        Check(reloaded.genre.length == 0,
            @"an empty Music genre remains authoritative and classifies as nontraditional");
        metadata.genre = @"Tango- inst";
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateLibraryMetadataNotification object:manager];
        CheckNear(reloaded.cueStartTime, 50, @"metadata refresh preserves absolute cue position");
        CheckNear(reloaded.cueOffset, 30, @"refreshed trim recomputes cue offset");
        CheckNear(reloaded.playDuration, 70, @"refreshed trims update playDuration independently");
        CheckNear(reloaded.queuedPlayDuration, 40, @"refreshed trims recompute queued duration");

        Track *duplicate = [reloaded duplicatedTrack];
        Check(duplicate != nil && WaitUntilResolved(duplicate, 5), @"duplicate entry resolves independently");
        Check(![duplicate.UUID isEqual:reloaded.UUID], @"duplicate receives a unique entry UUID");
        CheckNear(duplicate.cueStartTime, 0, @"duplicate cue defaults to zero instead of copying single-use state");
        Check(duplicate.setListColorOverride == nil && reloaded.setListColorOverride == nil,
            @"duplicate respects the latest saved automatic row-color reset");
        NSString *duplicateStatePath = [directory stringByAppendingPathComponent:
                                        [NSString stringWithFormat:@"Tracks/%@.plist", duplicate.UUID.UUIDString]];
        NSDictionary *duplicateState = [NSDictionary dictionaryWithContentsOfFile:duplicateStatePath];
        Check(duplicateState[@"cueStartTime"] == nil, @"duplicate state does not serialize the source cue");
        CheckNear(reloaded.cueStartTime, 50, @"duplicate creation leaves source cue unchanged");

        metadata.startTime = 60;
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateLibraryMetadataNotification object:manager];
        CheckNear(reloaded.cueStartTime, 60, @"live trim moving past a cue normalizes it to the new trim start");
        CheckNear(reloaded.cueOffset, 0, @"normalized cue has no offset from the updated trim");
        CheckNear(reloaded.queuedPlayDuration, 30, @"normalized cue preserves the updated trim duration");

        reloaded.cueStartTime = 85;
        metadata.stopTime = 80;
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateLibraryMetadataNotification object:manager];
        CheckNear(reloaded.cueStartTime, 0, @"live trim ending before a cue clears the now out-of-range cue");
        CheckNear(reloaded.cueOffset, 0, @"cleared out-of-range cue has no offset");
        CheckNear(reloaded.queuedPlayDuration, 20, @"cleared cue leaves the updated trimmed duration intact");

        [duplicate clearAndCleanup];
        [movedLibrarySong clearAndCleanup];
        [resetLibrarySong clearAndCleanup];
        [sameSongColor clearAndCleanup];
        [laterSetEntry clearAndCleanup];
        [sameSong clearAndCleanup];
        [reloaded clearAndCleanup];
        [track clearAndCleanup];
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
        printf("PASS: %lu Track cue assertions\n", (unsigned long)sAssertions);
    }
    return 0;
}
