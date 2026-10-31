// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "EditEffectController.h"
#import "Effect.h"
#import "EffectAdditions.h"
#import "EQStateButton.h"
#import "ParametricEQAudioUnit.h"


@interface EditEffectController () <NSMenuItemValidation>
@end

static NSString *sEQPresetName(EQPresetSlot slot)
{
    return slot == EQPresetSlotViolin ? NSLocalizedString(@"Violin", nil) : NSLocalizedString(@"Singer", nil);
}

static NSImage *sEQPresetImage(EQPresetSlot slot)
{
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] setFill];
        [[NSColor blackColor] setStroke];
        if (slot == EQPresetSlotSinger) {
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6, 10, 6, 7)] fill];
            NSBezierPath *shoulders = [NSBezierPath bezierPath];
            [shoulders moveToPoint:NSMakePoint(2, 1)];
            [shoulders curveToPoint:NSMakePoint(16, 1) controlPoint1:NSMakePoint(2, 12) controlPoint2:NSMakePoint(16, 12)];
            [shoulders closePath];
            [shoulders fill];
        } else {
            NSBezierPath *body = [NSBezierPath bezierPath];
            [body moveToPoint:NSMakePoint(7, 1)];
            [body curveToPoint:NSMakePoint(4, 7) controlPoint1:NSMakePoint(0, 1) controlPoint2:NSMakePoint(2, 5)];
            [body curveToPoint:NSMakePoint(5, 11) controlPoint1:NSMakePoint(6, 8) controlPoint2:NSMakePoint(2, 11)];
            [body curveToPoint:NSMakePoint(10, 11) controlPoint1:NSMakePoint(6, 13) controlPoint2:NSMakePoint(9, 13)];
            [body curveToPoint:NSMakePoint(11, 7) controlPoint1:NSMakePoint(13, 11) controlPoint2:NSMakePoint(9, 8)];
            [body curveToPoint:NSMakePoint(7, 1) controlPoint1:NSMakePoint(14, 5) controlPoint2:NSMakePoint(14, 1)];
            [body fill];
            NSRectFill(NSMakeRect(6.5, 10, 2, 7));
            NSRectFill(NSMakeRect(5, 15, 5, 1));
            NSBezierPath *bow = [NSBezierPath bezierPath];
            [bow moveToPoint:NSMakePoint(14, 1)];
            [bow lineToPoint:NSMakePoint(17, 17)];
            [bow setLineWidth:1.2];
            [bow stroke];
        }
        return YES;
    }];
    [image setTemplate:YES];
    [image setAccessibilityDescription:sEQPresetName(slot)];
    return image;
}


@implementation EditEffectController {
    NSInteger _index;
    NSArray<NSButton *> *_EQPresetButtons;
    NSButton *_EQFlatButton;
    AUParameterTree *_EQParameterTree;
    AUParameterObserverToken _EQParameterObserver;
}


- (id) initWithEffect:(Effect *)effect index:(NSInteger)index
{
    if ((self = [super init])) {
        _effect = effect;
        _index = index;
    }
    
    return self;
}


- (void) dealloc
{
    if (_EQParameterObserver) [_EQParameterTree removeParameterObserver:_EQParameterObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    @try {
        [[self effect] removeObserver:self forKeyPath:@"bypass"];
    } @finally { }
}


- (void) windowDidLoad
{
    NSString *autosaveName = [NSString stringWithFormat:@"%@-%ld", [[_effect type] fullName], (long)_index];
    [[self window] setFrameAutosaveName:autosaveName];
    [[self window] setFrameUsingName:autosaveName];

    [self _updateTitle];

    [[self effect] addObserver:self forKeyPath:@"bypass" options:0 context:NULL];
}


- (void) moveToolbarControlsIntoContentView
{
    NSWindow *window = [self window];
    NSMutableArray<NSView *> *controls = [NSMutableArray array];
    for (NSToolbarItem *item in [[window toolbar] items]) {
        if ([item view]) [controls addObject:[item view]];
    }
    if ([_effect supportsEQPresetSlots]) [self _addEQPresetControls:controls];
    [window setToolbar:nil];
    NSView *content = [window contentView];
    CGFloat right = NSWidth([content bounds]) - 8;
    for (NSView *view in [controls reverseObjectEnumerator]) {
        [view removeFromSuperview];
        if ([view isKindOfClass:[NSPopUpButton class]]) {
            NSPopUpButton *button = (NSPopUpButton *)view;
            [button setTitle:NSLocalizedString(@"Actions", nil)];
            [button setImagePosition:NSImageLeft];
            [button setAccessibilityLabel:NSLocalizedString(@"Effect actions", nil)];
            [button sizeToFit];
        }
        NSSize size = [view fittingSize];
        size.width = MAX(size.width, [view frame].size.width);
        size.height = 28;
        right -= size.width;
        [view setTranslatesAutoresizingMaskIntoConstraints:YES];
        [view setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
        [view setFrame:NSMakeRect(right, NSHeight([content bounds]) - 32, size.width, size.height)];
        [content addSubview:view];
        right -= 6;
    }
}


- (NSMenu *) _EQPresetMenuForSlot:(EQPresetSlot)slot
{
    NSMenu *menu = [NSMenu new];
    for (NSString *selector in @[@"recallEQPreset:", @"saveEQPreset:"]) {
        NSMenuItem *item = [menu addItemWithTitle:@"" action:NSSelectorFromString(selector) keyEquivalent:@""];
        item.target = self;
        item.tag = slot;
        [self validateMenuItem:item];
    }
    return menu;
}


- (void) _addEQPresetControls:(NSMutableArray<NSView *> *)controls
{
    NSButton *flat = nil;
    NSPopUpButton *actions = nil;
    SEL flatten = NSSelectorFromString(@"flatten:");
    for (NSView *view in controls) {
        if ([view isKindOfClass:[NSPopUpButton class]]) actions = (NSPopUpButton *)view;
        else if ([view isKindOfClass:[NSButton class]] && [(NSButton *)view action] == flatten) flat = (NSButton *)view;
    }
    if (!flat) {
        flat = [NSButton buttonWithTitle:NSLocalizedString(@"Flat", nil) target:self action:flatten];
        flat.bezelStyle = NSBezelStyleTexturedRounded;
        [controls insertObject:flat atIndex:0];
    }
    EQStateButton *styledFlat = [[EQStateButton alloc] initWithFrame:flat.frame];
    styledFlat.title = flat.title;
    styledFlat.font = flat.font;
    styledFlat.target = flat.target ?: self;
    styledFlat.action = flatten;
    styledFlat.bezelStyle = flat.bezelStyle;
    styledFlat.buttonType = NSButtonTypePushOnPushOff;
    [controls replaceObjectAtIndex:[controls indexOfObject:flat] withObject:styledFlat];
    flat = styledFlat;
    _EQFlatButton = flat;
    flat.accessibilityLabel = NSLocalizedString(@"Flat EQ", nil);
    flat.toolTip = [[_effect.type name] isEqualToString:EmbraceEffectParametricEQ]
        ? NSLocalizedString(@"Set all gains and output trim to 0 dB and turn low-cut off.", nil)
        : NSLocalizedString(@"Set EQ gains to 0 dB.", nil);
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    [actions.menu addItem:[NSMenuItem separatorItem]];
    for (NSNumber *number in @[@(EQPresetSlotViolin), @(EQPresetSlotSinger)]) {
        EQPresetSlot slot = number.integerValue;
        EQStateButton *button = [[EQStateButton alloc] initWithFrame:NSMakeRect(0, 0, 38, 28)];
        button.image = sEQPresetImage(slot);
        button.imagePosition = NSImageOnly;
        button.buttonType = NSButtonTypePushOnPushOff;
        button.target = self;
        button.action = @selector(recallEQPreset:);
        button.bezelStyle = NSBezelStyleTexturedRounded;
        button.tag = slot;
        button.menu = [self _EQPresetMenuForSlot:slot];
        button.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"%@ EQ preset", nil), sEQPresetName(slot)];
        [buttons addObject:button];
        NSMenuItem *save = [actions.menu addItemWithTitle:@"" action:@selector(saveEQPreset:) keyEquivalent:@""];
        save.target = self;
        save.tag = slot;
        [self validateMenuItem:save];
    }
    _EQPresetButtons = buttons;
    [controls insertObjects:buttons atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange([controls indexOfObject:flat], buttons.count)]];
    _EQParameterTree = _effect.audioUnit.parameterTree;
    __weak EditEffectController *weakSelf = self;
    _EQParameterObserver = [_EQParameterTree tokenByAddingParameterObserver:^(AUParameterAddress address, AUValue value) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf _updateEQPresetButtons]; });
    }];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_EQPresetDidChange:) name:EffectEQPresetDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_EQPresetDidChange:)
        name:EmbraceParametricEQAutomaticFlatDidChangeNotification object:_effect.audioUnit];
    [self _updateEQPresetButtons];
}


- (void) _EQPresetDidChange:(NSNotification *)note
{
    [self _updateEQPresetButtons];
}


- (void) _updateEQPresetButtons
{
    BOOL enabled = !_effect.bypass;
    BOOL automaticFlat = EmbraceParametricEQHasAutomaticFlatResponse(_effect.audioUnit);
    _EQFlatButton.state = enabled && [_effect hasFlatEQResponse] ? NSControlStateValueOn : NSControlStateValueOff;
    _EQFlatButton.needsDisplay = YES;
    for (NSButton *button in _EQPresetButtons) {
        button.state = enabled && !automaticFlat && [_effect matchesEQPresetInSlot:button.tag]
            ? NSControlStateValueOn : NSControlStateValueOff;
        button.needsDisplay = YES;
        BOOL saved = [_effect hasEQPresetInSlot:button.tag];
        NSString *format = saved
            ? NSLocalizedString(@"Recall %@ preset. Right-click to replace it with current EQ settings. Also available in Actions.", nil)
            : NSLocalizedString(@"No %@ preset saved. Click to save current EQ settings. You can first load a preset from Actions.", nil);
        button.toolTip = [NSString stringWithFormat:format, sEQPresetName(button.tag)];
        button.accessibilityHelp = button.toolTip;
    }
}


- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
    if ([menuItem action] == @selector(saveEQPreset:)) {
        NSString *format = [_effect hasEQPresetInSlot:menuItem.tag]
            ? NSLocalizedString(@"Replace %@ preset with current EQ", nil)
            : NSLocalizedString(@"Save current EQ as %@ preset", nil);
        menuItem.title = [NSString stringWithFormat:format, sEQPresetName(menuItem.tag)];
        return [_effect supportsEQPresetSlots] && [_effect audioUnit] != nil;
    }
    if ([menuItem action] == @selector(recallEQPreset:)) {
        menuItem.title = [NSString stringWithFormat:NSLocalizedString(@"Use %@ preset", nil), sEQPresetName(menuItem.tag)];
        return [_effect hasEQPresetInSlot:menuItem.tag];
    }
    if ([menuItem action] == @selector(toggleBypass:)) {
        [menuItem setState:[[self effect] bypass] ? NSControlStateValueOn : NSControlStateValueOff];
    }

    return YES;
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == [self effect]) {
        if ([keyPath isEqualToString:@"bypass"]) {
            [self _updateTitle];
            [self _updateEQPresetButtons];
        }
    }
}


- (void) _updateTitle
{
    NSString *name = [[_effect type] friendlyName];
    if (!name) name = NSLocalizedString(@"Effect", nil);

    if ([[self effect] bypass]) {
        NSString *bypassString = NSLocalizedString(@"(Bypassed)", nil);
        name = [NSString stringWithFormat:@"%@ %@", name, bypassString];
    }

    [[self window] setTitle:name];
}


- (NSURL *) _urlForPresetDirectory
{
    NSString *allPresets = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    allPresets = [allPresets stringByAppendingPathComponent:@"Audio"];
    allPresets = [allPresets stringByAppendingPathComponent:@"Presets"];

    NSString *manufacturer = [[_effect type] manufacturer];
    NSString *name = [[_effect type] name];

    NSString *unitPresets = nil;
    
    if (name && manufacturer) {
        unitPresets = [allPresets stringByAppendingPathComponent:manufacturer];
        unitPresets = [unitPresets stringByAppendingPathComponent:name];
    }

    BOOL allExists = NO,      unitExists = NO;
    BOOL allIsDirectory = NO, unitIsDirectory = NO;
    
    allExists  = [[NSFileManager defaultManager] fileExistsAtPath:allPresets  isDirectory:&allIsDirectory];
    unitExists = [[NSFileManager defaultManager] fileExistsAtPath:unitPresets isDirectory:&unitIsDirectory];

    NSURL *result = nil;

    if (unitExists && unitIsDirectory) {
        result = [NSURL fileURLWithPath:unitPresets];
    } else if (allExists && allIsDirectory) {
        result = [NSURL fileURLWithPath:allPresets];
    }

    return result;
}


#pragma mark - IBActions

- (IBAction) recallEQPreset:(id)sender
{
    EQPresetSlot slot = [sender tag];
    if (![_effect hasEQPresetInSlot:slot]) {
        NSView *view = [sender isKindOfClass:[NSView class]] ? sender : _EQPresetButtons.firstObject;
        [[self _EQPresetMenuForSlot:slot] popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSMaxY(view.bounds)) inView:view];
        return;
    }
    EmbraceParametricEQSetAutomaticFlatResponse(_effect.audioUnit, NO);
    if ([_effect loadEQPresetInSlot:slot]) [self reloadData];
    else NSBeep();
    [self _updateEQPresetButtons];
}


- (IBAction) saveEQPreset:(id)sender
{
    if (![_effect saveEQPresetInSlot:[sender tag]]) NSBeep();
    [self _updateEQPresetButtons];
}


- (IBAction) loadPreset:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    [openPanel setTitle:NSLocalizedString(@"Load Preset", nil)];
    
    NSURL *url = [self _urlForPresetDirectory];
    [openPanel setDirectoryURL:url];

    __weak id weakSelf = self;
    __weak Effect *weakEffect = _effect;

    [openPanel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK) {
            EmbraceParametricEQSetAutomaticFlatResponse([weakEffect audioUnit], NO);
            [weakEffect loadAudioPresetAtFileURL:[openPanel URL]];
            [weakSelf reloadData];
        }
    }];
}


- (IBAction) savePreset:(id)sender
{
    NSSavePanel *savePanel = [NSSavePanel savePanel];

    [savePanel setTitle:NSLocalizedString(@"Save Preset", nil)];

    NSURL *url = [self _urlForPresetDirectory];
    [savePanel setDirectoryURL:url];
    [savePanel setAllowedFileTypes:@[ @"aupreset" ]];
    [savePanel setNameFieldStringValue:NSLocalizedString(@"Preset", nil)];

    __weak id weakEffect = _effect;

    [savePanel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK) {
            [weakEffect saveAudioPresetAtFileURL:[savePanel URL]];
        }
    }];
}


- (IBAction) restoreDefaultValues:(id)sender
{
    EmbraceParametricEQSetAutomaticFlatResponse(_effect.audioUnit, NO);
    [[self effect] restoreDefaultValues];
    [self reloadData];
}


- (IBAction) toggleBypass:(id)sender
{
    BOOL bypass = [[self effect] bypass];
    [[self effect] setBypass:!bypass];
}


- (void) reloadData
{
    [self _updateEQPresetButtons];
}


@end
