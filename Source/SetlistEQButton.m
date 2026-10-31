#import "SetlistEQButton.h"
#import "AppDelegate.h"
#import "EditEffectController.h"
#import "Effect.h"
#import "EffectAdditions.h"
#import "InterfaceAppearance.h"
#import "Player.h"
#import "Preferences.h"

@implementation SetlistEQButton {
    Player *_player;
}

+ (instancetype) buttonUnderMenu:(NSButton *)menu besideSummary:(NSTextField *)summary player:(Player *)player
{
    NSRect frame = menu.frame;
    frame.size.height = 18;
    frame.origin.y = NSMidY(summary.frame) - frame.size.height / 2;
    SetlistEQButton *button = [[self alloc] initWithFrame:frame player:player];
    NSRect summaryFrame = summary.frame;
    summaryFrame.size.width = MAX(0, NSMinX(frame) - 6 - NSMinX(summaryFrame));
    summary.frame = summaryFrame;
    return button;
}

- (instancetype) initWithFrame:(NSRect)frame player:(Player *)player
{
    if ((self = [super initWithFrame:frame])) {
        _player = player;
        self.title = @"EQ";
        self.buttonType = NSButtonTypePushOnPushOff;
        self.bezelStyle = NSBezelStyleRounded;
        self.controlSize = NSControlSizeMini;
        [InterfaceAppearance setFont:[NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold] forControl:self];
        self.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
        self.target = self;
        self.action = @selector(_toggleEQ:);
        self.accessibilityLabel = NSLocalizedString(@"Equalizer", nil);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(_refresh:) name:PlayerEffectsDidChangeNotification object:player];
        [center addObserver:self selector:@selector(_refresh:) name:EffectBypassDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(_refresh:) name:PreferencesDidChangeNotification object:Preferences.sharedInstance];
        [self _refresh:nil];
    }
    return self;
}

- (void) dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void) _refresh:(NSNotification *)notification
{
    BOOL enabled = EmbraceParametricEQIsEnabled(_player.effects);
    self.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.needsDisplay = YES;
    self.toolTip = enabled ? @"Parametric EQ on. Click to bypass and open its panel."
                           : @"Parametric EQ off. Click to enable and open its panel.";
}

- (void) _toggleEQ:(id)sender
{
    Player *player = _player;
    BOOL success = [player setEqualizerEnabled:!EmbraceParametricEQIsEnabled(player.effects)
                                          type:EqualizerTypeParametric];
    if (!success) NSBeep();
    [self _refresh:nil];
    if (!success) return;
    for (Effect *effect in player.effects) {
        if ([effect.type.name isEqualToString:EmbraceEffectParametricEQ] && effect.audioUnit) {
            [[GetAppDelegate() editControllerForEffect:effect] showWindow:self];
            break;
        }
    }
}

@end
