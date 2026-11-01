#import <Cocoa/Cocoa.h>
#import "CurrentTrackController.h"
#import "WaveformView.h"
#import "SetlistPlayBar.h"
#import "SetlistMeterView.h"
#import "SetlistSlider.h"
#import "TrackTableRowView.h"
#import "Player.h"
#import "Track.h"
#import "Preferences.h"
#import "HugAudioDevice.h"
#import "HugMeterData.h"

// Keep presentation checks independent of device output and the user's library.
NSString * const EmbraceMappedEffect10BandEQ = @"Test EQ";
NSString *GetAppBuildString(void) { return @"1261"; }
NSUInteger GetCombinedBuildNumber(NSString *s) { return s.integerValue; }
BOOL IsAppearanceDarkAqua(NSView *view) { return NO; }
void PerformWithAppearance(NSAppearance *appearance, void (^block)(void)) { block(); }
CGRect GetInsetBounds(NSView *view) { return NSInsetRect(view.bounds, 1, 1); }
NSColor * const TrackTableViewGetRowHighlightColor(BOOL emphasized) { return NSColor.selectedContentBackgroundColor; }

@interface PresentationTrack : NSObject
@property NSString *title;
@property NSString *artist;
@property NSData *overviewData;
@property TrackStatus trackStatus;
@end
@implementation PresentationTrack
- (BOOL) didAnalyzeLoudness { return YES; }
- (NSTimeInterval) playDuration { return 90; }
- (NSTimeInterval) duration { return 90; }
- (NSTimeInterval) decodedDuration { return 90; }
- (NSTimeInterval) startTime { return 0; }
- (NSTimeInterval) stopTime { return 0; }
@end

@interface Player ()
@property (nonatomic, readwrite) Track *currentTrack;
@end
@interface CurrentTrackController (PresentationTesting)
- (IBAction) changePinning:(id)sender;
- (void) player:(Player *)player didFinishTrack:(Track *)finishedTrack;
@end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-property-implementation"
@implementation Player
+ (instancetype) sharedInstance { static Player *p; if (!p) p = [Player new]; return p; }
- (void) addListener:(id)listener { }
- (void) removeListener:(id)listener { }
- (NSString *) timeElapsedString { return @"0:45"; }
- (NSString *) timeRemainingString { return @"0:45"; }
- (float) percentage { return 0.5; }
- (NSTimeInterval) timeElapsed { return 45; }
- (BOOL) seekToTime:(NSTimeInterval)time forTrack:(Track *)track { return track == self.currentTrack && isfinite(time); }
@end
@implementation HugAudioDevice
+ (instancetype) placeholderDevice { return [self new]; }
+ (instancetype) bestDefaultDevice { return [self new]; }
+ (instancetype) archivedDeviceWithDeviceUID:(NSString *)uid name:(NSString *)name { return [self new]; }
- (NSString *) deviceUID { return @"presentation-device"; }
- (NSString *) name { return @"Presentation test device"; }
@end
#pragma clang diagnostic pop

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSBitmapImageRep *Render(NSView *view)
{
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    return image;
}
int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *domain = NSProcessInfo.processInfo.processName;
        Check([domain isEqualToString:@"ez-embrace-presentation-tests"], @"Isolated preferences domain");
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:domain];
        Preferences *preferences = Preferences.sharedInstance;
        preferences.textSizePercent = 100;
        preferences.usesBoldText = NO;
        preferences.scalesInterfaceWithWindow = NO;
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromSize(NSMakeSize(2204, 112)) forKey:@"InterfaceDesignSize.CurrentTrackWindow"];
        CurrentTrackController *controller = [CurrentTrackController new];
        NSWindow *window = controller.window;
        NSTextField *title = [controller valueForKey:@"titleLabel"];
        NSTextField *artist = [controller valueForKey:@"artistLabel"];
        NSTextField *status = [controller valueForKey:@"statusLabel"];
        WaveformView *wave = [controller valueForKey:@"waveformView"];
        Check(status.hidden && title.hidden && artist.hidden && wave.hidden, @"Stopped metadata and waveform are hidden");
        Check(status.alignment == NSTextAlignmentCenter && title.alignment == NSTextAlignmentCenter && artist.alignment == NSTextAlignmentCenter,
            @"Status, title and artist use centered text");
        Check((window.styleMask & NSWindowStyleMaskResizable) != 0, @"Current Track supports normal resizing");
        PresentationTrack *track = [PresentationTrack new];
        track.title = @"Long title Élan 東京 with enough words to exceed the minimum window width";
        track.artist = @"Long artist name for narrow Current Track layout";
        track.trackStatus = TrackStatusPlaying;
        Player.sharedInstance.currentTrack = (Track *)track;
        Check([status.stringValue isEqualToString:@"Now playing"], @"Current Track identifies active playback");
        Check([title.stringValue isEqualToString:track.title], @"Current title follows the playing track");
        Check([artist.stringValue isEqualToString:track.artist], @"Current artist follows the playing track");
        track.artist = @"Updated artist";
        Check([artist.stringValue isEqualToString:track.artist], @"Artist metadata changes update live");
        track.title = @"Updated title";
        Check([title.stringValue isEqualToString:track.title], @"Title metadata changes update live");
        for (NSNumber *size in @[@100, @125, @150, @175, @200]) {
            for (NSNumber *bold in @[@NO, @YES]) {
                preferences.textSizePercent = size.integerValue;
                preferences.usesBoldText = bold.boolValue;
                [window setContentSize:window.contentMinSize];
                [window.contentView layoutSubtreeIfNeeded];
                NSRect statusRect = [status convertRect:status.bounds toView:nil];
                NSRect titleRect = [title convertRect:title.bounds toView:nil];
                NSRect artistRect = [artist convertRect:artist.bounds toView:nil];
                NSRect waveRect = [wave convertRect:wave.bounds toView:nil];
                Check(!NSIntersectsRect(statusRect, titleRect) && !NSIntersectsRect(titleRect, artistRect) && !NSIntersectsRect(artistRect, waveRect),
                    @"Status and metadata stay above the waveform at every size/bold setting");
                Check(NSContainsRect(window.contentView.bounds, statusRect) && NSContainsRect(window.contentView.bounds, titleRect) &&
                    NSContainsRect(window.contentView.bounds, artistRect), @"Status and metadata remain inside the minimum window");
                Check(waveRect.size.height >= 48 * size.doubleValue / 100, @"Waveform retains a usable seek target");
                Check(fabs(NSMidX(statusRect) - NSMidX(waveRect)) < 1 && fabs(NSMidX(titleRect) - NSMidX(waveRect)) < 1 &&
                    fabs(NSMidX(artistRect) - NSMidX(waveRect)) < 1, @"Status and metadata are centered over the waveform");
                Check(NSMaxY(statusRect) <= NSMaxY(window.contentView.bounds) - 24, @"Status stays below native window controls");
            }
        }
        preferences.textSizePercent = 100;
        [window setContentSize:NSMakeSize(800, 240)];
        Check(fabs(window.contentView.frame.size.width - 800) < 1 && fabs(window.contentView.frame.size.height - 240) < 1, @"Ordinary resizing allows independent width and height");
        [window setContentSize:NSMakeSize(520, 144)];
        preferences.scalesInterfaceWithWindow = YES;
        Check(window.contentMinSize.width <= 520 && window.contentMinSize.height <= 144, @"A saved screen-wide strip does not lock the resize minimum");
        [window.contentView layoutSubtreeIfNeeded];
        NSSize before = [title convertRect:title.bounds toView:nil].size;
        NSSize content = window.contentView.frame.size;
        [window setContentSize:NSMakeSize(content.width * 1.5, content.height * 1.5)];
        [window.contentView layoutSubtreeIfNeeded];
        NSSize after = [title convertRect:title.bounds toView:nil].size;
        printf("Uniform resize: content %s -> %s, metadata %s -> %s\n", NSStringFromSize(content).UTF8String,
            NSStringFromSize(window.contentView.frame.size).UTF8String, NSStringFromSize(before).UTF8String, NSStringFromSize(after).UTF8String);
        // AppKit rounds label height to a whole point after applying the uniform transform.
        Check(fabs(after.width - before.width * 1.5) <= 1 && fabs(after.height - before.height * 1.5) <= 1, @"Window scaling enlarges metadata uniformly within one-point layout rounding");
        Check(!NSIntersectsRect([artist convertRect:artist.bounds toView:nil], [wave convertRect:wave.bounds toView:nil]), @"Window scaling keeps metadata clear of waveform");
        preferences.scalesInterfaceWithWindow = NO;
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"CurrentTrackPinning"];
        [controller changePinning:nil];
        Check((window.styleMask & NSWindowStyleMaskResizable) != 0, @"Pinned Current Track still supports height resizing");
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CurrentTrackPinning"];
        track.artist = @"";
        Check([artist.stringValue isEqualToString:@"Unknown artist"], @"Missing artist has an explicit fallback");
        track.title = @"";
        Check([title.stringValue isEqualToString:@"Untitled track"], @"Missing title has an explicit fallback");
        Player.sharedInstance.currentTrack = nil;
        Check(status.hidden && title.hidden && artist.hidden && wave.hidden, @"Old metadata clears after playback stops without a completed track");
        track.title = @"Completed fixture";
        track.artist = @"Synthetic QA";
        track.trackStatus = TrackStatusPlayed;
        Player.sharedInstance.currentTrack = (Track *)track;
        [controller player:Player.sharedInstance didFinishTrack:(Track *)track];
        Player.sharedInstance.currentTrack = nil;
        Check(!status.hidden && [status.stringValue isEqualToString:@"Played"],
            @"Current Track clearly identifies the last completed track as Played");
        Check([title.stringValue isEqualToString:@"Completed fixture"] && !wave.hidden,
            @"Completed track metadata and waveform remain available for review");
        track.trackStatus = TrackStatusQueued;
        Check(status.hidden && title.hidden && artist.hidden && wave.hidden,
            @"Requeueing the completed track clears the stale Played presentation");
        preferences.textSizePercent = 100;
        preferences.usesBoldText = NO;
        SetlistPlayBar *seek = [[SetlistPlayBar alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
        NSWindow *seekWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [seekWindow.contentView addSubview:seek];
        seek.playing = YES;
        seek.percentage = 0.5;
        [seek layoutSubtreeIfNeeded];
        Check([seek hitTest:NSMakePoint(160, 1)] == seek && [seek hitTest:NSMakePoint(160, 23)] == seek, @"Full 24-point seek height accepts input");
        NSView *progress = [seek valueForKey:@"progressBar"];
        NSView *playhead = [seek valueForKey:@"playhead"];
        Check(progress.frame.size.height == 8 && playhead.frame.size.width == 6 && playhead.frame.size.height == 18, @"Larger visible track and marker");
        SetlistMeterView *meters = [[SetlistMeterView alloc] initWithFrame:NSMakeRect(0, 0, 300, 18)];
        [seekWindow.contentView addSubview:meters];
        meters.metering = YES;
        [meters layoutSubtreeIfNeeded];
        for (NSNumber *peak in @[@0.0, @0.1, @0.4, @0.9, @1.2, @(NAN)]) {
            HugMeterData *data = [[HugMeterData alloc] initWithStruct:(HugMeterDataStruct){peak.floatValue, 0, NO}];
            [meters setLeftMeterData:data rightMeterData:data];
            NSView *left = [meters valueForKey:@"leftChannelBar"];
            NSBitmapImageRep *image = Render(left);
            Check(image != nil && [left.accessibilityValue doubleValue] <= 0 && [left.accessibilityValue doubleValue] >= -60, @"Meter renders silence, normal, hot, overload and malformed levels with bounded accessible values");
        }
        Check([[SetlistMeterView colorForPeakLevel:0.1 limiterActive:NO] isEqual:NSColor.systemGreenColor], @"Low output is green");
        Check([[SetlistMeterView colorForPeakLevel:0.4 limiterActive:NO] isEqual:NSColor.systemOrangeColor], @"Reduced headroom is amber");
        Check([[SetlistMeterView colorForPeakLevel:0.9 limiterActive:NO] isEqual:NSColor.systemRedColor], @"Near full scale is red");
        Check([[SetlistMeterView colorForPeakLevel:0.1 limiterActive:YES] isEqual:NSColor.systemRedColor], @"Limiter warning overrides a low instantaneous level");
        HugMeterData *full = [[HugMeterData alloc] initWithStruct:(HugMeterDataStruct){1.2, 0, YES}];
        [meters setLeftMeterData:full rightMeterData:full];
        NSView *left = [meters valueForKey:@"leftChannelBar"];
        NSBitmapImageRep *image = Render(left);
        NSUInteger green = 0, amber = 0, red = 0;
        for (NSInteger x = 0; x < image.pixelsWide; x++) {
            NSColor *c = [[image colorAtX:x y:image.pixelsHigh / 2] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            if (c.greenComponent > c.redComponent * 1.3) green++;
            if (c.redComponent > c.greenComponent * 1.1 && c.greenComponent > c.blueComponent * 1.5) amber++;
            if (c.redComponent > c.greenComponent * 1.5 && c.redComponent > c.blueComponent * 1.5) red++;
        }
        if (argc > 1) [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        Check(green > 10 && amber > 5 && red > 2, @"Rendered LEDs contain separate green, amber and red zones");
        meters.metering = NO;
        Check(meters.leftMeterData == nil && meters.rightMeterData == nil, @"Stopping clears output levels");
        TrackTableRowView *row = [[TrackTableRowView alloc] initWithFrame:NSMakeRect(0, 0, 300, 39)];
        row.playing = YES;
        Check(row.playing && !row.selected, @"Playing appearance is independent of selection");
        row.playing = NO;
        Check(!row.playing, @"Reused rows clear playing state");
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:domain];
        printf("PASS: %lu presentation assertions\n", (unsigned long)checks);
    }
}
