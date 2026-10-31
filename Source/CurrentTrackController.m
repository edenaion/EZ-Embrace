// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "CurrentTrackController.h"
#import "InterfaceAppearance.h"
#import "Player.h"
#import "EmbraceWindow.h"
#import "WaveformView.h"
#import "Preferences.h"
#import "Track.h"


typedef NS_ENUM(NSInteger, CurrentTrackAppearance) {
    CurrentTrackAppearanceDefault = 0,
    CurrentTrackAppearanceLight   = 1,
    CurrentTrackAppearanceDark    = 2
};


static CurrentTrackAppearance sGetCurrentTrackAppearance()
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"CurrentTrackAppearance"];
}


static void sSetCurrentTrackAppearance(CurrentTrackAppearance appearance)
{
    [[NSUserDefaults standardUserDefaults] setInteger:appearance forKey:@"CurrentTrackAppearance"];
}


static BOOL sGetCurrentTrackPinning()
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"CurrentTrackPinning"];
}


static void sSetCurrentTrackPinning(BOOL yn)
{
    [[NSUserDefaults standardUserDefaults] setBool:yn forKey:@"CurrentTrackPinning"];
}



@interface CurrentTrackController () <PlayerListener, NSWindowDelegate, NSMenuItemValidation>

- (IBAction) changeAppearance:(id)sender;
- (IBAction) changePinning:(id)sender;

@property (nonatomic, weak) IBOutlet WaveformView *waveformView;
@property (nonatomic, weak) IBOutlet NSVisualEffectView *effectView;

@property (nonatomic, strong) IBOutlet NSView *mainView;

@property (nonatomic, weak) IBOutlet NSTextField *noTrackLabel;
@property (nonatomic, weak) IBOutlet NSTextField *leftLabel;
@property (nonatomic, weak) IBOutlet NSTextField *rightLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *artistLabel;

@end


@interface CurrentTrackControllerMainView : NSView
@end

@implementation CurrentTrackControllerMainView

- (void) mouseDown:(NSEvent *)theEvent
{
    if ([theEvent type] == NSEventTypeLeftMouseDown) {
        NSEventModifierFlags modifierFlags = [NSEvent modifierFlags];
        
        if ((modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand)) == NSEventModifierFlagControl) {
            [NSMenu popUpContextMenu:[self menu] withEvent:theEvent forView:self];
            return;
        }
    }
    
    [super mouseDown:theEvent];
}


- (void) rightMouseDown:(NSEvent *)theEvent
{
    if ([theEvent type] == NSEventTypeRightMouseDown) {
        [NSMenu popUpContextMenu:[self menu] withEvent:theEvent forView:self];
    } else {
        [super rightMouseDown:theEvent];
    }
}

@end



@implementation CurrentTrackController {
    Track *_displayedTrack;
    Track *_lastFinishedTrack;
}

- (NSString *) windowNibName
{
    return @"CurrentTrackWindow";
}


- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [[Player sharedInstance] removeObserver:self forKeyPath:@"currentTrack"];
    [[Player sharedInstance] removeListener:self];
    [_displayedTrack removeObserver:self forKeyPath:@"title"];
    [_displayedTrack removeObserver:self forKeyPath:@"artist"];
    [_displayedTrack removeObserver:self forKeyPath:@"trackStatus"];

    [NSApp removeObserver:self forKeyPath:@"effectiveAppearance"];
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == _player) {
        if ([keyPath isEqualToString:@"currentTrack"]) {
            [self _updateTrack];
        }

    } else if (object == _displayedTrack) {
        if ([keyPath isEqualToString:@"trackStatus"] && object == _lastFinishedTrack &&
            [(Track *)object trackStatus] != TrackStatusPlayed && ![[Player sharedInstance] currentTrack]) {
            _lastFinishedTrack = nil;
            [self _updateTrack];
        } else {
            [self _updateMetadata];
        }

    } else if (object == NSApp) {
        if ([keyPath isEqualToString:@"effectiveAppearance"]) {
            [self _updateAppearance];
        }
    }
}


- (void) _updateTrack
{
    Track *track = [[Player sharedInstance] currentTrack] ?: _lastFinishedTrack;
    if (track != _displayedTrack) {
        [_displayedTrack removeObserver:self forKeyPath:@"title"];
        [_displayedTrack removeObserver:self forKeyPath:@"artist"];
        [_displayedTrack removeObserver:self forKeyPath:@"trackStatus"];
        _displayedTrack = track;
        [_displayedTrack addObserver:self forKeyPath:@"title" options:0 context:NULL];
        [_displayedTrack addObserver:self forKeyPath:@"artist" options:0 context:NULL];
        [_displayedTrack addObserver:self forKeyPath:@"trackStatus" options:0 context:NULL];
    }
    [self _updateMetadata];
    [[self waveformView] setTrack:track];

    if (track) {
        [[self waveformView] setHidden:NO];
        [[self leftLabel]    setHidden:NO];
        [[self rightLabel]   setHidden:NO];
        [[self statusLabel]  setHidden:NO];

        [[self noTrackLabel] setHidden:YES];

    } else {
        [[self waveformView] setHidden:YES];
        [[self leftLabel]    setHidden:YES];
        [[self rightLabel]   setHidden:YES];
        [[self statusLabel]  setHidden:YES];

        [[self noTrackLabel] setHidden:NO];
    }
}

- (void) _updateMetadata
{
    NSString *title = [_displayedTrack title];
    NSString *artist = [_displayedTrack artist];
    [[self titleLabel] setStringValue:[title length] ? title : NSLocalizedString(@"Untitled track", nil)];
    [[self artistLabel] setStringValue:[artist length] ? artist : NSLocalizedString(@"Unknown artist", nil)];
    [[self titleLabel] setToolTip:title];
    [[self artistLabel] setToolTip:artist];
    [[self statusLabel] setStringValue:[_displayedTrack trackStatus] == TrackStatusPlayed
        ? NSLocalizedString(@"Played", nil)
        : NSLocalizedString(@"Now playing", nil)];
    [[self titleLabel] setHidden:!_displayedTrack];
    [[self artistLabel] setHidden:!_displayedTrack];
    [[self statusLabel] setHidden:!_displayedTrack];
}

- (void) _buildMetadataLabels
{
    _statusLabel = [NSTextField labelWithString:@""];
    _titleLabel = [NSTextField labelWithString:@""];
    _artistLabel = [NSTextField labelWithString:@""];
    [_statusLabel setFont:[NSFont boldSystemFontOfSize:11]];
    [_titleLabel setFont:[NSFont systemFontOfSize:15 weight:NSFontWeightMedium]];
    [_artistLabel setFont:[NSFont systemFontOfSize:12]];
    [_statusLabel setAccessibilityLabel:NSLocalizedString(@"Playback status", nil)];
    [_titleLabel setAccessibilityLabel:NSLocalizedString(@"Track title", nil)];
    [_artistLabel setAccessibilityLabel:NSLocalizedString(@"Artist", nil)];
    for (NSTextField *label in @[_statusLabel, _titleLabel, _artistLabel]) {
        [label setTranslatesAutoresizingMaskIntoConstraints:NO];
        [label setAlignment:NSTextAlignmentCenter];
        [label setLineBreakMode:NSLineBreakByTruncatingTail];
        [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_mainView addSubview:label];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_mainView.leadingAnchor constant:16],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_mainView.trailingAnchor constant:-16],
        [_statusLabel.topAnchor constraintEqualToAnchor:_mainView.topAnchor constant:26],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_statusLabel.leadingAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_statusLabel.trailingAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:1],
        [_artistLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_artistLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_artistLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1],
        [_waveformView.topAnchor constraintEqualToAnchor:_artistLabel.bottomAnchor constant:6]
    ]];
}


- (void) _updateAppearance
{
    CurrentTrackAppearance appearance = sGetCurrentTrackAppearance();
    BOOL usesBlush = [[Preferences sharedInstance] themeType] == ThemeTypeBlush;
    BOOL scalesWithWindow = [[Preferences sharedInstance] scalesInterfaceWithWindow];
    BOOL pinToBottom = sGetCurrentTrackPinning() && !scalesWithWindow;

    NSWindow *window = [self window];

    if (appearance == CurrentTrackAppearanceDefault) {
        if (IsAppearanceDarkAqua(nil)) {
            appearance = CurrentTrackAppearanceDark;
        } else {
            appearance = CurrentTrackAppearanceLight;
        }
    }

    NSColor *secondaryLabelColor = [NSColor secondaryLabelColor];
    NSColor *tertiaryLabelColor  = [NSColor tertiaryLabelColor];

    [InterfaceAppearance setTextColor:secondaryLabelColor forField:self.leftLabel];
    [InterfaceAppearance setTextColor:secondaryLabelColor forField:self.rightLabel];
    [InterfaceAppearance setTextColor:secondaryLabelColor forField:self.noTrackLabel];
    [InterfaceAppearance setTextColor:secondaryLabelColor forField:self.statusLabel];
    [InterfaceAppearance setTextColor:[NSColor labelColor] forField:self.titleLabel];
    [InterfaceAppearance setTextColor:secondaryLabelColor forField:self.artistLabel];

    self.mainView.wantsLayer = YES;
    self.mainView.layer.backgroundColor = usesBlush
        ? [InterfaceAppearance blushCurrentTrackColor].CGColor
        : nil;

    if (appearance == CurrentTrackAppearanceLight) {
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantLight]];

        [[self effectView] setState:NSVisualEffectStateActive];

        [[self waveformView] setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantLight]];
        [[self waveformView] setActiveWaveformColor:secondaryLabelColor];
        [[self waveformView] setInactiveWaveformColor:tertiaryLabelColor];
    
    } else if (appearance == CurrentTrackAppearanceDark) {
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];

        [[self effectView] setState:NSVisualEffectStateActive];

        [[self waveformView] setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];

        [[self waveformView] setActiveWaveformColor:  [NSColor colorWithCalibratedWhite:0.6  alpha:1.0]];
        [[self waveformView] setInactiveWaveformColor:[NSColor colorWithCalibratedWhite:0.25 alpha:1.0]];
    }
    
    [[window standardWindowButton:NSWindowCloseButton] setHidden:pinToBottom];
    [[window standardWindowButton:NSWindowZoomButton] setHidden:pinToBottom];
    [window setStyleMask:([window styleMask] | NSWindowStyleMaskResizable)];

    if (pinToBottom) {
        [window setHasShadow:NO];
        [window setMovable:NO];
        [window setMovableByWindowBackground:NO];
        [window setLevel:NSMainMenuWindowLevel];

        [window setCollectionBehavior:(
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorTransient |
            NSWindowCollectionBehaviorIgnoresCycle |
            NSWindowCollectionBehaviorFullScreenAuxiliary
        )];

    } else {
        [window setHasShadow:YES];
        [window setMovable:YES];
        [window setMovableByWindowBackground:YES];
        [window setCollectionBehavior:NSWindowCollectionBehaviorDefault];
        
        BOOL floatsOnTop = [[Preferences sharedInstance] floatsOnTop];
        [window setLevel:(floatsOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel)];
    }

    [[self waveformView] redisplay];
}


- (void) _updateWindowFrame
{
    if (!sGetCurrentTrackPinning() || [[Preferences sharedInstance] scalesInterfaceWithWindow]) return;

    NSRect oldFrame = [[self window] frame];
    
    NSScreen *screen = [NSScreen mainScreen];
    
    NSRect visibleFrame = [screen visibleFrame];
    NSRect frame        = [screen frame];

    // Dock on left
    if (visibleFrame.origin.x > frame.origin.x) {
        if (visibleFrame.origin.x < 10) {
            visibleFrame.size.width += visibleFrame.origin.x;
            visibleFrame.origin.x = 0;

        } else {
            visibleFrame.origin.x   -= 1.0;
            visibleFrame.size.width += 1.0;
        }

    // Dock on right
    } else if (visibleFrame.size.width < frame.size.width) {
        CGFloat dockWidth = frame.size.width - visibleFrame.size.width;
        
        if (dockWidth < 10) {
            visibleFrame.size.width += dockWidth;
        }
        
    // Dock on bottom
    } else {
        if (visibleFrame.origin.y  < 10) {
            visibleFrame.origin.y = 0;
        }
    }

    NSRect newFrame = visibleFrame;
    
    newFrame.size.height = oldFrame.size.height;
    
    [[self window] setFrame:newFrame display:NO];
}


- (void) windowDidResize:(NSNotification *)notification
{
    [self _updateWindowFrame];
}


- (void) windowDidLoad
{
    [super windowDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleNSApplicationDidChangeScreenParameters:) name:NSApplicationDidChangeScreenParametersNotification object:nil];

    NSWindow *window = [self window];

    [window setDelegate:self];
    [window setTitle:NSLocalizedString(@"Current Track", nil)];
    [window setFrameAutosaveName:@"CurrentTrackWindow"];

    [window setTitleVisibility:NSWindowTitleHidden];
    [window setTitlebarAppearsTransparent:YES];

    [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];

    [[self mainView] setFrame:[[self effectView] bounds]];
    [[self mainView] setAutoresizingMask:NSViewHeightSizable|NSViewWidthSizable];
    [[self effectView] addSubview:[self mainView]];
    [self _buildMetadataLabels];
    
    if (![window setFrameUsingName:@"CurrentTrackWindow"]) {
        NSScreen *screen = [[NSScreen screens] firstObject];
        
        NSRect screenFrame = [screen visibleFrame];

        NSRect windowFrame = NSMakeRect(0, screenFrame.origin.y, 520, 144);
        windowFrame.origin.x = round((screenFrame.size.width - windowFrame.size.width) / 2);
        windowFrame.origin.x += screenFrame.origin.x;
    
        [window setFrame:windowFrame display:NO];
    }
    NSRect frame = [window frame];
    frame.size.height = MAX(144, frame.size.height);
    [window setFrame:frame display:NO];
    
    NSFont *monoFont = [NSFont monospacedDigitSystemFontOfSize:24.0 weight:NSFontWeightLight];

    [[self leftLabel]  setFont:monoFont];
    [[self rightLabel] setFont:monoFont];
    [[self noTrackLabel] setFont:[NSFont systemFontOfSize:24.0 weight:NSFontWeightLight]];

    Player *player = [Player sharedInstance];
    [self setPlayer:[Player sharedInstance]];

    [player addObserver:self forKeyPath:@"currentTrack" options:0 context:NULL];
    
    [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:NULL];

    [self _updateTrack];
    
    [[Player sharedInstance] addListener:self];

    [self _updateTrack];

    [[self window] setExcludedFromWindowsMenu:YES];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handlePreferencesDidChange:) name:PreferencesDidChangeNotification object:nil];

    // A restored screen-wide strip must not become the minimum resize width.
    [InterfaceAppearance installInWindow:window designSize:NSMakeSize(520, 144)];
    [InterfaceAppearance setAllowsIndependentResizeAxes:YES inWindow:window];
    [InterfaceAppearance setBorderIdentifier:WindowBorderCurrentTrack inWindow:window];
    [self _updateAppearance];
}


- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
    NSString *actionString = NSStringFromSelector([menuItem action]);

    if ([actionString isEqualToString:@"changeAppearance:"]) {
        NSInteger tag = [menuItem tag];
        
        if (sGetCurrentTrackAppearance() == tag) {
            [menuItem setState:NSControlStateValueOn];
        } else {
            [menuItem setState:NSControlStateValueOff];
        }
    
        return YES;

    } else if ([actionString isEqualToString:@"changePinning:"]) {
        [menuItem setState:sGetCurrentTrackPinning() ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    }
    
    return NO;
}


- (void) showWindow:(id)sender
{
    [self _updateWindowFrame];
    [super showWindow:sender];
}


- (IBAction) changeAppearance:(id)sender
{
    sSetCurrentTrackAppearance([sender tag]);
    [self _updateAppearance];
}


- (IBAction) changePinning:(id)sender
{
    sSetCurrentTrackPinning([sender state] == NSControlStateValueOff);
    [self _updateAppearance];
    [self _updateWindowFrame];
}


- (void) _handlePreferencesDidChange:(NSNotification *)note
{
    [self _updateAppearance];
}


- (void) _handleNSApplicationDidChangeScreenParameters:(NSNotification *)note
{
    [self _updateWindowFrame];
}


- (void) player:(Player *)player didUpdatePlaying:(BOOL)playing { }
- (void) player:(Player *)player didUpdateIssue:(PlayerIssue)issue { }
- (void) player:(Player *)player didUpdateVolume:(double)volume { }
- (void) player:(Player *)player didInterruptPlaybackWithReason:(PlayerInterruptionReason)reason { }
- (void) player:(Player *)player didFinishTrack:(Track *)finishedTrack
{
    _lastFinishedTrack = finishedTrack.trackStatus == TrackStatusPlayed ? finishedTrack : nil;
    [self _updateTrack];
}

- (void) playerDidTick:(Player *)player
{
    [[self waveformView] setPercentage:[player percentage]];
}


@end
