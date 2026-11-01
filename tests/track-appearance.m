#import <Cocoa/Cocoa.h>
#import "TrackTableCellView.h"
#import "TrackCueController.h"
#import "Track.h"
#import "TrackGenre.h"
#import "TrackTableRowView.h"
#import "TrackTableView.h"
#import "InterfaceAppearance.h"
#import "Preferences.h"
#import "HugAudioDevice.h"
#import "MaskView.h"
#import "TrackLabelView.h"
#import "NoDropImageView.h"
#import "TracksController.h"
#import "Player.h"
#import "AuditionPlayer.h"
#import "AuditionRoute.h"

// Exercise production cell refreshes without audio, library access or user defaults.
NSString * const EmbraceMappedEffect10BandEQ = @"Test EQ";
NSString * const TrackDidModifyDurationNotificationName = @"TestTrackDuration";
NSString * const AuditionPlayerDidChangeNotification = @"TestAuditionChange";
NSString * const HugAudioDevicesDidRefreshNotification = @"TestAudioDevicesDidRefresh";
NSString *EmbraceLockedTrackPasteboardType = @"test.locked";
NSString *EmbraceQueuedTrackPasteboardType = @"test.queued";
NSString *GetAppBuildString(void) { return @"1261"; }
NSUInteger GetCombinedBuildNumber(NSString *s) { return s.integerValue; }
AppDelegate *GetAppDelegate(void) { return nil; }
BOOL IsAppearanceDarkAqua(NSView *view) { return NO; }
void PerformWithAppearance(NSAppearance *appearance, void (^block)(void)) { block(); }
NSString *GetStringForTime(NSTimeInterval time) { return @"0:00"; }
NSString *GetOpenKeyNotationStringForTonality(NSInteger tonality) { return @""; }
NSString *GetTraditionalStringForTonality(NSInteger tonality) { return @""; }

static NSTimeInterval sPreviewStartTime;
static NSUUID *sPreviewRequestIdentifier;
static AuditionState sPreviewState;
static TrackStatus sTrackStatus;
static NSString *sTrackGenre;
static NSColor *sTrackColorOverride;

@implementation MaskView
@end
@implementation TrackLabelView
@end
@implementation NoDropImageView
@end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation Player
+ (instancetype) sharedInstance { return nil; }
@end
@implementation HugAudioDevice
+ (instancetype) placeholderDevice { return [self new]; }
+ (instancetype) bestDefaultDevice { return [self new]; }
+ (instancetype) archivedDeviceWithDeviceUID:(NSString *)uid name:(NSString *)name { return [self new]; }
- (NSString *) deviceUID { return @"test-device"; }
- (NSString *) name { return @"Test device"; }
@end
@implementation AuditionPlayer
+ (instancetype) sharedInstance { static AuditionPlayer *player; static dispatch_once_t once; dispatch_once(&once, ^{ player = [self new]; }); return player; }
- (NSUUID *) previewURL:(NSURL *)url title:(NSString *)title artist:(NSString *)artist { return [self previewURL:url title:title artist:artist startTime:0 endTime:0]; }
- (NSUUID *) previewURL:(NSURL *)url title:(NSString *)title artist:(NSString *)artist
              startTime:(NSTimeInterval)startTime endTime:(NSTimeInterval)endTime
{
    sPreviewStartTime = startTime;
    sPreviewRequestIdentifier = NSUUID.UUID;
    sPreviewState = AuditionStatePlaying;
    return sPreviewRequestIdentifier;
}
- (void) stopPreviewWithIdentifier:(NSUUID *)identifier { if ([identifier isEqual:sPreviewRequestIdentifier]) sPreviewState = AuditionStateStopped; }
- (void) pause { sPreviewState = AuditionStatePaused; }
- (void) resume { sPreviewState = AuditionStatePlaying; }
- (void) stop { sPreviewState = AuditionStateStopped; }
- (void) seekToTime:(NSTimeInterval)time { }
- (NSUUID *) requestIdentifier { return sPreviewRequestIdentifier; }
- (AuditionState) state { return sPreviewState; }
- (NSString *) message { return sPreviewState == AuditionStatePlaying ? @"Headphone preview playing" : @"Preview stopped"; }
@end
NSArray<NSDictionary<NSString *, id> *> *AuditionOutputDevices(void) { return @[]; }
@implementation Track
- (void) startPriorityAnalysis { }
- (NSURL *) internalURL { return [NSURL fileURLWithPath:@"/tmp/ez-embrace-cue-preview.wav"]; }
- (NSString *) title { return @"Cue preview fixture"; }
- (NSString *) artist { return @"Synthetic QA"; }
- (NSTimeInterval) startTime { return 0; }
- (NSTimeInterval) playDuration { return 120; }
- (NSTimeInterval) cueStartTime { return 0; }
- (TrackStatus) trackStatus { return sTrackStatus; }
- (void) setTrackStatus:(TrackStatus)trackStatus { sTrackStatus = trackStatus; }
- (NSString *) genre { return sTrackGenre; }
- (TrackGenreHighlightOverride) genreHighlightOverride { return TrackGenreHighlightOverrideAutomatic; }
- (NSColor *) setListColorOverride { return sTrackColorOverride; }
- (void) setSetListColorOverride:(NSColor *)color { sTrackColorOverride = [color copy]; }
@end
#pragma clang diagnostic pop

@interface FontFixtureCell : TrackTableCellView
@property Track *testTrack;
@end
@implementation FontFixtureCell
- (void) _commonTrackTableCellViewInit { }
- (void) _adjustConstraintsForLineLayout { }
- (Track *) track { return self.testTrack; }
@end

@interface TrackTableView (AppearanceTests)
- (void) _dispatchHeightUpdate;
- (void) _updateDrag;
@end

@interface HeightProbeTable : TrackTableView
@property NSUInteger heightInvalidations;
@end
@implementation HeightProbeTable
- (void) noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)indexes { self.heightInvalidations++; }
@end

@interface DragProbeDelegate : NSObject <TrackTableViewDelegate>
@property NSUInteger updateCount;
@property BOOL lastIsModifying;
@end
@implementation DragProbeDelegate
- (void)trackTableView:(TrackTableView *)tableView isModifyingViaDrag:(BOOL)isModifyingViaDrag
{
    self.updateCount++;
    self.lastIsModifying = isModifyingViaDrag;
}
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

static CGFloat TextLuminance(NSColor *color, NSAppearance *appearance, CGFloat background)
{
    __block CGFloat result;
    [appearance performAsCurrentDrawingAppearance:^{
        NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        CGFloat luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent;
        result = luminance * rgb.alphaComponent + background * (1 - rgb.alphaComponent);
    }];
    return result;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *domain = NSProcessInfo.processInfo.processName;
        Check([domain isEqual:@"ez-embrace-track-appearance-tests"], @"Isolated preferences domain");
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults removePersistentDomainForName:domain];
        Preferences *preferences = Preferences.sharedInstance;
        preferences.usesBoldText = YES;
        preferences.shortensPlayedTracks = NO;
        NSArray<NSDictionary *> *genreCases = @[
            @{ @"title": @"Electronic Pulse",       @"genre": @"Electronic",           @"green": @YES },
            @{ @"title": @"Jazz Interlude",        @"genre": @"Jazz",                 @"green": @YES },
            @{ @"title": @"Rock Break",            @"genre": @"Rock",                 @"green": @YES },
            @{ @"title": @"Ambient Set",           @"genre": @"Ambient / Downtempo", @"green": @YES },
            @{ @"title": @"Cantata in D",          @"genre": @"Classical Cantata",    @"green": @YES },
            @{ @"title": @"Cantaloupe",            @"genre": @"Cantaloupe",           @"green": @YES },
            @{ @"title": @"Inst Only",              @"genre": @"Inst",                  @"green": @YES },
            @{ @"title": @"Instrumental Only",      @"genre": @"Instrumental",          @"green": @YES },
            @{ @"title": @"Alt Only",               @"genre": @"Alt",                   @"green": @YES },
            @{ @"title": @"Alternative Only",       @"genre": @"Alternative",           @"green": @YES },
            @{ @"title": @"Alternative Rock",       @"genre": @"Alternative Rock",      @"green": @YES },
            @{ @"title": @"Instrumental Jazz",      @"genre": @"Instrumental Jazz",     @"green": @YES },
            @{ @"title": @"Blank Metadata",        @"genre": @"",                     @"green": @YES },
            @{ @"title": @"Missing Metadata",      @"genre": NSNull.null,              @"green": @YES },
            @{ @"title": @"Tango Clasico",         @"genre": @"Tango",                @"green": @NO },
            @{ @"title": @"Mixed Case Tango",      @"genre": @"tAnGo",                @"green": @NO },
            @{ @"title": @"Tango Cant",            @"genre": @"Tango-Cant",           @"green": @NO },
            @{ @"title": @"Cant Tango",            @"genre": @"Cant Tango",           @"green": @NO },
            @{ @"title": @"Cant Only",             @"genre": @"CANT",                 @"green": @NO },
            @{ @"title": @"Cant After Slash",      @"genre": @"Jazz / cant",          @"green": @NO },
            @{ @"title": @"Vals Clasico",          @"genre": @"VALS",                 @"green": @NO },
            @{ @"title": @"Milonga Instrumental", @"genre": @"miLONGa instrumental", @"green": @NO },
            @{ @"title": @"Reordered Pair",        @"genre": @"Vals, Tango",          @"green": @NO },
            @{ @"title": @"Cant Milonga",          @"genre": @"cant - milonga",       @"green": @NO },
            @{ @"title": @"Pipe Tango",            @"genre": @"Ambient | Tango",      @"green": @NO },
            @{ @"title": @"Dotted Milonga",        @"genre": @"Neo.Milonga",          @"green": @NO },
            @{ @"title": @"Parenthesized Vals",    @"genre": @"Traditional (Vals)",   @"green": @NO },
            @{ @"title": @"Underscore Cant",       @"genre": @"Milonga_Cant",         @"green": @NO },
            @{ @"title": @"Tabbed Tango",          @"genre": @"Tango\tCant",          @"green": @NO },
            @{ @"title": @"Newline Vals",          @"genre": @"Tango\nVals",          @"green": @NO },
            @{ @"title": @"Tango Inst Compact",    @"genre": @"TangoInst",            @"green": @NO },
            @{ @"title": @"Reported Tango Inst",   @"genre": @"Tango-Inst",           @"green": @NO },
            @{ @"title": @"Reported Lower Inst",   @"genre": @"Tango-inst",           @"green": @NO },
            @{ @"title": @"Reported Spaced Inst",  @"genre": @"Tango- inst",          @"green": @NO },
            @{ @"title": @"Reported Spaced Cant",  @"genre": @"Tango- Cant",          @"green": @NO },
            @{ @"title": @"Lower Tango Inst",      @"genre": @"tango-inst",           @"green": @NO },
            @{ @"title": @"Mixed Tango Inst",      @"genre": @"tAnGo-InSt",           @"green": @NO },
            @{ @"title": @"Spaced Tango Inst",     @"genre": @"Tango - Inst",         @"green": @NO },
            @{ @"title": @"Wide Tango Inst",       @"genre": @"Tango   -    Inst",    @"green": @NO },
            @{ @"title": @"Inst Tango Compact",    @"genre": @"InstTango",            @"green": @NO },
            @{ @"title": @"Tango Instrumental",    @"genre": @"Tango Instrumental",   @"green": @NO },
            @{ @"title": @"Instrumental Tango",    @"genre": @"Instrumental-Tango",   @"green": @NO },
            @{ @"title": @"Milonga Alt Compact",   @"genre": @"MilongaAlt",            @"green": @NO },
            @{ @"title": @"Alt Milonga Compact",   @"genre": @"AltMilonga",            @"green": @NO },
            @{ @"title": @"Milonga Alternative",  @"genre": @"Milonga Alternative",   @"green": @NO },
            @{ @"title": @"Alternative Milonga",  @"genre": @"Alternative/Milonga",   @"green": @NO },
            @{ @"title": @"Vals Inst Alt",          @"genre": @"ValsInstAlt",           @"green": @NO },
            @{ @"title": @"Alternative Vals",      @"genre": @"AlternativeVals",       @"green": @NO },
            @{ @"title": @"Vals Modifier Words",   @"genre": @"vals instrumental alt", @"green": @NO },
            @{ @"title": @"Neo Tango Compact",     @"genre": @"NeoTango",              @"green": @NO },
        ];
        for (NSDictionary *genreCase in genreCases) {
            id storedGenre = genreCase[@"genre"];
            NSString *genre = [storedGenre isKindOfClass:NSString.class] ? storedGenre : nil;
            BOOL expectedGreen = [genreCase[@"green"] boolValue];
            BOOL actualGreen = TrackGenreUsesUpcomingHighlight(genre);
            fprintf(stdout, "CLASSIFIER %-6s | %-22s | %s\n",
                actualGreen ? "GREEN" : "NORMAL", [genreCase[@"title"] UTF8String],
                genre.length ? genre.UTF8String : "(missing or empty)");
            Check(actualGreen == expectedGreen,
                [NSString stringWithFormat:@"%@ with genre %@ should be %@",
                    genreCase[@"title"], genre ?: @"(missing)", expectedGreen ? @"green" : @"normal"]);
        }
        NSArray<NSString *> *protectedTokens = @[ @"tango", @"cant", @"vals", @"milonga" ];
        NSArray<NSString *> *separators = @[ @" ", @"-", @"/", @",", @".", @"_", @"|", @"\t", @"\n" ];
        for (NSString *token in protectedTokens) {
            NSArray<NSString *> *caseVariants = @[
                token.lowercaseString, token.uppercaseString, token.capitalizedString
            ];
            for (NSString *variant in caseVariants) {
                for (NSString *separator in separators) {
                    for (NSString *genre in @[
                        [NSString stringWithFormat:@"Jazz%@%@", separator, variant],
                        [NSString stringWithFormat:@"%@%@Electronic", variant, separator]
                    ]) {
                        Check(!TrackGenreUsesUpcomingHighlight(genre),
                            [NSString stringWithFormat:@"Protected token permutation should stay normal: %@", genre]);
                    }
                }
            }
        }
        NSArray<NSString *> *danceRoots = @[ @"tango", @"milonga", @"vals" ];
        NSArray<NSString *> *modifiers = @[ @"inst", @"instrumental", @"alt", @"alternative" ];
        NSArray<NSString *> *combinationSeparators = @[ @"", @" ", @"-", @"/", @",", @".", @"_", @"|", @"\t", @"\n" ];
        for (NSString *root in danceRoots) {
            for (NSString *modifier in modifiers) {
                for (NSString *separator in combinationSeparators) {
                    for (NSString *genre in @[
                        [NSString stringWithFormat:@"%@%@%@", root, separator, modifier],
                        [NSString stringWithFormat:@"%@%@%@", modifier, separator, root],
                        [NSString stringWithFormat:@"%@%@%@", root.uppercaseString, separator, modifier.capitalizedString],
                        [NSString stringWithFormat:@"%@%@%@", modifier.uppercaseString, separator, root.capitalizedString]
                    ]) {
                        Check(!TrackGenreUsesUpcomingHighlight(genre),
                            [NSString stringWithFormat:@"Dance genre plus modifier should stay normal: %@", genre]);
                    }
                }
            }
        }
        for (NSString *modifier in modifiers) {
            Check(TrackGenreUsesUpcomingHighlight(modifier),
                [NSString stringWithFormat:@"Modifier without a dance genre should stay green: %@", modifier]);
        }
        NSArray<NSString *> *hyphenSpaces = @[ @"", @" ", @"  ", @"     " ];
        for (NSString *leftSpaces in hyphenSpaces) {
            for (NSString *rightSpaces in hyphenSpaces) {
                for (NSString *root in @[ @"tango", @"Tango", @"TANGO", @"TaNgO" ]) {
                    for (NSString *followingWord in @[ @"inst", @"Cant", @"ROCK", @"anything", @"Another Word" ]) {
                        NSString *genre = [NSString stringWithFormat:@"%@%@-%@%@",
                            root, leftSpaces, rightSpaces, followingWord];
                        Check(!TrackGenreUsesUpcomingHighlight(genre),
                            [NSString stringWithFormat:@"Tango hyphen permutation should stay normal: %@", genre]);
                    }
                }
            }
        }
        Check(TrackGenreUsesUpcomingHighlightWithOverride(@"Tango-Inst", TrackGenreHighlightOverrideGreen),
            @"Manual green override wins over Tango classification");
        Check(!TrackGenreUsesUpcomingHighlightWithOverride(@"Electronic", TrackGenreHighlightOverrideNormal),
            @"Manual normal override wins over non-Tango classification");
        Check(!TrackGenreUsesUpcomingHighlightWithOverride(@"Tango-Inst", TrackGenreHighlightOverrideAutomatic),
            @"Automatic override mode preserves Tango classification");
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 300)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        FontFixtureCell *cell = [[FontFixtureCell alloc] initWithFrame:NSMakeRect(0, 0, 500, 39)];
        NSMutableArray<NSTextField *> *fields = [NSMutableArray array];
        for (NSString *key in @[@"titleField", @"durationField", @"lineTwoLeftField", @"lineTwoRightField", @"lineThreeLeftField", @"lineThreeRightField"]) {
            NSTextField *field = [NSTextField labelWithString:@"Hover and selection regression"];
            field.font = [NSFont systemFontOfSize:13];
            [cell addSubview:field];
            [cell setValue:field forKey:key];
            [fields addObject:field];
        }
        [window.contentView addSubview:cell];
        [InterfaceAppearance installInWindow:window];
        preferences.themeType = ThemeTypeBlush;
        NSTextField *blushField = [NSTextField labelWithString:@"Always black"];
        [InterfaceAppearance setTextColor:NSColor.secondaryLabelColor forField:blushField];
        Check([blushField.textColor isEqual:NSColor.blackColor], @"Blush wash forces black text");
        Check([TrackTableViewGetPlayingTextColor() isEqual:NSColor.blackColor], @"Blush playing text stays black");
        Check(![TrackTableViewGetRowHighlightColor(YES) isEqual:NSColor.selectedContentBackgroundColor],
            @"Blush selection uses its pink highlight");
        Track *appearanceTrack = [Track new];
        appearanceTrack.trackStatus = TrackStatusPlayed;
        cell.testTrack = appearanceTrack;
        preferences.textContrastPercent = 100;
        [cell updateColors];
        CGFloat playedLuminance = TextLuminance(fields.firstObject.textColor,
            [NSAppearance appearanceNamed:NSAppearanceNameAqua], 1);
        Check(playedLuminance > 0.35 && playedLuminance < 0.70,
            @"Played track stays visibly gray in Blush at maximum contrast");
        Check(([NSFontManager.sharedFontManager traitsOfFont:fields.firstObject.font] & NSBoldFontMask) != 0,
            @"Played track keeps its gray state while bold text remains enabled");
        TrackTableRowView *genreRow = [[TrackTableRowView alloc] initWithFrame:NSMakeRect(0, 0, 500, 39)];
        [genreRow addSubview:cell];
        sTrackStatus = TrackStatusQueued;
        sTrackGenre = @"Electronic";
        [cell updateColors];
        Check(genreRow.highlightsUpcomingOtherGenre && genreRow.drawsUpcomingOtherGenreHighlight,
            @"Queued tracks outside the three dance genres use the alternate highlight");
        genreRow.selected = YES;
        Check(!genreRow.drawsUpcomingOtherGenreHighlight,
            @"Selection overrides the alternate genre highlight");
        genreRow.selected = NO;
        sTrackStatus = TrackStatusPlayed;
        [cell updateColors];
        Check(!genreRow.highlightsUpcomingOtherGenre,
            @"Played tracks keep the played appearance instead of the alternate highlight");
        sTrackStatus = TrackStatusPlaying;
        [cell updateColors];
        Check(!genreRow.highlightsUpcomingOtherGenre,
            @"Playing tracks keep the playing appearance instead of the alternate highlight");
        sTrackStatus = TrackStatusQueued;
        sTrackGenre = @"Jazz / cAnT";
        [cell updateColors];
        Check(!genreRow.highlightsUpcomingOtherGenre,
            @"Case-insensitive Cant metadata keeps the ordinary upcoming appearance");
        sTrackGenre = @"Electronic";
        sTrackColorOverride = [NSColor colorWithSRGBRed:0.35 green:0.65 blue:0.90 alpha:1];
        [cell updateColors];
        Check(genreRow.drawsTrackColorOverride && !genreRow.drawsUpcomingOtherGenreHighlight,
            @"per-track cosmetic color overrides automatic mint without changing classification");
        genreRow.selected = YES;
        Check(!genreRow.drawsTrackColorOverride,
            @"selection remains visible over a per-track cosmetic color");
        genreRow.selected = NO;
        sTrackColorOverride = nil;
        [window.contentView addSubview:cell];
        cell.testTrack = nil;
        preferences.textContrastPercent = 0;
        preferences.themeType = ThemeTypeSystem;
        for (NSNumber *size in @[@100, @200]) {
            preferences.textSizePercent = size.integerValue;
            for (NSNumber *bold in @[@YES, @NO]) {
                preferences.usesBoldText = bold.boolValue;
                for (NSUInteger cycle = 0; cycle < 8; cycle++) {
                    NSFont *before = fields.firstObject.font;
                    cell.expandedPlayedTrack = !cell.isExpandedPlayedTrack;
                    NSFont *after = fields.firstObject.font;
                    fprintf(stdout, "Refresh %lu size=%ld bold=%d: %s -> %s\n", (unsigned long)cycle,
                        (long)size.integerValue, bold.boolValue, before.fontName.UTF8String, after.fontName.UTF8String);
                    Check((([NSFontManager.sharedFontManager traitsOfFont:after] & NSBoldFontMask) != 0) == bold.boolValue,
                        @"Hover refresh retains bold immediately, before the next window update");
                    Check(after.pointSize == 13, @"Hover refresh retains the logical font size");
                    [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidUpdateNotification object:window];
                    Check([fields.firstObject.font isEqual:after], @"Window update does not replace the hover font again");
                }
            }
        }
        preferences.usesBoldText = YES;
        NSTextField *newField = [NSTextField labelWithString:@"Created while bold is enabled"];
        [InterfaceAppearance setFont:[NSFont systemFontOfSize:13] forControl:newField];
        [[InterfaceAppearance contentViewForWindow:window] addSubview:newField];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidUpdateNotification object:window];
        preferences.usesBoldText = NO;
        Check(!([NSFontManager.sharedFontManager traitsOfFont:newField.font] & NSBoldFontMask),
            @"A newly created cell retains its regular baseline when bold is disabled");

        Track *cueTrack = [Track new];
        TrackCueController *cueController = [TrackCueController new];
        [cueController setValue:cueTrack forKey:@"track"];
        [cueController setValue:@1 forKey:@"scale"];
        [cueController setValue:@420 forKey:@"contentWidth"];
        [cueController view];
        NSTextField *cueTime = [cueController valueForKey:@"timeField"];
        NSButton *cuePreview = [cueController valueForKey:@"previewButton"];
        cueTime.stringValue = @"1:15";
        [cuePreview performClick:nil];
        Check(fabs(sPreviewStartTime - 75) < .001, @"Flag preview sends the unsaved draft position to Audition Output");
        Check(cueTrack.cueStartTime == 0, @"Flag preview does not save or consume the track cue");
        Check([cuePreview.accessibilityLabel isEqual:@"Preview draft start in headphones"], @"Flag preview has an explicit accessibility contract");
        Check([[cueController valueForKey:@"previewStatusField"] stringValue].length > 0, @"Flag preview reports its headphone state in the popover");

        HeightProbeTable *table = [[HeightProbeTable alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        [table setValue:[NSMutableIndexSet indexSetWithIndex:0] forKey:@"rowsNeedingUpdatedHeight"];
        [table _dispatchHeightUpdate];
        Check(table.heightInvalidations == 0, @"Hover does not retile rows when compact played tracks is off");

        TrackTableView *dragTable = [[TrackTableView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        DragProbeDelegate *dragDelegate = [DragProbeDelegate new];
        dragTable.delegate = dragDelegate;
        [dragTable setValue:@YES forKey:@"inLocalDrag"];
        [dragTable _updateDrag];
        Check(dragDelegate.lastIsModifying, @"Local drag enables the playback-transition guard");
        [dragTable finishDragModification];
        Check(!dragDelegate.lastIsModifying, @"Finishing a local drag releases the playback-transition guard");
        NSUInteger finishedUpdateCount = dragDelegate.updateCount;
        [dragTable finishDragModification];
        Check(dragDelegate.updateCount == finishedUpdateCount + 1 && !dragDelegate.lastIsModifying,
              @"Finishing drag modification is safely idempotent");

        NSTextField *contrastField = [NSTextField labelWithString:@"Secondary metadata"];
        NSColor *base = NSColor.secondaryLabelColor;
        [InterfaceAppearance setTextColor:base forField:contrastField];
        [[InterfaceAppearance contentViewForWindow:window] addSubview:contrastField];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidUpdateNotification object:window];
        NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        NSAppearance *dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        CGFloat lightBefore = TextLuminance(contrastField.textColor, light, 1);
        CGFloat darkBefore = TextLuminance(contrastField.textColor, dark, 0);
        NSRect windowBefore = window.frame;
        __block NSUInteger generalChanges = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:PreferencesDidChangeNotification
            object:preferences queue:nil usingBlock:^(NSNotification *note) { generalChanges++; }];
        for (NSNumber *contrast in @[@25, @50, @100]) {
            preferences.textContrastPercent = contrast.integerValue;
            CGFloat lightAfter = TextLuminance(contrastField.textColor, light, 1);
            CGFloat darkAfter = TextLuminance(contrastField.textColor, dark, 0);
            Check(lightAfter < lightBefore, @"Contrast progressively darkens Light-mode metadata");
            Check(darkAfter > darkBefore, @"Contrast progressively brightens Dark-mode metadata");
            Check(NSEqualRects(windowBefore, window.frame), @"Contrast changes leave window geometry unchanged");
            lightBefore = lightAfter;
            darkBefore = darkAfter;
        }
        Check(generalChanges == 0, @"Contrast uses its own notification instead of reconfiguring playback");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        for (NSUInteger cycle = 0; cycle < 8; cycle++) {
            [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidUpdateNotification object:window];
            Check(fabs(TextLuminance(contrastField.textColor, light, 1) - lightBefore) < 0.00001,
                @"Repeated redraws do not accumulate contrast");
        }
        NSColor *changedBase = [NSColor colorWithWhite:0.7 alpha:1];
        [InterfaceAppearance setTextColor:changedBase forField:contrastField];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidUpdateNotification object:window];
        preferences.textContrastPercent = 0;
        Check([contrastField.textColor isEqual:changedBase], @"Zero restores the latest semantic text color after cell reuse");
        preferences.textContrastPercent = -8;
        Check(preferences.textContrastPercent == 0, @"Negative contrast clamps to zero");
        preferences.textContrastPercent = 101;
        Check(preferences.textContrastPercent == 100, @"Contrast clamps to 100");
        Check([defaults integerForKey:@"textContrastPercent"] == 100, @"Contrast persists as an integer preference");
        Preferences *reloaded = [Preferences new];
        Check(reloaded.textContrastPercent == 100, @"Saved contrast reloads correctly");
        NSTableRowView *selectedRow = [[NSTableRowView alloc] initWithFrame:NSMakeRect(0, 0, 300, 39)];
        selectedRow.selected = YES;
        selectedRow.emphasized = YES;
        NSTextField *selectedField = [NSTextField labelWithString:@"Selected track"];
        [selectedRow addSubview:selectedField];
        [[InterfaceAppearance contentViewForWindow:window] addSubview:selectedRow];
        [InterfaceAppearance setTextColor:NSColor.whiteColor forField:selectedField];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidUpdateNotification object:window];
        Check([selectedField.textColor isEqual:NSColor.whiteColor], @"Emphasized selection text retains its native color");
        TrackTableRowView *dividerRow = [[TrackTableRowView alloc] initWithFrame:NSMakeRect(0, 0, 300, 39)];
        [window.contentView addSubview:dividerRow];
        dividerRow.needsDisplay = NO;
        dividerRow.endsLastPlayedTrack = YES;
        Check(dividerRow.endsLastPlayedTrack, @"Last-played row retains divider state");
        Check(dividerRow.needsDisplay, @"Changing divider state invalidates row rendering");
        dividerRow.selected = YES;
        [dividerRow displayIfNeeded];
        Check(dividerRow.endsLastPlayedTrack, @"Selected last-played row retains its divider");
        [defaults removePersistentDomainForName:domain];
        printf("PASS: %lu track appearance assertions\n", (unsigned long)checks);
    }
}
