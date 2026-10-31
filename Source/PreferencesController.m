// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "PreferencesController.h"
#import "InterfaceAppearance.h"
#import "Preferences.h"
#import "Player.h"
#import "ScriptFile.h"
#import "ScriptsManager.h"
#import "HugAudioDevice.h"
#import "AppDelegate.h"
#import "AuditionRoute.h"
#import "MusicAppManager.h"

@interface PreferencesColorWell : NSColorWell
@property (nonatomic, copy) NSString *windowIdentifier;
@end
@implementation PreferencesColorWell
- (void) activate:(BOOL)exclusive
{
    [super activate:exclusive];
    NSColorPanel *panel = [NSColorPanel sharedColorPanel];
    [panel setShowsAlpha:NO];
    [panel setMode:NSColorPanelModeWheel];
    [panel makeKeyAndOrderFront:self];
}
@end

@interface PreferencesController ()

- (IBAction) changeMainDevice:(id)sender;
- (IBAction) changeMainDeviceAttributes:(id)sender;

@property (nonatomic, strong) IBOutlet NSView *generalPane;
@property (nonatomic, strong) IBOutlet NSView *appearancePane;
@property (nonatomic, strong) IBOutlet NSView *advancedPane;


@property (nonatomic, weak)   IBOutlet NSPopUpButton *mainDevicePopUp;
@property (nonatomic, weak)   IBOutlet NSPopUpButton *sampleRatePopUp;
@property (nonatomic, weak)   IBOutlet NSPopUpButton *framesPopUp;
@property (nonatomic, weak)   IBOutlet NSButton      *hogModeButton;
@property (nonatomic, weak)   IBOutlet NSButton      *resetVolumeButton;

@property (nonatomic, weak)   IBOutlet NSPopUpButton *scriptHandlerPopUp;

@end


@implementation PreferencesController {
    NSPopUpButton *_textSizePopUp;
    NSSlider *_textContrastSlider;
    NSTextField *_textContrastValue;
    NSButton *_boldTextButton;
    NSButton *_windowScalingButton;
    NSButton *_automaticArrangementButton;
    NSButton *_recallLayoutButton;
    NSSegmentedControl *_paneSelector;
    NSView *_paneContainer;
    NSSize _paneCanvasSize;
    NSArray<PreferencesColorWell *> *_borderColorWells;
    PreferencesColorWell *_upcomingGenreColorWell;
    NSPopUpButton *_auditionDevicePopUp;
    NSButton *_musicBackupCheckbox;
    NSButton *_musicBackupNowButton;
    NSButton *_openMusicBackupsButton;
    NSTextField *_musicBackupStatus;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (NSString *) windowNibName
{
    return @"PreferencesWindow";
}


- (void) windowDidLoad
{
    [self setPreferences:[Preferences sharedInstance]];
    [self setPlayer:[Player sharedInstance]];

    [self _buildAppearanceControls];
    [self _reflowGeneralControls];
    [self _reflowAdvancedControls];
    _paneSelector = [NSSegmentedControl segmentedControlWithLabels:@[@"General", @"Appearance", @"Advanced"]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(_selectSegment:)];
    _paneSelector.translatesAutoresizingMaskIntoConstraints = NO;
    _paneSelector.selectedSegment = 0;
    _paneContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _paneContainer.autoresizingMask = 0;
    _paneCanvasSize = NSZeroSize;
    for (NSView *pane in @[_generalPane, _appearancePane, _advancedPane]) {
        _paneCanvasSize.width = MAX(_paneCanvasSize.width, pane.frame.size.width);
        _paneCanvasSize.height = MAX(_paneCanvasSize.height, pane.frame.size.height);
    }
    _paneContainer.frame = NSMakeRect(0, 0, _paneCanvasSize.width, _paneCanvasSize.height);
    [[self window] setToolbar:nil];
    NSView *content = [[self window] contentView];
    [content addSubview:_paneContainer];
    [content addSubview:_paneSelector];
    [NSLayoutConstraint activateConstraints:@[
        [_paneSelector.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [_paneSelector.topAnchor constraintEqualToAnchor:content.topAnchor constant:12]
    ]];
    [InterfaceAppearance setContentSize:NSMakeSize(_paneCanvasSize.width, _paneCanvasSize.height + 50)
                                inWindow:[self window]];
    [self _handlePreferencesDidChange:nil];
        
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handlePreferencesDidChange:)    name:PreferencesDidChangeNotification    object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateBorderColorWells:) name:WindowBorderColorsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateTextContrastControls:) name:TextContrastDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_rebuildAuditionDevicesMenu:) name:AuditionPreferencesDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateMusicBackupControls:) name:MusicAppManagerDidUpdateBrowserNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleAudioDevicesDidRefresh:)  name:HugAudioDevicesDidRefreshNotification  object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleScriptsManagerDidReload:) name:ScriptsManagerDidReloadNotification object:nil];

    [self selectPane:0 animated:NO];
    [InterfaceAppearance installInWindow:[self window]];
}


#pragma mark - Private Methods

- (void) _reflowGeneralControls
{
    NSArray *controls = @[self.mainDevicePopUp, self.sampleRatePopUp, self.framesPopUp, self.hogModeButton, self.resetVolumeButton];
    for (NSView *view in [_generalPane.subviews copy]) [view removeFromSuperview];
    _auditionDevicePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _auditionDevicePopUp.target = self;
    _auditionDevicePopUp.action = @selector(_changeAuditionDevice:);
    _auditionDevicePopUp.accessibilityLabel = @"Audition Output";
    _auditionDevicePopUp.toolTip = @"Music library preview only. Choose a different output from Main Output, such as headphones on a second soundcard.";
    _auditionDevicePopUp.menu.autoenablesItems = NO;
    _musicBackupCheckbox = [NSButton checkboxWithTitle:@"Daily read-only snapshots" target:self action:@selector(_changeMusicBackupEnabled:)];
    _musicBackupCheckbox.accessibilityLabel = @"Daily Music library snapshots";
    _musicBackupCheckbox.toolTip = @"Save Music metadata and playlist structure once per day while EZ-Embrace runs. Audio files are not copied.";
    _musicBackupNowButton = [NSButton buttonWithTitle:@"Back Up Now" target:self action:@selector(_backupMusicLibraryNow:)];
    _openMusicBackupsButton = [NSButton buttonWithTitle:@"Open Snapshots" target:self action:@selector(_openMusicBackups:)];
    NSStackView *backupButtons = [NSStackView stackViewWithViews:@[_musicBackupNowButton, _openMusicBackupsButton]];
    backupButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    backupButtons.spacing = 8;
    _musicBackupStatus = [NSTextField wrappingLabelWithString:@"No snapshot yet"];
    _musicBackupStatus.font = [NSFont systemFontOfSize:11];
    _musicBackupStatus.textColor = NSColor.secondaryLabelColor;
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Main Output:"], controls[0]],
        @[[NSTextField labelWithString:@"Sample Rate:"], controls[1]],
        @[[NSTextField labelWithString:@"Buffer Size:"], controls[2]],
        @[[NSGridCell emptyContentView], controls[3]],
        @[[NSGridCell emptyContentView], controls[4]],
        @[[NSTextField labelWithString:@"Audition Output:"], _auditionDevicePopUp],
        @[[NSTextField labelWithString:@"Music Library:"], _musicBackupCheckbox],
        @[[NSGridCell emptyContentView], backupButtons],
        @[[NSGridCell emptyContentView], _musicBackupStatus]
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
    NSTextField *help = [NSTextField wrappingLabelWithString:@"Preview songs in the Music library through a separate output. Main Output and preview cannot share a device or aggregate subdevice. Reconnecting an output never restarts preview automatically. Snapshots contain metadata and playlist structure only; use Time Machine for audio files and the full Music database."];
    help.font = [NSFont systemFontOfSize:11];
    help.textColor = NSColor.secondaryLabelColor;
    help.translatesAutoresizingMaskIntoConstraints = NO;
    [_generalPane setFrameSize:NSMakeSize(620, 460)];
    [_generalPane addSubview:grid];
    [_generalPane addSubview:help];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:_generalPane.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:_generalPane.leadingAnchor constant:20],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:_generalPane.trailingAnchor constant:-20],
        [_auditionDevicePopUp.widthAnchor constraintEqualToConstant:320],
        [self.mainDevicePopUp.widthAnchor constraintEqualToConstant:320],
        [_musicBackupStatus.widthAnchor constraintLessThanOrEqualToConstant:360],
        [help.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:14],
        [help.leadingAnchor constraintEqualToAnchor:grid.leadingAnchor],
        [help.trailingAnchor constraintEqualToAnchor:_generalPane.trailingAnchor constant:-20]
    ]];
    [self _updateMusicBackupControls:nil];
}

- (void) _changeMusicBackupEnabled:(NSButton *)sender
{
    Preferences *preferences = [Preferences sharedInstance];
    preferences.musicLibraryDailySnapshotsEnabled = sender.state == NSControlStateValueOn;
}

- (void) _backupMusicLibraryNow:(id)sender { [[MusicAppManager sharedInstance] backupMusicLibraryNow]; }

- (void) _openMusicBackups:(id)sender
{
    MusicAppManager *manager = [MusicAppManager sharedInstance];
    NSURL *directory = manager.musicLibraryBackupDirectoryURL;
    if (!directory) return;
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSWorkspace sharedWorkspace] openURL:directory];
}

- (void) _updateMusicBackupControls:(NSNotification *)note
{
    MusicAppManager *manager = [MusicAppManager sharedInstance];
    Preferences *preferences = [Preferences sharedInstance];
    _musicBackupCheckbox.state = preferences.musicLibraryDailySnapshotsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _musicBackupNowButton.enabled = manager.browserSnapshot && !manager.musicLibraryBackupInProgress;
    if (manager.musicLibraryBackupInProgress) _musicBackupStatus.stringValue = @"Saving snapshot…";
    else if (manager.musicLibraryBackupError.length) _musicBackupStatus.stringValue = [@"Last backup failed: " stringByAppendingString:manager.musicLibraryBackupError];
    else if (manager.lastMusicLibraryBackupDate) {
        NSString *date = [NSDateFormatter localizedStringFromDate:manager.lastMusicLibraryBackupDate
            dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
        _musicBackupStatus.stringValue = [@"Last snapshot: " stringByAppendingString:date];
    } else _musicBackupStatus.stringValue = @"No snapshot yet";
}

- (void) _rebuildAuditionDevicesMenu:(NSNotification *)note
{
    Preferences *preferences = [Preferences sharedInstance];
    NSString *selected = preferences.auditionOutputDeviceUID ?: @"";
    [_auditionDevicePopUp removeAllItems];
    [_auditionDevicePopUp addItemWithTitle:@"Disabled"];
    _auditionDevicePopUp.lastItem.representedObject = @"";
    NSMenuItem *selectedItem = selected.length ? nil : _auditionDevicePopUp.lastItem;
    for (NSDictionary *device in AuditionOutputDevices()) {
        BOOL overlaps = AuditionOutputsOverlap([device[@"deviceID"] unsignedIntValue], preferences.mainOutputAudioDevice.objectID);
        NSString *title = overlaps ? [device[@"name"] stringByAppendingString:@" (used by Main Output)"] : device[@"name"];
        [_auditionDevicePopUp addItemWithTitle:title];
        NSMenuItem *item = _auditionDevicePopUp.lastItem;
        item.representedObject = device[@"uid"];
        item.enabled = !overlaps;
        if ([selected isEqual:device[@"uid"]]) selectedItem = item;
    }
    if (!selectedItem) {
        [_auditionDevicePopUp addItemWithTitle:[NSString stringWithFormat:@"Unavailable: %@", selected]];
        selectedItem = _auditionDevicePopUp.lastItem;
        selectedItem.representedObject = selected;
        selectedItem.enabled = NO;
    }
    [_auditionDevicePopUp selectItem:selectedItem];
}

- (void) _changeAuditionDevice:(NSPopUpButton *)sender
{
    Preferences *preferences = [Preferences sharedInstance];
    preferences.auditionOutputDeviceUID = sender.selectedItem.representedObject ?: @"";
}

- (void) _reflowAdvancedControls
{
    NSMutableArray<NSButton *> *radios = [NSMutableArray array];
    NSButton *shortcuts;
    NSPopUpButton *scripts = [self scriptHandlerPopUp];
    for (NSView *view in [_advancedPane subviews]) {
        if ([view isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)view;
            if ([[button title] hasPrefix:@"Enable keyboard"]) shortcuts = button;
            else if (![button isKindOfClass:[NSPopUpButton class]]) [radios addObject:button];
        }
    }
    for (NSView *view in [[_advancedPane subviews] copy]) [view removeFromSuperview];
    NSTextField *equalizer = [NSTextField labelWithString:@"Parametric Equalizer"];
    equalizer.accessibilityLabel = @"Equalizer type: Parametric Equalizer";
    equalizer.toolTip = @"EZ-Embrace uses one Parametric Equalizer. Use the EQ button to turn it on or off.";
    NSStackView *effectChoices = [NSStackView stackViewWithViews:radios];
    effectChoices.orientation = NSUserInterfaceLayoutOrientationVertical;
    effectChoices.alignment = NSLayoutAttributeLeading;
    effectChoices.spacing = 6;
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Equalizer:"], equalizer],
        @[[NSTextField labelWithString:@"Allow addition of:"], effectChoices],
        @[[NSTextField labelWithString:@"AppleScript handler:"], scripts],
        @[[NSGridCell emptyContentView], shortcuts]
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 18;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
    [_advancedPane setFrameSize:NSMakeSize(560, 230)];
    [_advancedPane addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:_advancedPane.leadingAnchor constant:20],
        [grid.topAnchor constraintEqualToAnchor:_advancedPane.topAnchor constant:20],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:_advancedPane.trailingAnchor constant:-20],
        [scripts.widthAnchor constraintGreaterThanOrEqualToConstant:260]
    ]];
}

- (void) _buildAppearanceControls
{
    NSPopUpButton *theme;
    for (NSView *view in [_appearancePane subviews]) {
        if ([view isKindOfClass:[NSPopUpButton class]]) theme = (NSPopUpButton *)view;
    }
    for (NSMenuItem *item in [theme.itemArray copy]) {
        if (!item.isSeparatorItem && item.title.length == 0) [theme.menu removeItem:item];
    }
    if ([theme itemWithTitle:@"Blush wash"] == nil) {
        [theme addItemWithTitle:@"Blush wash"];
        theme.lastItem.tag = ThemeTypeBlush;
    }
    [theme selectItemWithTag:[[Preferences sharedInstance] themeType]];
    for (NSView *view in [[_appearancePane subviews] copy]) [view removeFromSuperview];
    _appearancePane.frame = NSMakeRect(0, 0, 620, 560);

    _textSizePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *percent in @[@100, @125, @150, @175, @200]) {
        [_textSizePopUp addItemWithTitle:[NSString stringWithFormat:@"%@%%", percent]];
        _textSizePopUp.lastItem.tag = percent.integerValue;
    }
    _textSizePopUp.target = self;
    _textSizePopUp.action = @selector(_changeAppearance:);
    _textSizePopUp.accessibilityLabel = @"Text size";
    _textContrastSlider = [NSSlider sliderWithValue:0 minValue:0 maxValue:100 target:self action:@selector(_changeTextContrast:)];
    _textContrastSlider.continuous = YES;
    _textContrastSlider.accessibilityLabel = @"Text contrast";
    _textContrastSlider.toolTip = @"Increase text contrast. Darker in Light mode, lighter in Dark mode. Blush wash always uses black text.";
    [_textContrastSlider.widthAnchor constraintEqualToConstant:180].active = YES;
    _textContrastValue = [NSTextField labelWithString:@"Default"];
    [_textContrastValue.widthAnchor constraintEqualToConstant:58].active = YES;
    NSStackView *contrast = [NSStackView stackViewWithViews:@[_textContrastSlider, _textContrastValue]];
    contrast.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    contrast.alignment = NSLayoutAttributeCenterY;
    contrast.spacing = 8;
    _boldTextButton = [NSButton checkboxWithTitle:@"Use bold text" target:self action:@selector(_changeAppearance:)];
    _windowScalingButton = [NSButton checkboxWithTitle:@"Scale interface with window size" target:self action:@selector(_changeAppearance:)];
    _windowScalingButton.toolTip = @"Resize a window horizontally, vertically, or from a corner. Contents scale to fit without clipping. Current Track is unpinned while this is on.";

    NSTextField *themeLabel = [NSTextField labelWithString:@"Theme:"];
    NSTextField *sizeLabel = [NSTextField labelWithString:@"Text size:"];
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[themeLabel, theme], @[sizeLabel, _textSizePopUp],
        @[[NSTextField labelWithString:@"Text contrast:"], contrast],
        @[[NSGridCell emptyContentView], _boldTextButton],
        @[[NSGridCell emptyContentView], _windowScalingButton]
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
    [_appearancePane addSubview:grid];
    NSTextField *help = [NSTextField wrappingLabelWithString:@"Text size also enlarges controls and spacing. Blush wash uses soft pink window shades and black text for readability."];
    help.font = [NSFont systemFontOfSize:11];
    help.textColor = [NSColor secondaryLabelColor];
    help.translatesAutoresizingMaskIntoConstraints = NO;
    [_appearancePane addSubview:help];
    _upcomingGenreColorWell = [[PreferencesColorWell alloc] initWithFrame:NSMakeRect(0, 0, 64, 26)];
    _upcomingGenreColorWell.target = self;
    _upcomingGenreColorWell.action = @selector(_changeUpcomingGenreColor:);
    _upcomingGenreColorWell.continuous = YES;
    _upcomingGenreColorWell.accessibilityLabel = @"Other upcoming genre color";
    _upcomingGenreColorWell.toolTip = @"Highlight genuinely non-Tango Up Next songs. Tango, Milonga or Vals labels stay normal even when combined with Inst, Instrumental, Alt or Alternative. Cant is also recognized as a complete genre token.";
    [_upcomingGenreColorWell.widthAnchor constraintEqualToConstant:64].active = YES;
    [_upcomingGenreColorWell.heightAnchor constraintEqualToConstant:26].active = YES;
    NSButton *resetGenreColor = [NSButton buttonWithTitle:@"Default" target:self
        action:@selector(_resetUpcomingGenreColor:)];
    NSGridView *genreColor = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Other upcoming genres:"], _upcomingGenreColorWell, resetGenreColor]
    ]];
    genreColor.translatesAutoresizingMaskIntoConstraints = NO;
    genreColor.columnSpacing = 12;
    [genreColor columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [_appearancePane addSubview:genreColor];
    NSMutableArray *colorWells = [NSMutableArray array];
    NSMutableArray *colorRows = [NSMutableArray array];
    NSArray *identifiers = @[WindowBorderSetList, WindowBorderCurrentTrack, WindowBorderMusicLibrary];
    NSArray *titles = @[@"Set List border:", @"Current Track border:", @"Music library border:"];
    for (NSUInteger index = 0; index < identifiers.count; index++) {
        PreferencesColorWell *well = [[PreferencesColorWell alloc] initWithFrame:NSMakeRect(0, 0, 64, 26)];
        well.windowIdentifier = identifiers[index];
        well.target = self;
        well.action = @selector(_changeBorderColor:);
        well.continuous = YES;
        well.accessibilityLabel = titles[index];
        well.toolTip = @"Choose a window border color. Changes are saved automatically.";
        [well.widthAnchor constraintEqualToConstant:64].active = YES;
        [well.heightAnchor constraintEqualToConstant:26].active = YES;
        [colorWells addObject:well];
        NSButton *reset = [NSButton buttonWithTitle:@"Default" target:self action:@selector(_resetBorderColor:)];
        reset.identifier = identifiers[index];
        reset.accessibilityLabel = [@"Reset " stringByAppendingString:[titles[index] lowercaseString]];
        [colorRows addObject:@[[NSTextField labelWithString:titles[index]], well, reset]];
    }
    _borderColorWells = colorWells;
    NSGridView *colors = [NSGridView gridViewWithViews:colorRows];
    colors.translatesAutoresizingMaskIntoConstraints = NO;
    colors.columnSpacing = 12;
    colors.rowSpacing = 6;
    [colors columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [_appearancePane addSubview:colors];
    NSButton *resetAll = [NSButton buttonWithTitle:@"Reset border colors" target:self action:@selector(_resetAllBorderColors:)];
    resetAll.translatesAutoresizingMaskIntoConstraints = NO;
    [_appearancePane addSubview:resetAll];

    NSTextField *layoutTitle = [NSTextField labelWithString:@"Window layout"];
    layoutTitle.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
    layoutTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [_appearancePane addSubview:layoutTitle];
    NSButton *saveLayout = [NSButton buttonWithTitle:@"Save Current" target:self action:@selector(_saveWindowLayout:)];
    _recallLayoutButton = [NSButton buttonWithTitle:@"Recall Saved" target:self action:@selector(_recallWindowLayout:)];
    NSButton *arrangeNow = [NSButton buttonWithTitle:@"Arrange Now" target:self action:@selector(_arrangeWindows:)];
    for (NSButton *button in @[saveLayout, _recallLayoutButton, arrangeNow]) {
        [button.widthAnchor constraintEqualToConstant:112].active = YES;
        button.accessibilityLabel = button.title;
    }
    NSStackView *layoutButtons = [NSStackView stackViewWithViews:@[saveLayout, _recallLayoutButton, arrangeNow]];
    layoutButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    layoutButtons.spacing = 8;
    layoutButtons.translatesAutoresizingMaskIntoConstraints = NO;
    [_appearancePane addSubview:layoutButtons];
    _automaticArrangementButton = [NSButton checkboxWithTitle:@"Arrange automatically on launch and display changes"
        target:self action:@selector(_changeAutomaticArrangement:)];
    _automaticArrangementButton.translatesAutoresizingMaskIntoConstraints = NO;
    _automaticArrangementButton.toolTip = @"Fit Music library at left, Set List at upper right and Equalizer at lower right. Current Track stays hidden until you open it.";
    [_appearancePane addSubview:_automaticArrangementButton];
    [self _updateBorderColorWells:nil];
    [self _updateUpcomingGenreColorWell];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:_appearancePane.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:_appearancePane.leadingAnchor constant:20],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:_appearancePane.trailingAnchor constant:-20],
        [theme.widthAnchor constraintGreaterThanOrEqualToConstant:270],
        [_textSizePopUp.widthAnchor constraintEqualToConstant:120],
        [help.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:14],
        [help.leadingAnchor constraintEqualToAnchor:grid.leadingAnchor],
        [help.trailingAnchor constraintEqualToAnchor:_appearancePane.trailingAnchor constant:-20],
        [genreColor.topAnchor constraintEqualToAnchor:help.bottomAnchor constant:14],
        [genreColor.leadingAnchor constraintEqualToAnchor:grid.leadingAnchor],
        [colors.topAnchor constraintEqualToAnchor:genreColor.bottomAnchor constant:14],
        [colors.leadingAnchor constraintEqualToAnchor:grid.leadingAnchor],
        [resetAll.topAnchor constraintEqualToAnchor:colors.bottomAnchor constant:10],
        [resetAll.leadingAnchor constraintEqualToAnchor:colors.leadingAnchor],
        [layoutTitle.topAnchor constraintEqualToAnchor:resetAll.bottomAnchor constant:20],
        [layoutTitle.leadingAnchor constraintEqualToAnchor:colors.leadingAnchor],
        [layoutButtons.topAnchor constraintEqualToAnchor:layoutTitle.bottomAnchor constant:8],
        [layoutButtons.leadingAnchor constraintEqualToAnchor:layoutTitle.leadingAnchor],
        [_automaticArrangementButton.topAnchor constraintEqualToAnchor:layoutButtons.bottomAnchor constant:8],
        [_automaticArrangementButton.leadingAnchor constraintEqualToAnchor:layoutTitle.leadingAnchor]
    ]];
    [self _updateWindowLayoutControls];
}

- (void) _updateTextContrastControls:(NSNotification *)note
{
    NSInteger value = [[Preferences sharedInstance] textContrastPercent];
    _textContrastSlider.integerValue = value;
    _textContrastValue.stringValue = value ? [NSString stringWithFormat:@"%ld%%", (long)value] : @"Default";
}

- (void) _changeTextContrast:(NSSlider *)sender
{
    NSInteger value = lround(sender.doubleValue);
    Preferences *preferences = [Preferences sharedInstance];
    if (preferences.textContrastPercent != value) preferences.textContrastPercent = value;
}

- (void) _updateBorderColorWells:(NSNotification *)note
{
    for (PreferencesColorWell *well in _borderColorWells) {
        well.color = [[Preferences sharedInstance] windowBorderColorForIdentifier:well.windowIdentifier]
            ?: [NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:1];
    }
}

- (void) _updateUpcomingGenreColorWell
{
    _upcomingGenreColorWell.color = [[Preferences sharedInstance] upcomingOtherGenreColor];
}

- (void) _changeUpcomingGenreColor:(NSColorWell *)sender
{
    [Preferences sharedInstance].upcomingOtherGenreColor = sender.color;
}

- (void) _resetUpcomingGenreColor:(id)sender
{
    [_upcomingGenreColorWell deactivate];
    [[Preferences sharedInstance] resetUpcomingOtherGenreColor];
    [self _updateUpcomingGenreColorWell];
}

- (void) _changeBorderColor:(PreferencesColorWell *)sender
{
    [[Preferences sharedInstance] setWindowBorderColor:sender.color forIdentifier:sender.windowIdentifier];
}

- (void) _resetBorderColor:(NSButton *)sender
{
    for (PreferencesColorWell *well in _borderColorWells) [well deactivate];
    [[Preferences sharedInstance] setWindowBorderColor:nil forIdentifier:sender.identifier];
}

- (void) _resetAllBorderColors:(id)sender
{
    for (PreferencesColorWell *well in _borderColorWells) [well deactivate];
    [[Preferences sharedInstance] resetWindowBorderColors];
}

- (AppDelegate *) _appDelegate { return (AppDelegate *)NSApp.delegate; }

- (void) _updateWindowLayoutControls
{
    _recallLayoutButton.enabled = [[self _appDelegate] hasSavedWindowLayout];
    _automaticArrangementButton.state = [Preferences sharedInstance].automaticallyArrangesWindows
        ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void) _saveWindowLayout:(id)sender
{
    [[self _appDelegate] saveWindowLayout];
    [self _updateWindowLayoutControls];
}

- (void) _recallWindowLayout:(id)sender
{
    if (![[self _appDelegate] recallWindowLayout]) NSBeep();
}

- (void) _arrangeWindows:(id)sender
{
    [[self _appDelegate] arrangeWindowsAutomatically];
    [self _updateWindowLayoutControls];
}

- (void) _changeAutomaticArrangement:(NSButton *)sender
{
    [Preferences sharedInstance].automaticallyArrangesWindows = sender.state == NSControlStateValueOn;
}

- (void) _changeAppearance:(id)sender
{
    Preferences *preferences = [Preferences sharedInstance];
    if (sender == _textSizePopUp) preferences.textSizePercent = _textSizePopUp.selectedTag;
    else if (sender == _boldTextButton) preferences.usesBoldText = _boldTextButton.state == NSControlStateValueOn;
    else if (sender == _windowScalingButton) preferences.scalesInterfaceWithWindow = _windowScalingButton.state == NSControlStateValueOn;
}

- (void) _selectSegment:(id)sender { [self selectPane:_paneSelector.selectedSegment animated:NO]; }

- (NSMenuItem *) _itemWithTitle:(NSString *)title representedObject:(id)representedObject valid:(BOOL)valid
{
    NSMenuItem *item = [[NSMenuItem alloc] init];

    [item setTitle:title];
    [item setRepresentedObject:representedObject];
    
    if (!valid) {
        NSFont *font = [[self mainDevicePopUp] font];

        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        
        [attributes setObject:[NSColor colorNamed:@"InvalidMenuItem"] forKey:NSForegroundColorAttributeName]; 
        if (font) [attributes setObject:font forKey:NSFontAttributeName];

        NSAttributedString *as = [[NSAttributedString alloc] initWithString:title attributes:attributes];

        [item setAttributedTitle:as];

    } else {
        [item setImage:nil];
    }

    return item;
}


- (void) _rebuildDevicesMenu
{
    NSPopUpButton  *popUpButton    = [self mainDevicePopUp];
    NSMenu         *menu           = [popUpButton menu];
    HugAudioDevice *deviceToSelect = [[Preferences sharedInstance] mainOutputAudioDevice];

    __block NSMenuItem *itemToSelect = nil;

    NSMenuItem *(^makeItem)(HugAudioDevice *) = ^(HugAudioDevice *device) {
        NSMenuItem *item = nil;

        NSString *title = [device name];
        if (!title) return item;

        BOOL valid = [device isConnected];
        if (!valid) title = [NSString stringWithFormat:@"? %@", title];
        
        item = [self _itemWithTitle:title representedObject:device valid:valid];
                
        return item;
    };

    [menu removeAllItems];
    
    for (HugAudioDevice *device in [HugAudioDevice allDevices]) {
        NSMenuItem *item = makeItem(device);

        if (item) {
            [menu addItem:item];
        }

        if ([deviceToSelect isEqual:device]) {
            itemToSelect = item;
        }
    }
    
    if (!itemToSelect) {
        itemToSelect = makeItem(deviceToSelect);

        if (itemToSelect) {
            [menu insertItem:itemToSelect atIndex:0];
        }
    }

    [popUpButton selectItem:itemToSelect];
}


- (void) _rebuildSampleRateMenu
{
    NSNumber *selectedRate = @([[Preferences sharedInstance] mainOutputSampleRate]);

    __block NSMenuItem *itemToSelect = nil;

    auto makeMenu = ^NSMenuItem *(NSNumber *rate, BOOL isNA) {
        NSString *title = isNA ? @"N/A" : [NSString stringWithFormat:@"%@ Hz", rate];
        
        NSMenuItem *item = [self _itemWithTitle:title representedObject:rate valid:YES];

        if (fabs([rate doubleValue] - [selectedRate doubleValue]) < 1) {
            itemToSelect = item;
        }
        
        return item;
    };

    NSPopUpButton *popUpButton = [self sampleRatePopUp];
    NSMenu *menu = [popUpButton menu];

    HugAudioDevice *device = [[Preferences sharedInstance] mainOutputAudioDevice];

    NSArray *availableSampleRates = [device availableSampleRates];
    
    if (![availableSampleRates count]) {
        availableSampleRates = @[ selectedRate ];
    }
    
    [menu removeAllItems];
    
    for (NSNumber *number in availableSampleRates) {
        [menu addItem:makeMenu(number, NO)];
    }

    if (itemToSelect) {
        [popUpButton selectItem:itemToSelect];

    } else {
        [menu insertItem:[NSMenuItem separatorItem] atIndex:0];
        [menu insertItem:makeMenu(selectedRate, YES) atIndex:0];
        [popUpButton selectItemAtIndex:0];
    }
}


- (void) _rebuildFrameMenu
{
    NSNumber *selectedFrameSize = @([[Preferences sharedInstance] mainOutputFrames]);

    __block NSMenuItem *itemToSelect = nil;

    auto makeMenu = ^NSMenuItem *(NSNumber *frameSize, BOOL isNA) {
        NSString *title = isNA ? @"N/A" : [frameSize stringValue];
        
        NSMenuItem *item = [self _itemWithTitle:title representedObject:frameSize valid:YES];

        if ([frameSize integerValue] == [selectedFrameSize integerValue]) {
            itemToSelect = item;
        }
        
        return item;
    };

    NSPopUpButton *popUpButton = [self framesPopUp];
    NSMenu *menu = [popUpButton menu];

    HugAudioDevice *device = [[Preferences sharedInstance] mainOutputAudioDevice];

    NSArray *availableFrameSizes = [device availableFrameSizes];
    
    if (![availableFrameSizes count]) {
        availableFrameSizes = @[ selectedFrameSize ];
    }
    
    [menu removeAllItems];
    
    for (NSNumber *number in availableFrameSizes) {
        [menu addItem:makeMenu(number, NO)];
    }

    if (itemToSelect) {
        [popUpButton selectItem:itemToSelect];

    } else {
        [menu insertItem:[NSMenuItem separatorItem] atIndex:0];
        [menu insertItem:makeMenu(selectedFrameSize, YES) atIndex:0];
        [popUpButton selectItemAtIndex:0];
    }
}


- (void) _rebuildScriptHandlerMenu
{
    NSMenu *menu = [[self scriptHandlerPopUp] menu];

    NSArray    *allScriptFiles    = [[ScriptsManager sharedInstance] allScriptFiles];
    ScriptFile *handlerScriptFile = [[ScriptsManager sharedInstance] handlerScriptFile];

    NSMenuItem *itemToSelect = nil;

    [menu removeAllItems];

    // Add "None"
    {
        NSMenuItem *noneItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"None", nil) action:nil keyEquivalent:@""];
        [noneItem setTag:0];

        itemToSelect = noneItem;
        [menu addItem:noneItem];
    }

    // Add separator and one entry per script
    if ([allScriptFiles count]) {
        [menu addItem:[NSMenuItem separatorItem]];

        for (ScriptFile *scriptFile in allScriptFiles) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[scriptFile displayName] action:nil keyEquivalent:@""];
            [item setTag:1];
            [item setRepresentedObject:[scriptFile fileName]];
            
            if ([handlerScriptFile isEqual:scriptFile]) {
                itemToSelect = item;
            }

            [menu addItem:item];
        }
    }

    // Add separator and "Reveal Scripts in Finder"
    {
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *revealItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Reveal Scripts in Finder", nil) action:nil keyEquivalent:@""];
        [revealItem setTag:2];

        [menu addItem:revealItem];
    }
    
    if (itemToSelect) {
        [[self scriptHandlerPopUp] selectItem:itemToSelect];
    }
}


#pragma mark - Notifications Observers

- (void) _handlePreferencesDidChange:(NSNotification *)note
{
    Preferences *preferences = [Preferences sharedInstance];

    [_textSizePopUp selectItemWithTag:preferences.textSizePercent];
    [self _updateUpcomingGenreColorWell];
    [self _updateTextContrastControls:nil];
    _boldTextButton.state = preferences.usesBoldText ? NSControlStateValueOn : NSControlStateValueOff;
    _windowScalingButton.state = preferences.scalesInterfaceWithWindow ? NSControlStateValueOn : NSControlStateValueOff;
    [self _updateWindowLayoutControls];
    HugAudioDevice *device = [preferences mainOutputAudioDevice];
    [self _rebuildFrameMenu];
    [self _rebuildSampleRateMenu];

    BOOL resetVolumeEnabled = [device hasVolumeControl] &&
                              [device isHogModeSettable] &&
                              [preferences mainOutputUsesHogMode];

    [self setResetVolumeEnabled:resetVolumeEnabled];

    if ([device isHogModeSettable]) {
        [self setDeviceHoggable:YES];
        
        BOOL mainOutputUsesHogMode = [preferences mainOutputUsesHogMode];
        [[self hogModeButton] setState:(mainOutputUsesHogMode ? NSControlStateValueOn : NSControlStateValueOff)];

        BOOL mainOutputResetsVolume = mainOutputUsesHogMode && [preferences mainOutputResetsVolume] && [device hasVolumeControl];
        [[self resetVolumeButton] setState:(mainOutputResetsVolume ? NSControlStateValueOn : NSControlStateValueOff)];

    } else {
        [self setDeviceHoggable:NO];
        [[self hogModeButton] setState:NSControlStateValueOff];
        [[self resetVolumeButton] setState:NSControlStateValueOff];
    }
 
    [self _rebuildDevicesMenu];
    [self _rebuildAuditionDevicesMenu:nil];
    [self _updateMusicBackupControls:nil];
    [self _rebuildScriptHandlerMenu];

    [self setDeviceConnected:[device isConnected]];
}


- (void) _handleAudioDevicesDidRefresh:(NSNotification *)note
{
    [self _rebuildDevicesMenu];
    [self _rebuildAuditionDevicesMenu:nil];

    HugAudioDevice *device = [[Preferences sharedInstance] mainOutputAudioDevice];
    [self setDeviceConnected:[device isConnected]];
}


- (void) _handleScriptsManagerDidReload:(NSNotification *)note
{
    [self _rebuildScriptHandlerMenu];
}


#pragma mark - IBActions

- (IBAction) selectPane:(id)sender
{
    [self selectPane:[sender tag] animated:YES];
}


- (IBAction) changeMainDevice:(id)sender
{
    HugAudioDevice *device = [[sender selectedItem] representedObject];
    [[Preferences sharedInstance] setMainOutputAudioDevice:device];
}


- (IBAction) changeMainDeviceAttributes:(id)sender
{
    if (sender == [self framesPopUp]) {
        NSNumber *number = [[sender selectedItem] representedObject];
        
        UInt32 frames = [number unsignedIntValue];
        [[Preferences sharedInstance] setMainOutputFrames:frames];
        
    } else if (sender == [self sampleRatePopUp]) {
        NSNumber *number = [[sender selectedItem] representedObject];

        double sampleRate = [number doubleValue];
        [[Preferences sharedInstance] setMainOutputSampleRate:sampleRate];
        
    } else if (sender == [self hogModeButton]) {
        BOOL hogMode = [[self hogModeButton] state] == NSControlStateValueOn;
        [[Preferences sharedInstance] setMainOutputUsesHogMode:hogMode];

    } else if (sender == [self resetVolumeButton]) {
        BOOL resetsVolume = [[self resetVolumeButton] state] == NSControlStateValueOn;
        [[Preferences sharedInstance] setMainOutputResetsVolume:resetsVolume];
    }
}


- (IBAction) handleScriptHandlerPopUp:(id)sender
{
    NSMenuItem *selectedItem = [[self scriptHandlerPopUp] selectedItem];

    if ([selectedItem tag] == 0) {
        [[Preferences sharedInstance] setScriptHandlerName:@""];
   
    } else if ([selectedItem tag] == 1) {
        [[Preferences sharedInstance] setScriptHandlerName:[selectedItem representedObject]];
    
    } else if ([selectedItem tag] == 2) {
        [[ScriptsManager sharedInstance] revealScriptsFolder];
        [self _rebuildScriptHandlerMenu];
    }
}


#pragma mark - Public Methods

- (void) selectPane:(NSInteger)tag animated:(BOOL)animated
{
    NSView *pane;

    if (tag == 2) {
        pane = _advancedPane;

    } else if (tag == 1) {
        pane = _appearancePane;
    
    } else {
        pane = _generalPane;
    }
    
    _paneSelector.selectedSegment = tag;
    
    for (NSView *view in [_paneContainer subviews]) {
        [view removeFromSuperview];
    }

    NSRect paneFrame = [pane frame];
    paneFrame.origin.x = floor((_paneCanvasSize.width - paneFrame.size.width) / 2.0);
    paneFrame.origin.y = _paneCanvasSize.height - paneFrame.size.height;
    [pane setFrame:paneFrame];
    [_paneContainer addSubview:pane];
}


@end
