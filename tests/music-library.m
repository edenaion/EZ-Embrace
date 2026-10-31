#import <Cocoa/Cocoa.h>
#import "MusicLibrary.h"
#import "MusicLibraryBackupStore.h"
#import "MusicLibraryController.h"
#import "MusicAppManager.h"
#import "InterfaceAppearance.h"
#import "Preferences.h"
#import "HugAudioDevice.h"
#import "AuditionPlayer.h"
#ifndef EZ_EMBRACE_TEST_ROOT
#define EZ_EMBRACE_TEST_ROOT "."
#endif

NSString * const EmbraceMappedEffect10BandEQ = @"Test EQ";
NSString * const PlayerWillConfigureOutputNotification = @"PlayerWillConfigureOutput";
NSString * const HugAudioDevicesDidRefreshNotification = @"HugAudioDevicesDidRefresh";
NSString *GetAppBuildString(void) { return @"1261"; }
NSUInteger GetCombinedBuildNumber(NSString *s) { return s.integerValue; }
AppDelegate *GetAppDelegate(void) { return nil; }
void EmbraceLog(NSString *category, NSString *format, ...) { }
NSString *GetStringForTime(NSTimeInterval time) { return [NSString stringWithFormat:@"%ld:%02ld", (long)(time / 60), (long)time % 60]; }
@interface FixtureMusicAppManager : MusicAppManager
@end
static NSUInteger sAutomaticRefreshes;
@implementation FixtureMusicAppManager
- (void) _checkLibrary:(NSTimer *)timer { }
- (void) refreshBrowser { sAutomaticRefreshes++; }
@end
@implementation HugAudioDevice
+ (instancetype) placeholderDevice { return [self new]; }
+ (instancetype) bestDefaultDevice { return [self new]; }
+ (instancetype) archivedDeviceWithDeviceUID:(NSString *)uid name:(NSString *)name { return [self new]; }
- (NSString *) name { return @"Test device"; }
- (NSString *) deviceUID { return @"TestDevice"; }
- (AudioObjectID) objectID { return 0; }
@end

static NSUInteger sAssertions;
static void Check(BOOL condition, NSString *message)
{
    sAssertions++;
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static NSArray *FindViews(NSView *view, Class cls)
{
    NSMutableArray *result = [NSMutableArray array];
    if ([view isKindOfClass:cls]) [result addObject:view];
    for (NSView *child in view.subviews) [result addObjectsFromArray:FindViews(child, cls)];
    return result;
}

static MusicLibrarySnapshot *Fixture(NSString *firstPath, NSString *secondPath)
{
    return [[MusicLibrarySnapshot alloc] initWithDictionary:@{
        @"tracks":@[
            @{@"id":@"1", @"title":@"Zulu drums", @"artist":@"Café Session", @"album":@"Synthetic fixtures", @"duration":@90, @"bpm":@120, @"year":@2026, @"availability":@"Local file", @"location":[NSURL fileURLWithPath:firstPath].absoluteString},
            @{@"id":@"2", @"title":@"Alpha groove", @"artist":@"Test Artist", @"album":@"Synthetic fixtures", @"duration":@120, @"bpm":@80, @"year":@2025, @"availability":@"Local file", @"location":[NSURL fileURLWithPath:secondPath].absoluteString},
            @{@"id":@"3", @"title":@"Cloud song", @"availability":@"Cloud only", @"location":@"https://example.invalid/track"},
            @{@"id":@"4", @"title":@"Protected song", @"availability":@"Protected audio", @"drmProtected":@YES, @"location":[NSURL fileURLWithPath:firstPath].absoluteString},
            @{@"id":@"5", @"title":@"Missing song", @"availability":@"File unavailable", @"location":@"file:///nonexistent/ez-embrace-missing.wav"}
        ],
        @"playlists":@[
            @{@"id":@"set", @"name":@"DJ practice", @"parentID":@"folder", @"trackIDs":@[@"2", @"1", @"2", @"3", @"4", @"5", @"unknown"]},
            @{@"id":@"folder", @"name":@"Sets", @"trackIDs":@[]},
            @{@"id":@"empty", @"name":@"Empty playlist", @"trackIDs":@[]}
        ]
    }];
}

static void TestSnapshot(MusicLibrarySnapshot *snapshot)
{
    Check(snapshot.isComplete, @"Complete library root accepted");
    Check(snapshot.tracks.count == 5, @"All audio rows retained");
    Check(snapshot.playlists.count == 4, @"All music and playlists");
    NSArray *tracks = [snapshot tracksForPlaylist:@"set" search:@"" sortDescriptors:@[]];
    Check(tracks.count == 6, @"Playlist duplicates retained and unknown IDs skipped");
    Check([tracks[0][@"id"] isEqual:@"2"] && [tracks[2][@"id"] isEqual:@"2"], @"Original playlist order");
    Check([[snapshot tracksForPlaylist:@"set" search:@"cafe drums" sortDescriptors:@[]] count] == 1, @"Case and accent insensitive multiword search");
    Check([[snapshot tracksForPlaylist:@"all" search:@"2026" sortDescriptors:@[]] count] == 1, @"Numeric metadata search");
    Check([[snapshot tracksForPlaylist:@"empty" search:@"" sortDescriptors:@[]] count] == 0, @"Empty playlist");
    Check([[snapshot tracksForPlaylist:@"unknown" search:@"" sortDescriptors:@[]] count] == 0, @"Unknown playlist");
    NSArray *sorted = [snapshot tracksForPlaylist:@"all" search:@"Synthetic fixtures" sortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"bpm" ascending:YES]]];
    Check([sorted[0][@"id"] isEqual:@"2"], @"Numeric sorting uses numbers");
    sorted = [snapshot tracksForPlaylist:@"all" search:@"Synthetic fixtures" sortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:NO selector:@selector(localizedStandardCompare:)]]];
    Check([sorted[0][@"id"] isEqual:@"1"], @"Text sorting descending");
    Check([snapshot tracksForPlaylist:@"all" search:@"" sortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"invalid.key" ascending:YES]]].count == 5, @"Unknown sort key ignored");
    Check([[MusicLibrarySnapshot displayValueForTrack:snapshot.tracks[0] column:@"duration"] isEqual:@"1:30"], @"Duration display");
    Check([MusicLibrarySnapshot importURLsForTracks:tracks].count == 3, @"Only local readable unprotected files dragged, duplicates retained");
    for (NSUInteger index = 2; index < 5; index++) Check(![MusicLibrarySnapshot importURLForTrack:snapshot.tracks[index]], @"Unavailable row blocked");
    NSUInteger setIndex = [snapshot.playlists indexOfObjectPassingTest:^BOOL(NSDictionary *playlist, NSUInteger index, BOOL *stop) { return [playlist[@"id"] isEqual:@"set"]; }];
    Check(setIndex != NSNotFound && [snapshot.playlists[setIndex][@"path"] isEqual:@"Sets / DJ practice"], @"Playlist folder path");
    Check([snapshot.playlists[1][@"id"] isEqual:@"set"], @"Source playlist order retained");
    Check(!snapshot.backupPayload[@"tracks"][0][@"searchText"], @"Search index excluded from backup payload");
    Check([snapshot.backupPayload[@"playlists"][0][@"trackIDs"] count] == 6, @"Backup preserves ordered duplicate playlist membership");
    MusicLibrarySnapshot *malformed = [[MusicLibrarySnapshot alloc] initWithDictionary:@{@"tracks":@[@1, @{}, @{@"id":@"x", @"duration":@(NAN), @"title":@1}, @{@"id":@"x"}], @"playlists":@[@1, @{}, @{@"id":@"cycle", @"parentID":@"cycle", @"trackIDs":@[@1]}]}];
    Check(malformed.tracks.count == 1 && [malformed.tracks[0][@"title"] isEqual:@"Untitled track"], @"Malformed data and duplicate ID handled");
    Check([malformed.tracks[0][@"duration"] doubleValue] == 0, @"Nonfinite duration rejected");
    Check(malformed.playlists.count == 2, @"Cyclic parent bounded");
    Check(malformed.isComplete, @"Malformed rows do not invalidate a complete root");
    Check(![[MusicLibrarySnapshot alloc] initWithDictionary:@{}].isComplete, @"Incomplete root identified");
    Check([MusicLibrarySnapshot columns].count == 33, @"Metadata column contract");
}

static void TestBackups(MusicLibrarySnapshot *snapshot)
{
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    MusicLibraryBackupStore *store = [[MusicLibraryBackupStore alloc] initWithDirectoryURL:directory];
    NSDate *start = [NSDate dateWithTimeIntervalSince1970:1767268800];
    BOOL wrote = NO;
    NSError *error = nil;
    NSURL *daily = [store saveSnapshot:snapshot atDate:start force:NO didWrite:&wrote error:&error];
    Check(daily && wrote && !error, @"Daily snapshot written atomically");
    NSDictionary *verified = [MusicLibraryBackupStore verifiedEnvelopeAtURL:daily error:&error];
    Check(verified && [verified[@"trackCount"] unsignedIntegerValue] == snapshot.tracks.count, @"Snapshot checksum and track count verify");
    NSArray *membership = verified[@"decodedPayload"][@"playlists"][0][@"trackIDs"];
    Check(membership.count == 6 && [membership[0] isEqual:@"2"] && [membership[2] isEqual:@"2"], @"Verified snapshot restores playlist order and duplicates");
    MusicLibrarySnapshot *restored = [[MusicLibrarySnapshot alloc] initWithDictionary:verified[@"decodedPayload"]];
    Check(restored.isComplete && [restored.backupPayload[@"tracks"] isEqual:snapshot.backupPayload[@"tracks"]],
        @"Verified payload restores into a standalone mirror");
    Check([restored.playlists[1][@"trackIDs"] isEqual:snapshot.playlists[1][@"trackIDs"]], @"Standalone restore preserves playlist membership");
    NSURL *sameDay = [store saveSnapshot:snapshot atDate:[start dateByAddingTimeInterval:60] force:NO didWrite:&wrote error:&error];
    Check([sameDay isEqual:daily] && !wrote, @"Automatic backup runs once per calendar day");
    NSURL *manual = [store saveSnapshot:snapshot atDate:[start dateByAddingTimeInterval:120] force:YES didWrite:&wrote error:&error];
    Check(manual && wrote && ![manual isEqual:daily], @"Backup now creates a separate retained snapshot");

    NSURL *corrupt = [directory URLByAppendingPathComponent:@"corrupt.ezmusiclibrary"];
    [@"not a snapshot" writeToURL:corrupt atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Check(![MusicLibraryBackupStore verifiedEnvelopeAtURL:corrupt error:&error] && error, @"Corrupt snapshot rejected");
    MusicLibrarySnapshot *incomplete = [[MusicLibrarySnapshot alloc] initWithDictionary:@{}];
    Check(![store saveSnapshot:incomplete atDate:start force:YES didWrite:&wrote error:&error] && error, @"Incomplete scan never becomes a backup");
    NSString *blockedPath = [directory.path stringByAppendingPathComponent:@"not-a-directory"];
    [[NSData data] writeToFile:blockedPath atomically:YES];
    MusicLibraryBackupStore *blocked = [[MusicLibraryBackupStore alloc] initWithDirectoryURL:[NSURL fileURLWithPath:blockedPath isDirectory:YES]];
    error = nil;
    Check(![blocked saveSnapshot:snapshot atDate:start force:YES didWrite:&wrote error:&error] && error && !wrote,
        @"Unavailable snapshot directory fails without reporting a write");

    for (NSUInteger day = 1; day < 60; day++) {
        NSDate *date = [start dateByAddingTimeInterval:day * 86400.0];
        Check([store saveSnapshot:snapshot atDate:date force:NO didWrite:&wrote error:&error] != nil, @"Retention fixture snapshot written");
    }
    for (NSUInteger index = 0; index < 24; index++) {
        NSDate *date = [start dateByAddingTimeInterval:(60 + index) * 86400.0];
        Check([store saveSnapshot:snapshot atDate:date force:YES didWrite:&wrote error:&error] != nil,
            @"Manual retention fixture written");
    }
    NSUInteger automatic = 0, manualCount = 0, invalid = 0;
    for (NSURL *url in store.snapshotURLs) {
        NSDictionary *entry = [MusicLibraryBackupStore verifiedEnvelopeAtURL:url error:nil];
        if (!entry) { invalid++; continue; }
        if ([entry[@"automatic"] boolValue]) automatic++; else manualCount++;
    }
    Check(automatic == 31, @"Retention keeps 30 daily and one older month-end snapshot");
    Check(manualCount == 20 && invalid == 1, @"Retention bounds manual snapshots and preserves invalid evidence files");
    Check([store.latestSnapshotDate compare:[start dateByAddingTimeInterval:83 * 86400.0]] == NSOrderedSame, @"Latest snapshot date reported");
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
}

static void TestBorders(Preferences *preferences)
{
    NSArray *identifiers = @[WindowBorderSetList, WindowBorderCurrentTrack, WindowBorderMusicLibrary];
    [preferences resetWindowBorderColors];
    for (NSString *identifier in identifiers) Check(![preferences windowBorderColorForIdentifier:identifier], @"Native border default");
    NSArray *colors = @[NSColor.redColor, NSColor.blueColor, NSColor.greenColor];
    for (NSUInteger index = 0; index < identifiers.count; index++) [preferences setWindowBorderColor:colors[index] forIdentifier:identifiers[index]];
    Preferences *reloaded = [Preferences new];
    for (NSUInteger index = 0; index < identifiers.count; index++) {
        NSColor *actual = [[reloaded windowBorderColorForIdentifier:identifiers[index]] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        NSColor *expected = [colors[index] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        Check(actual && fabs(actual.redComponent - expected.redComponent) < 0.001 && fabs(actual.blueComponent - expected.blueComponent) < 0.001, @"Saved colors survive new Preferences instance");
    }
    [preferences setWindowBorderColor:nil forIdentifier:WindowBorderSetList];
    Check(![preferences windowBorderColorForIdentifier:WindowBorderSetList] && [preferences windowBorderColorForIdentifier:WindowBorderCurrentTrack], @"Per-window default preserves other colors");
    [preferences resetWindowBorderColors];
    for (NSString *identifier in identifiers) Check(![preferences windowBorderColorForIdentifier:identifier], @"Reset all native borders");
    [[NSUserDefaults standardUserDefaults] setObject:@{@"SetList":@[@(NAN), @0, @0], @"CurrentTrack":@[@1]} forKey:@"windowBorderColors"];
    Check(![preferences windowBorderColorForIdentifier:WindowBorderSetList] && ![preferences windowBorderColorForIdentifier:WindowBorderCurrentTrack], @"Corrupt saved colors ignored");
    [preferences resetWindowBorderColors];
}

static void TestBorderRendering(void)
{
    for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        for (NSNumber *factor in @[@1, @2]) {
            NSInteger scale = factor.integerValue;
            NSView *border = [[NSClassFromString(@"InterfaceBorderView") alloc] initWithFrame:NSMakeRect(0, 0, 320, 200)];
            [border setValue:NSColor.systemBlueColor forKey:@"borderColor"];
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:320 * scale pixelsHigh:200 * scale bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            bitmap.size = border.bounds.size;
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
            NSRectFillUsingOperation(border.bounds, NSCompositingOperationClear);
            [[NSAppearance appearanceNamed:name] performAsCurrentDrawingAppearance:^{ [border drawRect:border.bounds]; }];
            [NSGraphicsContext restoreGraphicsState];
            NSColor *first;
            NSColor *last;
            for (NSInteger y = 0; y < 8 * scale && !first; y++) {
                NSColor *sample = [[bitmap colorAtX:160 * scale y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                if (sample.alphaComponent > .4) first = sample;
            }
            for (NSInteger y = 200 * scale - 1; y >= 192 * scale && !last; y--) {
                NSColor *sample = [[bitmap colorAtX:160 * scale y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                if (sample.alphaComponent > .4) last = sample;
            }
            Check(first.alphaComponent > .4 && last.alphaComponent > .4, @"Gradient remains visible at both window edges in Light and Dark modes");
            Check(fabs(first.redComponent - last.redComponent) + fabs(first.greenComponent - last.greenComponent) > .03, @"Border has a subtle vertical color gradient");
            Check([bitmap colorAtX:160 * scale y:0].alphaComponent == 0,
                  @"Top border keeps a clear outer gutter at 1x and Retina resolution");
            Check([bitmap colorAtX:160 * scale y:100 * scale].alphaComponent == 0, @"Border leaves window content fully clear");
            Check([bitmap colorAtX:scale y:scale].alphaComponent == 0 && [bitmap colorAtX:318 * scale y:198 * scale].alphaComponent == 0, @"Rounded corners do not paint into the native corner cutout");
            CGFloat coverage = 0;
            for (NSInteger y = 0; y < 8 * scale; y++) coverage += [bitmap colorAtX:160 * scale y:y].alphaComponent;
            Check(coverage / scale > .7 && coverage / scale < 2.1, @"Border retains a fine edge at 1x and Retina resolution");
            Check([border hitTest:NSMakePoint(160, 1)] == nil, @"Gradient edge never captures pointer input");
        }
    }
}

static void TestWindow(MusicLibraryController *controller, MusicLibrarySnapshot *snapshot, Preferences *preferences)
{
    NSWindow *window = controller.window;
    Check((window.styleMask & NSWindowStyleMaskResizable) != 0, @"Browser resizable");
    Check(FindViews(window.contentView, NSImageView.class).count == 0, @"No album artwork views");
    NSArray *tables = FindViews(window.contentView, NSTableView.class);
    Check(tables.count == 2, @"Playlist and track tables");
    NSTableView *tracks;
    NSTableView *playlists;
    for (NSTableView *table in tables) {
        if ([table.accessibilityLabel isEqual:@"Music library tracks"]) tracks = table;
        else playlists = table;
    }
    [window.contentView layoutSubtreeIfNeeded];
    Check(playlists.enclosingScrollView.bounds.size.width >= 96, @"Playlist sidebar remains visible");
    Check(tracks.enclosingScrollView.bounds.size.width >= 360, @"Track pane remains visible");
    NSTableColumn *rowNumberColumn = tracks.tableColumns.firstObject;
    Check([rowNumberColumn.identifier isEqual:@"visibleRowNumber"] && [rowNumberColumn.title isEqual:@"#"],
          @"Visible row number is the first track column");
    CGFloat digitTextWidth = ceil([@"999" sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12]}].width);
    CGFloat threeDigitWidth = digitTextWidth + 2;
    Check(rowNumberColumn.width == threeDigitWidth && rowNumberColumn.width < 36,
          @"Row number defaults to the compact width needed for three digits");
    Check(rowNumberColumn.minWidth == digitTextWidth && rowNumberColumn.minWidth < threeDigitWidth &&
          rowNumberColumn.maxWidth > rowNumberColumn.minWidth &&
          (rowNumberColumn.resizingMask & NSTableColumnUserResizingMask),
          @"Row number can shrink to the exact measured three-digit width");
    CGFloat compactNumberWidth = rowNumberColumn.width;
    rowNumberColumn.width = rowNumberColumn.minWidth;
    Check(rowNumberColumn.width == rowNumberColumn.minWidth && rowNumberColumn.width < compactNumberWidth,
          @"Row number column accepts a narrower user width");
    rowNumberColumn.width = compactNumberWidth;
    for (NSTableColumn *column in tracks.tableColumns) {
        Check((column.resizingMask & NSTableColumnUserResizingMask) != 0 && column.maxWidth > column.minWidth,
              @"Every Music Library track column is user-resizable");
    }
    NSTableColumn *titleColumn = [tracks tableColumnWithIdentifier:@"title"];
    CGFloat titleWidth = titleColumn.width;
    titleColumn.width = titleWidth + 30;
    Check(titleColumn.width == titleWidth + 30, @"Metadata columns accept user width changes");
    titleColumn.width = titleWidth;
    NSTableColumn *playlistColumn = playlists.tableColumns.firstObject;
    Check((playlistColumn.resizingMask & NSTableColumnUserResizingMask) != 0 && playlistColumn.maxWidth > playlistColumn.minWidth,
          @"Playlist table column is user-resizable inside the sidebar");
    NSTextField *firstNumber = (NSTextField *)[tracks.delegate tableView:tracks viewForTableColumn:rowNumberColumn row:0];
    NSTextField *lastNumber = (NSTextField *)[tracks.delegate tableView:tracks viewForTableColumn:rowNumberColumn row:4];
    Check([firstNumber.stringValue isEqual:@"1"] && [lastNumber.stringValue isEqual:@"5"],
          @"Visible rows display sequential one-based numbers");
    Check(![tracks.delegate tableView:tracks shouldReorderColumn:0 toColumn:1] &&
          ![tracks.delegate tableView:tracks shouldReorderColumn:1 toColumn:0] &&
           [tracks.delegate tableView:tracks shouldReorderColumn:1 toColumn:2],
          @"Row numbers stay first while metadata columns remain reorderable");
    NSRect playlistFrame = [playlists.enclosingScrollView convertRect:playlists.enclosingScrollView.bounds
                                                               toView:window.contentView];
    NSRect trackFrame = [tracks.enclosingScrollView convertRect:tracks.enclosingScrollView.bounds
                                                       toView:window.contentView];
    Check(NSMaxY(playlistFrame) > NSMaxY(trackFrame) + 20,
          @"Playlist reaches the title-bar row while track controls stay above songs");
    Check(tracks.numberOfRows == 5 && playlists.numberOfRows == 4, @"Fixture rows visible");
    NSButton *preview;
    NSButton *pausePreview;
    NSButton *stopPreview;
    NSButton *playlistOrder;
    NSButton *refresh;
    for (NSButton *button in FindViews(window.contentView, NSButton.class)) {
        if ([button.accessibilityLabel isEqual:@"Preview selected library track"]) preview = button;
        if ([button.accessibilityLabel isEqual:@"Pause or resume headphone preview"]) pausePreview = button;
        if ([button.accessibilityLabel isEqual:@"Stop headphone preview"]) stopPreview = button;
        if ([button.title isEqual:@"Playlist order"]) playlistOrder = button;
        if ([button.title isEqual:@"Refresh"]) refresh = button;
    }
    NSPopUpButton *columns = [FindViews(window.contentView, NSPopUpButton.class) firstObject];
    Check(preview != nil && !preview.enabled, @"Explicit preview control starts disabled without a selection");
    [window.contentView layoutSubtreeIfNeeded];
    Check(NSEqualSizes(preview.frame.size, pausePreview.frame.size) && NSEqualSizes(preview.frame.size, stopPreview.frame.size),
          @"Preview transport buttons use one uniform fixed size");
    NSSize transportButtonSize = pausePreview.frame.size;
    pausePreview.title = @"Resume";
    [window.contentView layoutSubtreeIfNeeded];
    Check(NSEqualSizes(pausePreview.frame.size, transportButtonSize) && NSEqualSizes(preview.frame.size, stopPreview.frame.size),
          @"Pause to Resume title change does not resize transport buttons");
    pausePreview.title = @"Pause";
    [tracks selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    Check(preview.enabled && [AuditionPlayer sharedInstance].state == AuditionStateStopped, @"Selecting local music enables preview without starting it");
    [tracks selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
    Check(!preview.enabled, @"Cloud-only preview unavailable");
    [tracks selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] byExtendingSelection:NO];
    Check(!preview.enabled, @"Preview accepts one track without changing multi-row Add semantics");
    Check(tracks.doubleAction == NSSelectorFromString(@"_addSelection:"), @"Double-click continues to Add to Set List");
    [tracks deselectAll:nil];
    id<NSTableViewDataSource> source = tracks.dataSource;
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    NSMutableArray *writers = [NSMutableArray array];
    for (NSInteger row = 0; row < tracks.numberOfRows; row++) {
        id writer = [source tableView:tracks pasteboardWriterForRow:row];
        if (writer) [writers addObject:writer];
    }
    Check([pasteboard writeObjects:writers], @"Table creates drag pasteboard");
    NSArray *urls = [pasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    Check(urls.count == 2, @"Actual drag data contains two local file URLs");
    MusicAppManager *parser = [FixtureMusicAppManager new];
    Check([parser parsePasteboard:pasteboard].fileURLs.count == 2, @"Existing importer reads track drag data");
    [pasteboard releaseGlobally];
    Check(![source tableView:tracks pasteboardWriterForRow:2], @"Cloud-only drag rejected");
    NSUInteger playlistRow = [snapshot.playlists indexOfObjectPassingTest:^BOOL(NSDictionary *playlist, NSUInteger index, BOOL *stop) { return [playlist[@"id"] isEqual:@"set"]; }];
    NSPasteboardItem *playlistWriter = (NSPasteboardItem *)[playlists.dataSource tableView:playlists pasteboardWriterForRow:playlistRow];
    Check([[playlistWriter propertyListForType:MusicLibraryPlaylistPasteboardType] count] == 3, @"Playlist drag contains all local files in original order");
    NSPasteboard *playlistPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [playlistPasteboard writeObjects:@[playlistWriter]];
    Check([parser parsePasteboard:playlistPasteboard].fileURLs.count == 3, @"Existing importer reads playlist drag data");
    [playlistPasteboard releaseGlobally];
    NSSearchField *search = [FindViews(window.contentView, NSSearchField.class) firstObject];
    search.stringValue = @"cafe";
    [search.delegate controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
    Check(tracks.numberOfRows == 1, @"Search UI filters actual table");
    NSTextField *filteredNumber = (NSTextField *)[tracks.delegate tableView:tracks viewForTableColumn:rowNumberColumn row:0];
    Check([filteredNumber.stringValue isEqual:@"1"], @"Filtered results restart visible numbering at one");
    search.stringValue = @"";
    [search.delegate controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
    NSSplitView *split = [FindViews(window.contentView, NSSplitView.class) firstObject];
    Check([NSStringFromClass(split.class) isEqual:@"MusicLibraryFixedSplitView"] &&
          split.dividerStyle == NSSplitViewDividerStyleThin && split.dividerThickness == 1,
          @"Playlist sidebar uses a thin fixed separator without a grabber");
    NSSplitViewController *splitController = (NSSplitViewController *)split.delegate;
    NSSplitViewItem *sidebarItem = splitController.splitViewItems.firstObject;
    Check(sidebarItem.minimumThickness == 96 && sidebarItem.maximumThickness == 96 && !sidebarItem.canCollapse,
          @"Playlist sidebar is fixed at its original width");
    for (NSNumber *size in @[@100, @125, @150, @175, @200]) {
        preferences.textSizePercent = size.integerValue;
        preferences.usesBoldText = YES;
        [window.contentView layoutSubtreeIfNeeded];
        Check(![window.contentView hasAmbiguousLayout], @"Scaled browser layout bounded");
        Check(tracks.numberOfRows == 5, @"Tracks retained at each text scale");
        NSRect splitHostFrame = [split.superview convertRect:split.superview.bounds toView:window.contentView];
        Check(NSMaxY(splitHostFrame) <= NSMaxY(window.contentView.bounds) - 8,
            @"Music Library reserves a real top gap below the title bar at each text scale");
        NSRect buttonFrame = [preview convertRect:preview.bounds toView:window.contentView];
        Check(NSContainsRect(window.contentView.bounds, buttonFrame), @"Preview stays reachable at each text scale");
        NSRect playlistWindowFrame = [playlists.enclosingScrollView convertRect:playlists.enclosingScrollView.bounds toView:nil];
        Check(NSMaxY(playlistWindowFrame) <= NSMaxY(window.contentLayoutRect) - 1,
            @"Playlist header stays below the native title bar at each text scale");
        for (NSView *control in @[search, playlistOrder, columns, refresh]) {
            NSRect controlFrame = [control convertRect:control.bounds toView:window.contentView];
            Check(NSContainsRect(window.contentView.bounds, controlFrame),
                @"Search toolbar controls remain fully visible at each text scale");
            NSRect controlWindowFrame = [control convertRect:control.bounds toView:nil];
            Check(NSMaxY(controlWindowFrame) <= NSMaxY(window.contentLayoutRect) - 1,
                @"Search toolbar controls stay below the native title bar at each text scale");
        }
    }
    preferences.textSizePercent = 100;
    preferences.usesBoldText = NO;
    [window setContentSize:NSMakeSize(700, 560)];
    [window.contentView layoutSubtreeIfNeeded];
    CGFloat fixedSidebarWidth = NSWidth(split.subviews.firstObject.frame);
    [split setPosition:330 ofDividerAtIndex:0];
    [window.contentView layoutSubtreeIfNeeded];
    Check(fabs(NSWidth(split.subviews.firstObject.frame) - fixedSidebarWidth) < 1,
          @"Playlist separator cannot move the fixed sidebar");
    for (NSView *control in @[playlistOrder, columns, refresh]) {
        NSRect controlFrame = [control convertRect:control.bounds toView:window.contentView];
        Check(NSContainsRect(window.contentView.bounds, controlFrame),
            @"Right-side toolbar buttons remain visible at the minimum window width");
    }
    preferences.textSizePercent = 200;
    preferences.scalesInterfaceWithWindow = YES;
    Check(window.contentMinSize.width <= 1401,
          @"Responsive Music Library does not enforce its full scaled design width");
    preferences.textSizePercent = 100;
    NSSize start = window.contentView.frame.size;
    [window setContentSize:NSMakeSize(start.width + 90, start.height)];
    NSSize widthOnly = window.contentView.frame.size;
    Check(widthOnly.width > start.width + 80 && fabs(widthOnly.height - start.height) < 1,
          @"Music Library accepts width-only native resizing with uniform scaling enabled");
    [window setContentSize:NSMakeSize(widthOnly.width, widthOnly.height + 70)];
    NSSize heightOnly = window.contentView.frame.size;
    Check(heightOnly.height > widthOnly.height + 60 && fabs(heightOnly.width - widthOnly.width) < 1,
          @"Music Library accepts height-only native resizing with uniform scaling enabled");
    Check(FindViews(window.contentView, NSImageView.class).count == 0, @"Uniform scaling introduces no artwork");
    preferences.scalesInterfaceWithWindow = NO;
    [preferences setWindowBorderColor:NSColor.redColor forIdentifier:WindowBorderMusicLibrary];
    NSView *border = window.contentView.subviews.lastObject;
    Check([NSStringFromClass(border.class) isEqual:@"InterfaceBorderView"] && !border.hidden, @"Live library border visible");
    Check([border hitTest:NSMakePoint(1, 1)] == nil, @"Border does not intercept pointer input");
    [preferences resetWindowBorderColors];
    Check(border.hidden, @"Default removes custom border");
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *suite = @"com.ezscape.EZEmbrace.LibraryQA";
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:suite];
        Preferences *preferences = [Preferences sharedInstance];
        Check(preferences.musicLibraryDailySnapshotsEnabled, @"Daily snapshots default to enabled");
        preferences.musicLibraryDailySnapshotsEnabled = NO;
        __unused FixtureMusicAppManager *automaticManager = [FixtureMusicAppManager new];
        NSDate *automaticDeadline = [NSDate dateWithTimeIntervalSinceNow:0.25];
        while (!sAutomaticRefreshes && [automaticDeadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Check(sAutomaticRefreshes == 1, @"Read-only Music mirror refreshes automatically when daily snapshots are disabled");
        preferences.musicLibraryDailySnapshotsEnabled = YES;
        NSString *fixtureDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:fixtureDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *first = [fixtureDirectory stringByAppendingPathComponent:@"library-fixture-a.wav"];
        NSString *second = [fixtureDirectory stringByAppendingPathComponent:@"library-fixture-b.aiff"];
        [[NSData data] writeToFile:first atomically:YES];
        [[NSData data] writeToFile:second atomically:YES];
        MusicLibrarySnapshot *snapshot = Fixture(first, second);
        TestSnapshot(snapshot);
        TestBackups(snapshot);
        TestBorders(preferences);
        TestBorderRendering();
        preferences.textSizePercent = 200;
        preferences.usesBoldText = YES;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"MusicLibrary.compactRowNumberColumn.v3"];
        MusicLibraryController *controller = [[MusicLibraryController alloc] initWithSnapshot:snapshot importHandler:^(NSArray *urls) { NSLog(@"QA import: %lu local tracks", (unsigned long)urls.count); }];
        Check([[NSUserDefaults standardUserDefaults] boolForKey:@"MusicLibrary.compactRowNumberColumn.v3"],
              @"Legacy fixed row-number width migrates once to the compact default");
        TestWindow(controller, snapshot, preferences);
        printf("Music library and borders: %lu assertions passed.\n", (unsigned long)sAssertions);
        if (argc > 1 && strcmp(argv[1], "--interactive") == 0) {
            NSMenu *mainMenu = [[NSMenu alloc] init];
            NSMenuItem *applicationItem = [[NSMenuItem alloc] init];
            NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"EZ-Embrace Library QA"];
            NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit EZ-Embrace Library QA" action:@selector(terminate:) keyEquivalent:@"q"];
            quit.target = NSApp;
            [applicationMenu addItem:quit];
            applicationItem.submenu = applicationMenu;
            [mainMenu addItem:applicationItem];
            NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
            NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
            [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"]];
            editItem.submenu = editMenu;
            [mainMenu addItem:editItem];
            NSApp.mainMenu = mainMenu;
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            controller.window.title = @"Music library QA · Synthetic fixtures";
            [controller showWindow:nil];
            [NSApp activateIgnoringOtherApps:YES];
            [NSApp run];
        }
        [controller close];
        [NSFileManager.defaultManager removeItemAtPath:fixtureDirectory error:nil];
    }
    return 0;
}
