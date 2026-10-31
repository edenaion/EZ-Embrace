#import "MusicLibraryController.h"
#import "MusicLibrary.h"
#import "MusicAppManager.h"
#import "InterfaceAppearance.h"
#import "Preferences.h"
#import "AppDelegate.h"
#import "SetlistController.h"
#import "AuditionPlayer.h"
#import "AuditionRoute.h"
#import "HugAudioDevice.h"

static NSString * const MusicLibraryRowNumberColumn = @"visibleRowNumber";
static NSString * const MusicLibraryCompactRowNumberMigration = @"MusicLibrary.compactRowNumberColumn.v3";
static const CGFloat MusicLibraryTransportButtonWidth = 84;
static const CGFloat MusicLibraryTransportButtonHeight = 30;

static CGFloat MusicLibraryCompactRowNumberWidth(void)
{
    NSFont *font = [NSFont systemFontOfSize:12];
    CGFloat digits = [@"999" sizeWithAttributes:@{NSFontAttributeName:font}].width;
    return ceil(digits) + 2;
}

static CGFloat MusicLibraryMinimumRowNumberWidth(void)
{
    NSFont *font = [NSFont systemFontOfSize:12];
    CGFloat digits = [@"999" sizeWithAttributes:@{NSFontAttributeName:font}].width;
    return ceil(digits);
}

@interface MusicLibraryFixedSplitView : NSSplitView
@end
@implementation MusicLibraryFixedSplitView
- (CGFloat) dividerThickness
{
    return 1;
}
- (void) resetCursorRects {}
- (void) mouseDown:(NSEvent *)event {}
@end

@interface AuditionSeekSlider : NSSlider
@property (nonatomic, readonly) BOOL trackingPreview;
@end
@implementation AuditionSeekSlider
- (void) mouseDown:(NSEvent *)event
{
    _trackingPreview = YES;
    [super mouseDown:event];
    _trackingPreview = NO;
}
@end

@interface MusicLibraryController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate>
@end

@implementation MusicLibraryController {
    MusicLibrarySnapshot *_snapshot;
    BOOL _usesLiveLibrary;
    NSTableView *_playlistTable;
    NSTableView *_trackTable;
    NSSearchField *_searchField;
    NSButton *_refreshButton;
    NSButton *_addButton;
    NSTextField *_status;
    NSPopUpButton *_columnsButton;
    NSArray<NSDictionary *> *_visibleTracks;
    NSString *_selectedPlaylistID;
    void (^_importHandler)(NSArray<NSURL *> *);
    AuditionPlayer *_audition;
    NSUUID *_auditionRequestIdentifier;
    NSButton *_previewButton;
    NSButton *_pausePreviewButton;
    NSButton *_stopPreviewButton;
    AuditionSeekSlider *_previewSeek;
    NSSlider *_previewVolume;
    NSTextField *_previewTitle;
    NSTextField *_previewStatus;
    NSTextField *_previewTime;
    NSTextField *_previewVolumeValue;
    NSString *_auditionOutputName;
    NSSplitViewController *_librarySplitViewController;
    NSSplitViewItem *_librarySidebarItem;
}

- (instancetype) init { return [self initWithSnapshot:nil importHandler:nil]; }

- (instancetype) initWithSnapshot:(MusicLibrarySnapshot *)snapshot importHandler:(void (^)(NSArray<NSURL *> *))handler
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(180, 180, 1000, 560)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
                  NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        _snapshot = snapshot;
        _usesLiveLibrary = !snapshot;
        _importHandler = [handler copy];
        _selectedPlaylistID = [[NSUserDefaults standardUserDefaults] stringForKey:@"MusicLibrary.selectedPlaylist"] ?: @"all";
        [self _buildWindow];
    }
    return self;
}

- (void) dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (NSScrollView *) _scrollViewForTable:(NSTableView *)table
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;
    scroll.documentView = table;
    return scroll;
}

- (NSTableView *) _makeTable
{
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.delegate = self;
    table.dataSource = self;
    table.rowHeight = 24;
    table.usesAlternatingRowBackgroundColors = YES;
    table.allowsMultipleSelection = YES;
    table.allowsEmptySelection = YES;
    table.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
    [table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    [table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    return table;
}

- (void) _buildTablesInSplitViewController:(NSSplitViewController *)splitController toolbar:(NSView *)toolbar
{
    _playlistTable = [self _makeTable];
    _playlistTable.accessibilityLabel = @"Music playlists";
    _playlistTable.allowsMultipleSelection = NO;
    NSTableColumn *playlistColumn = [[NSTableColumn alloc] initWithIdentifier:@"playlist"];
    playlistColumn.title = @"Playlists";
    playlistColumn.width = 225;
    playlistColumn.minWidth = 64;
    playlistColumn.maxWidth = 1200;
    playlistColumn.resizingMask = NSTableColumnUserResizingMask | NSTableColumnAutoresizingMask;
    [_playlistTable addTableColumn:playlistColumn];
    _trackTable = [self _makeTable];
    _trackTable.accessibilityLabel = @"Music library tracks";
    _trackTable.autosaveName = @"MusicLibraryColumns";
    _trackTable.autosaveTableColumns = YES;
    _trackTable.target = self;
    _trackTable.doubleAction = @selector(_addSelection:);
    NSTableColumn *rowNumber = [[NSTableColumn alloc] initWithIdentifier:MusicLibraryRowNumberColumn];
    rowNumber.title = @"#";
    rowNumber.headerToolTip = @"Visible row number";
    rowNumber.width = MusicLibraryCompactRowNumberWidth();
    rowNumber.minWidth = MusicLibraryMinimumRowNumberWidth();
    rowNumber.maxWidth = 160;
    rowNumber.resizingMask = NSTableColumnUserResizingMask;
    [_trackTable addTableColumn:rowNumber];
    NSArray *visible = [[NSUserDefaults standardUserDefaults] arrayForKey:@"MusicLibrary.visibleColumns"];
    for (NSDictionary *definition in [MusicLibrarySnapshot columns]) {
        NSString *key = definition[@"key"];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:key];
        column.title = definition[@"title"];
        column.width = [definition[@"width"] doubleValue];
        column.minWidth = 50;
        column.maxWidth = 2400;
        column.resizingMask = NSTableColumnUserResizingMask;
        column.hidden = visible ? ![visible containsObject:key] : ![definition[@"visible"] boolValue];
        if ([key isEqual:@"title"]) column.hidden = NO;
        BOOL text = [@[@"title", @"artist", @"album", @"albumArtist", @"genre", @"composer", @"grouping", @"comments", @"kind", @"availability", @"location", @"sortTitle", @"sortArtist", @"sortAlbum", @"sortAlbumArtist", @"sortComposer"] containsObject:key];
        column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:key ascending:YES
            selector:text ? @selector(localizedStandardCompare:) : @selector(compare:)];
        [_trackTable addTableColumn:column];
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:MusicLibraryCompactRowNumberMigration]) {
        rowNumber.width = MusicLibraryCompactRowNumberWidth();
        [defaults setBool:YES forKey:MusicLibraryCompactRowNumberMigration];
    }
    NSInteger rowNumberIndex = [_trackTable.tableColumns indexOfObject:rowNumber];
    if (rowNumberIndex != 0) [_trackTable moveColumn:rowNumberIndex toColumn:0];
    NSScrollView *playlists = [self _scrollViewForTable:_playlistTable];
    NSScrollView *tracks = [self _scrollViewForTable:_trackTable];
    playlists.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *trackPane = [[NSView alloc] initWithFrame:NSZeroRect];
    trackPane.translatesAutoresizingMaskIntoConstraints = NO;
    tracks.translatesAutoresizingMaskIntoConstraints = NO;
    [trackPane addSubview:toolbar];
    [trackPane addSubview:tracks];
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:trackPane.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:trackPane.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:trackPane.trailingAnchor],
        [tracks.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:10],
        [tracks.leadingAnchor constraintEqualToAnchor:trackPane.leadingAnchor],
        [tracks.trailingAnchor constraintEqualToAnchor:trackPane.trailingAnchor],
        [tracks.bottomAnchor constraintEqualToAnchor:trackPane.bottomAnchor]
    ]];
    NSViewController *playlistController = [[NSViewController alloc] init];
    playlistController.view = playlists;
    NSSplitViewItem *sidebar = [NSSplitViewItem splitViewItemWithViewController:playlistController];
    sidebar.minimumThickness = 96;
    sidebar.maximumThickness = 96;
    sidebar.preferredThicknessFraction = 96.0 / 980.0;
    sidebar.canCollapse = NO;
    sidebar.holdingPriority = NSLayoutPriorityDefaultHigh;
    _librarySidebarItem = sidebar;
    NSViewController *tracksController = [[NSViewController alloc] init];
    tracksController.view = trackPane;
    NSSplitViewItem *content = [NSSplitViewItem splitViewItemWithViewController:tracksController];
    content.minimumThickness = 360;
    content.canCollapse = NO;
    content.holdingPriority = NSLayoutPriorityDefaultLow;
    [splitController addSplitViewItem:sidebar];
    [splitController addSplitViewItem:content];
}

- (void) _buildColumnsMenu
{
    [_columnsButton addItemWithTitle:@"Columns"];
    for (NSDictionary *definition in [MusicLibrarySnapshot columns]) {
        [_columnsButton addItemWithTitle:definition[@"title"]];
        NSMenuItem *item = _columnsButton.lastItem;
        item.representedObject = definition[@"key"];
        item.target = self;
        item.action = @selector(_toggleColumn:);
        item.enabled = ![definition[@"key"] isEqual:@"title"];
    }
    [self _updateColumnsMenu];
}

- (void) _buildWindow
{
    NSWindow *window = self.window;
    window.title = @"Music library";
    window.excludedFromWindowsMenu = YES;
    window.titlebarAppearsTransparent = NO;
    window.releasedWhenClosed = NO;
    window.contentMinSize = NSMakeSize(700, 420);
    window.delegate = self;
    [window setFrameAutosaveName:@"MusicLibraryWindow"];
    [window setFrameUsingName:@"MusicLibraryWindow"];
    NSView *content = window.contentView;
    _searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _searchField.placeholderString = @"Search this playlist";
    _searchField.accessibilityLabel = @"Search Music library";
    _searchField.sendsSearchStringImmediately = YES;
    _searchField.delegate = self;
    _refreshButton = [NSButton buttonWithTitle:@"Refresh" target:self action:@selector(_refresh:)];
    NSButton *order = [NSButton buttonWithTitle:@"Playlist order" target:self action:@selector(_restorePlaylistOrder:)];
    order.toolTip = @"Restore the order stored in Music. Sorting here does not change your Music library.";
    _columnsButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    _columnsButton.accessibilityLabel = @"Choose library columns";
    NSStackView *toolbar = [NSStackView stackViewWithViews:@[_searchField, order, _columnsButton, _refreshButton]];
    toolbar.spacing = 8;
    toolbar.distribution = NSStackViewDistributionFill;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [_searchField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_searchField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    for (NSView *control in @[order, _columnsButton, _refreshButton]) {
        [control setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        [control setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh + 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    _status = [NSTextField labelWithString:@"Reading Music library…"];
    _status.lineBreakMode = NSLineBreakByTruncatingTail;
    _status.font = [NSFont systemFontOfSize:11];
    _status.textColor = NSColor.secondaryLabelColor;
    _status.accessibilityLabel = @"Library status";
    _addButton = [NSButton buttonWithTitle:@"Add to Set List" target:self action:@selector(_addSelection:)];
    _addButton.toolTip = @"Copy selected local tracks to the end of the Set List. You can also drag tracks or a playlist into it.";
    NSStackView *footer = [NSStackView stackViewWithViews:@[_status, _addButton]];
    footer.spacing = 8;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [_status setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _librarySplitViewController = [[NSSplitViewController alloc] init];
    NSSplitView *split = [[MusicLibraryFixedSplitView alloc] initWithFrame:NSMakeRect(0, 0, 980, 450)];
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    _librarySplitViewController.splitView = split;
    [self _buildTablesInSplitViewController:_librarySplitViewController toolbar:toolbar];
    NSView *splitHost = _librarySplitViewController.view;
    splitHost.translatesAutoresizingMaskIntoConstraints = NO;
    _audition = [AuditionPlayer sharedInstance];
    NSView *preview = [self _buildPreviewControls];
    [content addSubview:splitHost];
    [content addSubview:footer];
    [content addSubview:preview];
    NSLayoutConstraint *searchMinimumWidth = [_searchField.widthAnchor constraintGreaterThanOrEqualToConstant:48];
    searchMinimumWidth.priority = NSLayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        searchMinimumWidth,
        [splitHost.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [splitHost.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
        [splitHost.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [splitHost.bottomAnchor constraintEqualToAnchor:preview.topAnchor constant:-10],
        [preview.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [preview.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [preview.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-8],
        [footer.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [footer.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [footer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-10]
    ]];
    [self _buildColumnsMenu];
    [content layoutSubtreeIfNeeded];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_libraryUpdated:)
        name:MusicAppManagerDidUpdateBrowserNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updatePreview:)
        name:AuditionPlayerDidChangeNotification object:_audition];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateAuditionOutput:)
        name:AuditionPreferencesDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateAuditionOutput:)
        name:HugAudioDevicesDidRefreshNotification object:nil];
    [self _updateAuditionOutput:nil];
    [self _applySnapshot];
    [InterfaceAppearance installInWindow:window designSize:NSMakeSize(1000, 560)];
    [InterfaceAppearance setAllowsIndependentResizeAxes:YES inWindow:window];
    [InterfaceAppearance setBorderIdentifier:WindowBorderMusicLibrary inWindow:window];
}

- (NSView *) _buildPreviewControls
{
    _previewTitle = [NSTextField labelWithString:@"Headphone preview"];
    _previewTitle.font = [NSFont boldSystemFontOfSize:12];
    _previewTitle.lineBreakMode = NSLineBreakByTruncatingTail;
    _previewTitle.accessibilityLabel = @"Preview track";
    _previewButton = [NSButton buttonWithTitle:@"Preview" target:self action:@selector(_previewSelection:)];
    _previewButton.toolTip = @"Play one selected local track through Audition Output. The Set List keeps playing independently.";
    _previewButton.accessibilityLabel = @"Preview selected library track";
    _pausePreviewButton = [NSButton buttonWithTitle:@"Pause" target:self action:@selector(_pausePreview:)];
    _pausePreviewButton.accessibilityLabel = @"Pause or resume headphone preview";
    _stopPreviewButton = [NSButton buttonWithTitle:@"Stop" target:self action:@selector(_stopPreview:)];
    _stopPreviewButton.accessibilityLabel = @"Stop headphone preview";
    _previewSeek = [[AuditionSeekSlider alloc] initWithFrame:NSZeroRect];
    _previewSeek.target = self;
    _previewSeek.action = @selector(_seekPreview:);
    _previewSeek.continuous = NO;
    _previewSeek.accessibilityLabel = @"Headphone preview position";
    _previewTime = [NSTextField labelWithString:@"0:00 / 0:00"];
    _previewTime.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _previewTime.accessibilityLabel = @"Headphone preview time";
    [_previewSeek setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_previewSeek.widthAnchor constraintGreaterThanOrEqualToConstant:80].active = YES;
    NSStackView *transport = [NSStackView stackViewWithViews:@[_previewButton, _pausePreviewButton, _stopPreviewButton, _previewSeek, _previewTime]];
    transport.spacing = 8;
    transport.alignment = NSLayoutAttributeCenterY;
    [NSLayoutConstraint activateConstraints:@[
        [_previewButton.widthAnchor constraintEqualToConstant:MusicLibraryTransportButtonWidth],
        [_previewButton.heightAnchor constraintEqualToConstant:MusicLibraryTransportButtonHeight],
        [_pausePreviewButton.widthAnchor constraintEqualToAnchor:_previewButton.widthAnchor],
        [_pausePreviewButton.heightAnchor constraintEqualToAnchor:_previewButton.heightAnchor],
        [_stopPreviewButton.widthAnchor constraintEqualToAnchor:_previewButton.widthAnchor],
        [_stopPreviewButton.heightAnchor constraintEqualToAnchor:_previewButton.heightAnchor]
    ]];

    _previewStatus = [NSTextField labelWithString:@""];
    _previewStatus.font = [NSFont systemFontOfSize:11];
    _previewStatus.textColor = NSColor.secondaryLabelColor;
    _previewStatus.lineBreakMode = NSLineBreakByTruncatingTail;
    _previewStatus.accessibilityLabel = @"Headphone preview status and output";
    [_previewStatus setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_previewStatus setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _previewVolume = [NSSlider sliderWithValue:25 minValue:0 maxValue:100 target:self action:@selector(_changePreviewVolume:)];
    _previewVolume.continuous = YES;
    _previewVolume.accessibilityLabel = @"Headphone preview volume";
    _previewVolume.toolTip = @"Preview volume only. Main Output volume is unchanged.";
    [_previewVolume.widthAnchor constraintEqualToConstant:120].active = YES;
    _previewVolumeValue = [NSTextField labelWithString:@"25%"];
    [_previewVolumeValue.widthAnchor constraintGreaterThanOrEqualToConstant:34].active = YES;
    NSStackView *status = [NSStackView stackViewWithViews:@[_previewStatus,
        [NSTextField labelWithString:@"Preview volume"], _previewVolume, _previewVolumeValue]];
    status.spacing = 8;
    status.alignment = NSLayoutAttributeCenterY;
    NSStackView *preview = [NSStackView stackViewWithViews:@[_previewTitle, transport, status]];
    preview.orientation = NSUserInterfaceLayoutOrientationVertical;
    preview.alignment = NSLayoutAttributeLeading;
    preview.spacing = 4;
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_previewTitle.widthAnchor constraintEqualToAnchor:preview.widthAnchor],
        [transport.widthAnchor constraintEqualToAnchor:preview.widthAnchor],
        [status.widthAnchor constraintEqualToAnchor:preview.widthAnchor]
    ]];
    return preview;
}

- (void) _updateAuditionOutput:(NSNotification *)note
{
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self _updateAuditionOutput:note]; }); return; }
    Preferences *preferences = [Preferences sharedInstance];
    NSString *uid = preferences.auditionOutputDeviceUID;
    _auditionOutputName = uid.length ? @"Output unavailable" : @"Output disabled - choose in Settings > General";
    for (NSDictionary *device in AuditionOutputDevices()) {
        if ([device[@"uid"] isEqual:uid]) { _auditionOutputName = device[@"name"]; break; }
    }
    _previewVolume.integerValue = preferences.auditionVolumePercent;
    _previewVolumeValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)_previewVolume.integerValue];
    [self _updatePreview:nil];
}

- (void) _updatePreview:(NSNotification *)note
{
    BOOL active = _audition.state == AuditionStatePlaying || _audition.state == AuditionStatePaused;
    _pausePreviewButton.enabled = active;
    _pausePreviewButton.title = _audition.state == AuditionStatePaused ? @"Resume" : @"Pause";
    _stopPreviewButton.enabled = _audition.state != AuditionStateStopped;
    _previewSeek.enabled = active;
    if (!_previewSeek.trackingPreview) {
        _previewSeek.maxValue = MAX(1, _audition.duration);
        _previewSeek.doubleValue = _audition.position;
    }
    _previewTime.stringValue = [NSString stringWithFormat:@"%@ / %@", GetStringForTime(_audition.position), GetStringForTime(_audition.duration)];
    _previewTitle.stringValue = _audition.title.length
        ? [_audition.title stringByAppendingFormat:@"%@%@", _audition.artist.length ? @" · " : @"", _audition.artist]
        : @"Headphone preview";
    _previewTitle.toolTip = _previewTitle.stringValue;
    _previewStatus.stringValue = [NSString stringWithFormat:@"%@ · %@", _audition.message, _auditionOutputName ?: @""];
    _previewStatus.toolTip = _previewStatus.stringValue;
}

- (void) _previewSelection:(id)sender
{
    NSInteger row = _trackTable.selectedRow;
    if (_trackTable.numberOfSelectedRows != 1 || row < 0 || row >= (NSInteger)_visibleTracks.count) return;
    NSDictionary *track = _visibleTracks[row];
    NSURL *url = [MusicLibrarySnapshot importURLForTrack:track];
    if (url) _auditionRequestIdentifier = [_audition previewURL:url title:track[@"title"] artist:track[@"artist"]];
}

- (void) _pausePreview:(id)sender
{
    if (_audition.state == AuditionStatePaused) [_audition resume];
    else [_audition pause];
}
- (void) _stopPreview:(id)sender { [_audition stop]; }
- (void) _seekPreview:(NSSlider *)sender { [_audition seekToTime:sender.doubleValue]; }
- (void) _changePreviewVolume:(NSSlider *)sender
{
    NSInteger volume = lround(sender.doubleValue);
    Preferences *preferences = [Preferences sharedInstance];
    if (preferences.auditionVolumePercent != volume) preferences.auditionVolumePercent = volume;
}
- (void) windowWillClose:(NSNotification *)note
{
    [_audition stopPreviewWithIdentifier:_auditionRequestIdentifier];
    _auditionRequestIdentifier = nil;
}

- (void) showWindow:(id)sender
{
    [super showWindow:sender];
    if (_usesLiveLibrary) {
        _snapshot = [[MusicAppManager sharedInstance] browserSnapshot];
        [self _applySnapshot];
        [[MusicAppManager sharedInstance] refreshBrowser];
    }
}

- (void) _refresh:(id)sender { if (_usesLiveLibrary) [[MusicAppManager sharedInstance] refreshBrowser]; }

- (void) _libraryUpdated:(NSNotification *)note
{
    if (!_usesLiveLibrary) return;
    _snapshot = [[MusicAppManager sharedInstance] browserSnapshot];
    [self _applySnapshot];
}

- (void) _applySnapshot
{
    [_playlistTable reloadData];
    NSUInteger row = [_snapshot.playlists indexOfObjectPassingTest:^BOOL(NSDictionary *playlist, NSUInteger index, BOOL *stop) {
        return [playlist[@"id"] isEqual:_selectedPlaylistID];
    }];
    if (row == NSNotFound || row >= _snapshot.playlists.count) { row = 0; _selectedPlaylistID = @"all"; }
    if (_snapshot.playlists.count) [_playlistTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self _filterTracks];
}

- (void) _filterTracks
{
    _visibleTracks = [_snapshot tracksForPlaylist:_selectedPlaylistID search:_searchField.stringValue sortDescriptors:_trackTable.sortDescriptors] ?: @[];
    [_trackTable deselectAll:nil];
    [_trackTable reloadData];
    [self _updateStatus];
}

- (void) _updateStatus
{
    MusicAppManager *manager = _usesLiveLibrary ? [MusicAppManager sharedInstance] : nil;
    _refreshButton.enabled = !manager.browserLoading;
    _addButton.enabled = NO;
    NSInteger selected = _trackTable.selectedRow;
    _previewButton.enabled = _trackTable.numberOfSelectedRows == 1 && selected >= 0 &&
        selected < (NSInteger)_visibleTracks.count && [MusicLibrarySnapshot importURLForTrack:_visibleTracks[selected]] != nil;
    [_trackTable.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        if (row < _visibleTracks.count && [MusicLibrarySnapshot importURLForTrack:_visibleTracks[row]]) { _addButton.enabled = YES; *stop = YES; }
    }];
    if (manager.browserLoading) _status.stringValue = @"Reading Music library…";
    else if (manager.browserError.length) _status.stringValue = manager.browserError;
    else if (!_snapshot.tracks.count) _status.stringValue = @"No tracks in the Music library. Add local audio files to Music, then refresh.";
    else if (_trackTable.numberOfSelectedRows && !_addButton.enabled) _status.stringValue = @"Selected files are cloud-only, protected or unavailable. Choose local audio to add it.";
    else {
        NSString *synced = manager.lastLibraryRefreshDate
            ? [NSDateFormatter localizedStringFromDate:manager.lastLibraryRefreshDate dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle]
            : nil;
        NSUInteger playlistCount = _snapshot.playlists.count ? _snapshot.playlists.count - 1 : 0;
        _status.stringValue = [NSString stringWithFormat:@"Read-only mirror · %lu %@ · %lu %@ · %lu selected%@", (unsigned long)_visibleTracks.count,
            _visibleTracks.count == 1 ? @"track" : @"tracks", (unsigned long)playlistCount,
            playlistCount == 1 ? @"playlist" : @"playlists", (unsigned long)_trackTable.numberOfSelectedRows,
            synced.length ? [@" · Synced " stringByAppendingString:synced] : @""];
    }
    _status.toolTip = [_status.stringValue stringByAppendingString:@" Search and sorting stay inside EZ-Embrace. Music tracks and playlists are never edited. Cloud-only, protected and missing files cannot be added."];
}

- (void) controlTextDidChange:(NSNotification *)note { [self _filterTracks]; }

- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
    return tableView == _playlistTable ? _snapshot.playlists.count : _visibleTracks.count;
}

- (NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSTextField *field = [tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!field) {
        field = [NSTextField labelWithString:@""];
        field.identifier = column.identifier;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        [InterfaceAppearance setFont:[NSFont systemFontOfSize:12] forControl:field];
    }
    if (tableView == _playlistTable) {
        field.stringValue = _snapshot.playlists[row][@"path"];
        [InterfaceAppearance setTextColor:NSColor.labelColor forField:field];
    } else if ([column.identifier isEqual:MusicLibraryRowNumberColumn]) {
        field.stringValue = [NSString stringWithFormat:@"%ld", (long)row + 1];
        field.alignment = NSTextAlignmentRight;
        [InterfaceAppearance setTextColor:NSColor.secondaryLabelColor forField:field];
    } else {
        NSDictionary *track = _visibleTracks[row];
        field.stringValue = [MusicLibrarySnapshot displayValueForTrack:track column:column.identifier];
        [InterfaceAppearance setTextColor:[track[@"availability"] isEqual:@"Local file"] ? NSColor.labelColor : NSColor.secondaryLabelColor forField:field];
    }
    field.toolTip = field.stringValue;
    return field;
}

- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
    if (notification.object == _playlistTable) {
        NSInteger row = _playlistTable.selectedRow;
        if (row >= 0 && row < (NSInteger)_snapshot.playlists.count) {
            _selectedPlaylistID = _snapshot.playlists[row][@"id"];
            if (_usesLiveLibrary) [[NSUserDefaults standardUserDefaults] setObject:_selectedPlaylistID forKey:@"MusicLibrary.selectedPlaylist"];
        }
        [self _filterTracks];
    } else [self _updateStatus];
}

- (void) tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors { [self _filterTracks]; }

- (BOOL) tableView:(NSTableView *)tableView shouldReorderColumn:(NSInteger)columnIndex toColumn:(NSInteger)newColumnIndex
{
    if (tableView != _trackTable) return YES;
    NSTableColumn *column = _trackTable.tableColumns[columnIndex];
    if ([column.identifier isEqual:MusicLibraryRowNumberColumn]) return NO;
    return newColumnIndex > 0;
}

- (void) _restorePlaylistOrder:(id)sender { _trackTable.sortDescriptors = @[]; }

- (void) _updateColumnsMenu
{
    for (NSMenuItem *item in _columnsButton.itemArray) {
        if (!item.representedObject) continue;
        NSTableColumn *column = [_trackTable tableColumnWithIdentifier:item.representedObject];
        item.state = column && !column.hidden ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void) _toggleColumn:(NSMenuItem *)sender
{
    NSTableColumn *column = [_trackTable tableColumnWithIdentifier:sender.representedObject];
    if (!column || [column.identifier isEqual:@"title"]) return;
    column.hidden = !column.hidden;
    NSMutableArray *visible = [NSMutableArray array];
    for (NSTableColumn *entry in _trackTable.tableColumns) if (!entry.hidden) [visible addObject:entry.identifier];
    [[NSUserDefaults standardUserDefaults] setObject:visible forKey:@"MusicLibrary.visibleColumns"];
    [self _updateColumnsMenu];
}

- (NSArray<NSDictionary *> *) _tracksForTable:(NSTableView *)table rows:(NSIndexSet *)rows
{
    NSMutableArray *tracks = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        if (table == _playlistTable && row < _snapshot.playlists.count) {
            [tracks addObjectsFromArray:[_snapshot tracksForPlaylist:_snapshot.playlists[row][@"id"] search:@"" sortDescriptors:@[]]];
        } else if (table == _trackTable && row < _visibleTracks.count) [tracks addObject:_visibleTracks[row]];
    }];
    return tracks;
}

- (id<NSPasteboardWriting>) tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    if (row < 0) return nil;
    if (tableView == _trackTable) {
        return row < (NSInteger)_visibleTracks.count ? [MusicLibrarySnapshot importURLForTrack:_visibleTracks[row]] : nil;
    }
    NSArray<NSURL *> *urls = [MusicLibrarySnapshot importURLsForTracks:[self _tracksForTable:tableView rows:[NSIndexSet indexSetWithIndex:row]]];
    if (!urls.count) return nil;
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    NSMutableArray *locations = [NSMutableArray array];
    for (NSURL *url in urls) [locations addObject:url.absoluteString];
    [item setPropertyList:locations forType:MusicLibraryPlaylistPasteboardType];
    return item;
}

- (void) _addSelection:(id)sender
{
    NSArray *tracks = [self _tracksForTable:_trackTable rows:_trackTable.selectedRowIndexes];
    NSArray *urls = [MusicLibrarySnapshot importURLsForTracks:tracks];
    if (!urls.count) return;
    BOOL added = YES;
    if (_importHandler) _importHandler(urls);
    else added = [[GetAppDelegate() setlistController] addTracksWithURLs:urls];
    if (!added) { _status.stringValue = @"No tracks added"; return; }
    NSUInteger skipped = tracks.count - urls.count;
    _status.stringValue = [NSString stringWithFormat:@"Added %lu local %@%@", (unsigned long)urls.count, urls.count == 1 ? @"track" : @"tracks",
        skipped ? [NSString stringWithFormat:@" · Skipped %lu unavailable tracks", (unsigned long)skipped] : @""];
}
@end
