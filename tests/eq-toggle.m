#import <Cocoa/Cocoa.h>
#import "SetlistEQButton.h"
#import "EQStateButton.h"
#import "Effect.h"
#import "EffectAdditions.h"
#import "ParametricEQAudioUnit.h"
#import "ParametricEQView.h"
#import "Player.h"
#import "Preferences.h"
#import "InterfaceAppearance.h"
#import "HugAudioDevice.h"
#import "AppDelegate.h"
#import "EditEffectController.h"

@interface EditEffectController (PresetTests)
- (void) _addEQPresetControls:(NSMutableArray<NSView *> *)controls;
@end

@interface PresetTestController : EditEffectController
@property ParametricEQView *editor;
@end
@implementation PresetTestController
- (void) reloadData { [super reloadData]; [self.editor reloadData]; }
- (void) flatten:(id)sender { [self.editor flatten]; [super reloadData]; }
@end

@interface EQPanelTestController : NSWindowController
@property NSUInteger presentations;
@end
@implementation EQPanelTestController
- (void) showWindow:(id)sender { self.presentations++; }
@end

@interface EQPanelTestDelegate : NSObject <NSApplicationDelegate>
@property EQPanelTestController *controller;
@property Effect *editedEffect;
@end
@implementation EQPanelTestDelegate
- (NSWindowController *) editControllerForEffect:(Effect *)effect
{
    self.editedEffect = effect;
    return self.controller;
}
@end
AppDelegate *GetAppDelegate(void) { return (AppDelegate *)NSApp.delegate; }

// Exercise production controls and real Audio Units without hardware output.
NSString * const PlayerEffectsDidChangeNotification = @"PlayerEffectsDidChange";
NSString *GetAppBuildString(void) { return @"1261"; }
NSUInteger GetCombinedBuildNumber(NSString *s) { return s.integerValue; }
static NSUInteger assignments, saves, checks;
static NSArray *savedEffects;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-property-implementation"
@implementation Player
@synthesize effects = _effects;
+ (instancetype) sharedInstance { static Player *p; if (!p) p = [Player new]; return p; }
- (void) setEffects:(NSArray *)effects
{
    assignments++;
    _effects = effects;
    [self saveEffectState];
    [NSNotificationCenter.defaultCenter postNotificationName:PlayerEffectsDidChangeNotification object:self];
}
- (void) saveEffectState
{
    saves++;
    NSMutableArray *states = [NSMutableArray new];
    for (Effect *effect in self.effects) [states addObject:effect.stateDictionary];
    savedEffects = states;
}
- (BOOL) setParametricEQEnabled:(BOOL)enabled
{
    return [self setEqualizerEnabled:enabled type:EqualizerTypeParametric];
}
- (BOOL) setEqualizerEnabled:(BOOL)enabled type:(EqualizerType)type
{
    NSArray *updated = EmbraceEffectsBySettingEqualizerEnabled(self.effects, type, enabled);
    if (!updated) return NO;
    if (updated != self.effects) self.effects = updated;
    else [self saveEffectState];
    return YES;
}
@end
@implementation HugAudioDevice
+ (instancetype) placeholderDevice { return [self new]; }
+ (instancetype) bestDefaultDevice { return [self new]; }
+ (instancetype) archivedDeviceWithDeviceUID:(NSString *)uid name:(NSString *)name { return [self new]; }
- (NSString *) deviceUID { return @"eq-toggle-device"; }
- (NSString *) name { return @"EQ toggle test device"; }
@end
#pragma clang diagnostic pop

static void Check(BOOL value, NSString *message)
{
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static Effect *NewEffect(NSString *name)
{
    for (EffectType *type in EffectType.allEffectTypes) if ([type.name isEqualToString:name]) return [Effect effectWithEffectType:type];
    return nil;
}
static NSArray *Parameters(Effect *effect)
{
    NSMutableArray *values = [NSMutableArray new];
    for (AUParameter *parameter in effect.audioUnit.parameterTree.allParameters) [values addObject:@(parameter.value)];
    return values;
}

static void TestLinkedButtons(void)
{
    Effect *effect = NewEffect(EmbraceEffectParametricEQ);
    Player *player = Player.sharedInstance;
    player.effects = @[effect];
    [effect.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain].value = -7;
    NSArray *values = Parameters(effect);
    ParametricEQView *view = [[ParametricEQView alloc] initWithAudioUnit:effect.audioUnit];
    view.setEQEnabled = ^(BOOL enabled) { [Player.sharedInstance setParametricEQEnabled:enabled]; };
    NSButton *editor = [view valueForKey:@"statusButton"];
    SetlistEQButton *playlist = [[SetlistEQButton alloc] initWithFrame:NSMakeRect(0, 0, 42, 18) player:player];
    NSUInteger previousAssignments = assignments, previousSaves = saves;
    for (NSUInteger i = 0; i < 10; i++) {
        [(i % 2 ? playlist : editor) performClick:nil];
        NSControlStateValue expected = i % 2 ? NSControlStateValueOn : NSControlStateValueOff;
        Check(playlist.state == expected && editor.state == expected && effect.bypass == (expected == NSControlStateValueOff), @"Both buttons follow the real unit after alternating clicks");
    }
    Check(assignments == previousAssignments && [Parameters(effect) isEqual:values], @"Linked toggles preserve parameters without assigning the effect chain");
    Check(saves == previousSaves + 10, @"Every linked toggle saves the current state once");
    effect.bypass = YES;
    Check(playlist.state == NSControlStateValueOff && editor.state == NSControlStateValueOff, @"Actions bypass synchronizes both controls");
    effect.bypass = NO;
    Check(playlist.state == NSControlStateValueOn && editor.state == NSControlStateValueOn, @"Actions enable synchronizes both controls");
}

static NSBitmapImageRep *RenderView(NSView *view)
{
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:NSWidth(view.bounds) * 2 pixelsHigh:NSHeight(view.bounds) * 2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = view.bounds.size;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    NSRectFillUsingOperation(view.bounds, NSCompositingOperationClear);
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{ [view drawRect:view.bounds]; }];
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

static BOOL IsBlue(NSColor *color)
{
    return color.alphaComponent > .5 && color.redComponent < .5 && color.blueComponent > color.redComponent + .2 && color.blueComponent > color.greenComponent + .1;
}

static void TestCurvePreview(void)
{
    Effect *effect = NewEffect(EmbraceEffectParametricEQ);
    [effect.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain].value = -12;
    [effect.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterHFGain].value = -18;
    ParametricEQView *view = [[ParametricEQView alloc] initWithAudioUnit:effect.audioUnit];
    NSView *curve = [view valueForKey:@"curveView"];
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        curve.appearance = [NSAppearance appearanceNamed:appearance];
        effect.bypass = NO;
        NSBitmapImageRep *on = RenderView(curve);
        effect.bypass = YES;
        NSBitmapImageRep *off = RenderView(curve);
        NSUInteger onBlue = 0, offBlue = 0, sameCurveGray = 0;
        NSInteger minY = on.pixelsHigh, maxY = 0;
        for (NSInteger y = 3; y < on.pixelsHigh - 3; y++) {
            for (NSInteger x = 3; x < on.pixelsWide - 3; x++) {
                NSColor *a = [[on colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                NSColor *b = [[off colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                if (IsBlue(b)) offBlue++;
                if (!IsBlue(a)) continue;
                onBlue++;
                minY = MIN(minY, y); maxY = MAX(maxY, y);
                BOOL neutral = fabs(b.redComponent - b.greenComponent) < .04 && fabs(b.greenComponent - b.blueComponent) < .04;
                BOOL visible = [appearance isEqual:NSAppearanceNameAqua] ? b.redComponent < .8 : b.redComponent > .35;
                if (neutral && visible) sameCurveGray++;
            }
        }
        printf("Curve check %s: %lu on blue, %lu off blue, %lu retained gray, span %ld\n", appearance.UTF8String, onBlue, offBlue, sameCurveGray, (long)(maxY-minY));
        Check(onBlue > 100 && maxY - minY > 20, @"Enabled curve is blue and nonflat");
        Check(offBlue == 0 && sameCurveGray > onBlue * .75, @"Bypassed curve keeps the same shape in gray");
        const char *directory = getenv("EZ_EMBRACE_EQ_RENDER_DIR");
        if (directory) {
            for (NSString *state in @[@"on", @"off"]) {
                NSString *name = [NSString stringWithFormat:@"curve-%@-%@.png", appearance, state];
                NSString *path = [[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:name];
                [[([state isEqual:@"on"] ? on : off) representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
            }
        }
    }
}

static void WaitForPresetState(NSButton *button, NSControlStateValue expected)
{
    // AU parameter observers throttle notifications. Wait for the expected
    // result instead of assuming every update arrives within 120 ms.
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 1;
    while (button.state != expected && CFAbsoluteTimeGetCurrent() < deadline) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, .02, false);
    }
}

static void TestPresetControls(void)
{
    Effect *effect = NewEffect(EmbraceEffectParametricEQ);
    PresetTestController *controller = [[PresetTestController alloc] initWithEffect:effect index:0];
    controller.editor = [[ParametricEQView alloc] initWithAudioUnit:effect.audioUnit];
    controller.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 776, 357) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    [controller windowDidLoad];
    NSButton *flat = [NSButton buttonWithTitle:@"Flat" target:controller action:@selector(flatten:)];
    NSPopUpButton *actions = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,100,28) pullsDown:YES];
    NSMutableArray *controls = [@[flat, actions] mutableCopy];
    [controller _addEQPresetControls:controls];
    NSArray<NSButton *> *presets = [controller valueForKey:@"EQPresetButtons"];
    flat = [controller valueForKey:@"EQFlatButton"];
    NSButton *violin = presets[0], *singer = presets[1];
    Check([flat isKindOfClass:EQStateButton.class] && [violin isKindOfClass:EQStateButton.class] && [singer isKindOfClass:EQStateButton.class], @"All preset controls share state-driven gray and blue drawing");
    [violin performClick:nil];
    Check(violin.state == NSControlStateValueOn && singer.state == NSControlStateValueOff && flat.state == NSControlStateValueOff, @"Violin recall highlights only matching enabled settings");
    effect.bypass = YES;
    Check(violin.state == NSControlStateValueOff && singer.state == NSControlStateValueOff && flat.state == NSControlStateValueOff, @"Bypass makes every preset button gray immediately");
    [singer performClick:nil];
    Check(effect.bypass && [effect matchesEQPresetInSlot:EQPresetSlotSinger] && singer.state == NSControlStateValueOff, @"Recalling Singer while bypassed prepares settings without enabling EQ");
    effect.bypass = NO;
    Check(singer.state == NSControlStateValueOn && violin.state == NSControlStateValueOff, @"Enabling highlights the prepared Singer settings");
    AUParameter *gain = [effect.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain];
    gain.value = 4;
    WaitForPresetState(singer, NSControlStateValueOff);
    Check(singer.state == NSControlStateValueOff && violin.state == NSControlStateValueOff, @"External parameter edits clear preset highlights");
    [flat performClick:nil];
    WaitForPresetState(flat, NSControlStateValueOn);
    Check(flat.state == NSControlStateValueOn && effect.hasFlatEQResponse, @"Flat reflects a completely flat response");
    AUParameter *slope = [effect.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterFilterSlope];
    slope.value = 1;
    WaitForPresetState(flat, NSControlStateValueOff);
    Check(!effect.hasFlatEQResponse && flat.state == NSControlStateValueOff, @"Low-cut clears Flat even when every gain remains zero");
    [flat performClick:nil];
    Check(slope.value == 0 && effect.hasFlatEQResponse && flat.state == NSControlStateValueOn, @"Flat turns low-cut off and restores its highlight");
    [flat performClick:nil];
    Check(flat.state == NSControlStateValueOn, @"Repeated Flat clicks keep the matching enabled state");
    effect.bypass = YES;
    Check(flat.state == NSControlStateValueOff, @"Flat is gray while bypassed");
    slope.value = 2;
    [flat performClick:nil];
    Check(effect.bypass && slope.value == 0 && flat.state == NSControlStateValueOff, @"Flat while bypassed prepares unity without enabling processing");
    effect.bypass = NO;
    gain.value = -5;
    [controller saveEQPreset:violin];
    Check(violin.state == NSControlStateValueOn && [effect matchesEQPresetInSlot:EQPresetSlotViolin], @"Replacing a preset updates its highlight immediately");
    gain.value = -6;
    WaitForPresetState(violin, NSControlStateValueOff);
    Check(violin.state == NSControlStateValueOff, @"Editing a replaced preset clears its highlight");
    [violin performClick:nil];
    Check(fabs(gain.value + 5) < .001 && violin.state == NSControlStateValueOn, @"Recall loads the replacement and restores its highlight");
    [NSUserDefaults.standardUserDefaults removeObjectForKey:[NSString stringWithFormat:@"EQPresetSlot.%@.1",EmbraceEffectParametricEQ]];
}

@interface EQColorTestWindow : NSWindow
@property BOOL simulatedFocus;
@end
@implementation EQColorTestWindow
- (BOOL) isKeyWindow { return self.simulatedFocus; }
- (BOOL) isMainWindow { return self.simulatedFocus; }
@end

static void TestButtonColors(void)
{
    Effect *effect = NewEffect(EmbraceEffectParametricEQ);
    Player.sharedInstance.effects = @[effect];
    SetlistEQButton *playlist = [[SetlistEQButton alloc] initWithFrame:NSMakeRect(0, 0, 42, 18) player:Player.sharedInstance];
    ParametricEQView *editor = [[ParametricEQView alloc] initWithAudioUnit:effect.audioUnit];
    NSButton *status = [editor valueForKey:@"statusButton"];
    EQStateButton *icon = [[EQStateButton alloc] initWithFrame:NSMakeRect(0, 0, 38, 28)];
    icon.image = [NSImage imageWithSize:NSMakeSize(18,18) flipped:NO drawingHandler:^BOOL(NSRect rect) { [NSColor.blackColor setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect,2,2)] fill]; return YES; }];
    icon.imagePosition = NSImageOnly;
    for (NSButton *button in @[playlist, status, icon]) {
        EQColorTestWindow *window = [[EQColorTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 80, 40) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        [window.contentView addSubview:button];
        Check([button acceptsFirstMouse:nil], @"EQ accepts one click when its window is inactive");
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            button.appearance = [NSAppearance appearanceNamed:appearance];
            for (NSNumber *focus in @[@NO, @YES]) {
                window.simulatedFocus = focus.boolValue;
                for (NSNumber *enabled in @[@NO, @YES]) {
                    effect.bypass = !enabled.boolValue;
                    if (button == icon) button.state = enabled.boolValue ? NSControlStateValueOn : NSControlStateValueOff;
                    for (NSNumber *pressed in @[@NO, @YES]) {
                        [button highlight:pressed.boolValue];
                        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:NSWidth(button.bounds) * 2 pixelsHigh:NSHeight(button.bounds) * 2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                        bitmap.size = button.bounds.size;
                        [NSGraphicsContext saveGraphicsState];
                        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
                        NSRectFillUsingOperation(button.bounds, NSCompositingOperationClear);
                        [button.appearance performAsCurrentDrawingAppearance:^{ [button drawRect:button.bounds]; }];
                        [NSGraphicsContext restoreGraphicsState];
                        NSUInteger blue = 0;
                        for (NSInteger y = 2; y < bitmap.pixelsHigh - 2; y++) {
                            for (NSInteger x = 2; x < bitmap.pixelsWide - 2; x++) {
                                NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                                if (color.alphaComponent > .5 && color.blueComponent > color.redComponent + .2 && color.blueComponent > color.greenComponent + .1) blue++;
                            }
                        }
                        NSString *name = [NSString stringWithFormat:@"%@-%@-focus%d-on%d-pressed%d", button == playlist ? @"playlist" : button == status ? @"editor" : @"icon", appearance, focus.boolValue, enabled.boolValue, pressed.boolValue];
                        const char *directory = getenv("EZ_EMBRACE_EQ_RENDER_DIR");
                        if (directory) {
                            NSString *path = [[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
                            [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
                        }
                        printf("Color check %s: %lu blue pixels\n", name.UTF8String, (unsigned long)blue);
                        Check(enabled.boolValue ? blue > 300 : blue == 0, @"EQ fill follows bypass, independent of focus, appearance and press highlight");
                    }
                }
            }
        }
    }
}

static void TestGeometry(Preferences *preferences)
{
    for (NSNumber *size in @[@100, @125, @150, @175, @200]) {
        for (NSNumber *bold in @[@NO, @YES]) {
            preferences.textSizePercent = size.integerValue;
            preferences.usesBoldText = bold.boolValue;
            preferences.scalesInterfaceWithWindow = NO;
            NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 424) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
            window.contentMinSize = NSMakeSize(240, 240);
            NSButton *menu = [[NSButton alloc] initWithFrame:NSMakeRect(271, 366, 42, 32)];
            NSTextField *summary = [NSTextField labelWithString:@"98 played / 1 queued"];
            summary.frame = NSMakeRect(8, 313, 304, 20);
            NSView *seek = [[NSView alloc] initWithFrame:NSMakeRect(0, 333, 320, 24)];
            [window.contentView addSubview:menu];
            [window.contentView addSubview:summary];
            [window.contentView addSubview:seek];
            NSRect windowBefore = window.frame, menuBefore = menu.frame, seekBefore = seek.frame;
            NSSize minimumBefore = window.contentMinSize;
            SetlistEQButton *button = [SetlistEQButton buttonUnderMenu:menu besideSummary:summary player:Player.sharedInstance];
            [window.contentView addSubview:button];
            Check(NSEqualRects(windowBefore, window.frame) && NSEqualSizes(minimumBefore, window.contentMinSize), @"Adding EQ keeps window and minimum dimensions unchanged");
            Check(NSEqualRects(menuBefore, menu.frame) && NSEqualRects(seekBefore, seek.frame), @"Adding EQ does not move existing controls");
            Check(NSMidX(button.frame) == NSMidX(menu.frame) && NSMaxY(button.frame) < NSMinY(seek.frame), @"EQ is below the menu and clear of the scrubber");
            [InterfaceAppearance installInWindow:window designSize:NSMakeSize(320, 424)];
            for (NSNumber *scales in @[@NO, @YES]) {
                preferences.scalesInterfaceWithWindow = scales.boolValue;
                if (scales.boolValue) [window setContentSize:NSMakeSize(960, 1272)];
                [window.contentView layoutSubtreeIfNeeded];
                NSRect before = window.frame;
                NSSize minimum = window.contentMinSize;
                [button performClick:nil];
                Check(NSEqualRects(before, window.frame) && NSEqualSizes(minimum, window.contentMinSize), @"Toggling EQ never resizes the window at any text, bold or scaling setting");
                NSRect eqRect = [button convertRect:button.bounds toView:nil];
                NSRect summaryRect = [summary convertRect:summary.bounds toView:nil];
                NSRect seekRect = [seek convertRect:seek.bounds toView:nil];
                Check(!NSIntersectsRect(eqRect, summaryRect) && !NSIntersectsRect(eqRect, seekRect), @"Scaled EQ hitbox stays clear of summary and seek bar");
                Check(NSContainsRect(window.contentView.bounds, eqRect), @"EQ remains inside the window at every scale");
            }
        }
    }
}

static void TestParametricAutomaticResize(Preferences *preferences)
{
    preferences.textSizePercent = 100;
    preferences.scalesInterfaceWithWindow = NO;
    Effect *effect = NewEffect(EmbraceEffectParametricEQ);
    ParametricEQView *editor = [[ParametricEQView alloc] initWithAudioUnit:effect.audioUnit];
    NSSize design = editor.bounds.size;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(40, 40, design.width, design.height + 36)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    editor.frame = NSMakeRect(0, 0, design.width, design.height);
    editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [window.contentView addSubview:editor];
    [InterfaceAppearance installInWindow:window];
    [InterfaceAppearance setAllowsIndependentResizeAxes:YES inWindow:window];
    preferences.textSizePercent = 200;
    preferences.scalesInterfaceWithWindow = YES;
    NSRect target = [window frameRectForContentRect:NSMakeRect(100, 100, 430, 310)];
    [InterfaceAppearance applyAutomaticFrame:target toWindow:window];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];

    NSView *document = [InterfaceAppearance contentViewForWindow:window];
    Check(fabs(editor.frame.size.width - document.bounds.size.width) < 1 &&
          fabs(editor.frame.size.height - (document.bounds.size.height - 36)) < 1,
          @"Automatic placement resizes the parametric editor with its window");
    Check(fabs(editor.bounds.size.width - design.width) < 0.1 &&
          fabs(editor.bounds.size.height - design.height) < 0.1,
          @"Parametric controls scale as one complete canvas instead of clipping");
    NSRect drawn = [editor convertRect:editor.bounds toView:window.contentView];
    Check(NSContainsRect(NSInsetRect(window.contentView.bounds, -1, -1), drawn),
          @"Resized parametric EQ content remains fully visible");
    [window orderOut:nil];
    preferences.textSizePercent = 100;
    preferences.scalesInterfaceWithWindow = NO;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        EQPanelTestDelegate *delegate = [EQPanelTestDelegate new];
        delegate.controller = [EQPanelTestController new];
        NSApp.delegate = delegate;
        NSString *domain = NSProcessInfo.processInfo.processName;
        Check([domain isEqualToString:@"eq-toggle-tests"], @"Isolated preferences domain");
        Check([NSBundle.mainBundle.bundleIdentifier isEqualToString:domain], @"Isolated test bundle preferences");
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults removePersistentDomainForName:domain];
        EmbraceRegisterParametricEQAudioUnit();
        [EffectType embrace_registerMappedEffects];
        Preferences *preferences = Preferences.sharedInstance;
        NSArray *freshEffects = [defaults objectForKey:@"effects"];
        Check([freshEffects.firstObject[@"name"] isEqualToString:EmbraceEffectParametricEQ], @"Fresh installs default to the parametric EQ");

        Effect *legacyDefault = NewEffect(EmbraceMappedEffect10BandEQ);
        [defaults setObject:@[legacyDefault.stateDictionary] forKey:@"effects"];
        [defaults setObject:@"1261" forKey:@"last-build"];
        [defaults removeObjectForKey:@"equalizerType"];
        EmbraceMigrateDefaultEqualizer(preferences);
        Check([[[defaults objectForKey:@"effects"] firstObject][@"name"] isEqualToString:EmbraceEffectParametricEQ] &&
              preferences.equalizerType == EqualizerTypeParametric, @"Untouched 4.2.0 graphic default migrates to parametric");

        Effect *customGraphic = NewEffect(EmbraceMappedEffect10BandEQ);
        AUParameter *graphicGain = [customGraphic.audioUnit.parameterTree parameterWithID:0 scope:kAudioUnitScope_Global element:0];
        graphicGain.value = 4;
        NSString *graphicBackupKey = [@"EqualizerSavedState." stringByAppendingString:EmbraceMappedEffect10BandEQ];
        [defaults removeObjectForKey:graphicBackupKey];
        [defaults setObject:@[customGraphic.stateDictionary] forKey:@"effects"];
        [defaults removeObjectForKey:@"equalizerType"];
        EmbraceMigrateDefaultEqualizer(preferences);
        Check([[[defaults objectForKey:@"effects"] firstObject][@"name"] isEqualToString:EmbraceEffectParametricEQ] &&
              preferences.equalizerType == EqualizerTypeParametric, @"Customized graphic EQ migrates to the sole parametric EQ");
        Check([[[defaults objectForKey:graphicBackupKey] objectForKey:@"name"] isEqualToString:EmbraceMappedEffect10BandEQ],
              @"Migration backs up removed graphic EQ state");

        Effect *firstParametric = NewEffect(EmbraceEffectParametricEQ);
        Effect *duplicateParametric = NewEffect(EmbraceEffectParametricEQ);
        [firstParametric.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain].value = -9;
        [duplicateParametric.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain].value = 6;
        [defaults setObject:@[customGraphic.stateDictionary, firstParametric.stateDictionary, duplicateParametric.stateDictionary]
                         forKey:@"effects"];
        EmbraceMigrateDefaultEqualizer(preferences);
        NSArray *migratedStates = [defaults objectForKey:@"effects"];
        Effect *migratedParametric = [Effect effectWithStateDictionary:migratedStates.firstObject];
        Check(migratedStates.count == 1 &&
              [migratedParametric.type.name isEqualToString:EmbraceEffectParametricEQ] &&
              fabs([migratedParametric.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain].value + 9) < .001,
              @"Launch migration retains the first parametric curve and removes every duplicate EQ");
        preferences.equalizerType = EqualizerTypeParametric;
        Player *player = Player.sharedInstance;
        player.effects = @[];
        NSButton *menu = [[NSButton alloc] initWithFrame:NSMakeRect(271, 366, 42, 32)];
        NSTextField *summary = [NSTextField labelWithString:@""];
        summary.frame = NSMakeRect(8, 313, 304, 20);
        SetlistEQButton *button = [SetlistEQButton buttonUnderMenu:menu besideSummary:summary player:player];
        Check(button.state == NSControlStateValueOff, @"EQ starts off when absent");
        [button performClick:nil];
        Check(player.effects.count == 1 && button.state == NSControlStateValueOn, @"First click adds and enables one custom EQ");
        Effect *effect = player.effects.firstObject;
        Check(delegate.editedEffect == effect && delegate.controller.presentations == 1, @"First enable opens the newly added custom EQ panel");
        AUParameter *gain = [effect.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain];
        Check(gain.value == 0, @"A newly enabled EQ starts flat");
        gain.value = -5;
        NSArray *values = Parameters(effect);
        NSUInteger originalAssignments = assignments;
        [button performClick:nil];
        Check(effect.bypass && button.state == NSControlStateValueOff && [button.toolTip containsString:@"off"], @"Button bypasses EQ and reports off");
        Check(delegate.editedEffect == effect && delegate.controller.presentations == 2, @"Bypass also opens the existing EQ panel");
        [button performClick:nil];
        Check(!effect.bypass && button.state == NSControlStateValueOn, @"Second click re-enables the same EQ");
        Check(delegate.editedEffect == effect && delegate.controller.presentations == 3, @"Re-enable routes to the same effect editor");
        Check(assignments == originalAssignments && player.effects.firstObject == effect && [Parameters(effect) isEqual:values], @"Existing toggles preserve the unit and all parameters without rebuilding the chain");
        effect.bypass = YES;
        Check(button.state == NSControlStateValueOff, @"External bypass updates the button while stopped");
        effect.bypass = NO;
        Check(button.state == NSControlStateValueOn, @"External re-enable updates the button");
        [button performClick:nil];
        Effect *restored = [Effect effectWithStateDictionary:savedEffects.firstObject];
        Check(restored.bypass && [Parameters(restored) isEqual:values], @"Saved chain restores bypass and every parameter");
        NSMutableDictionary *legacy = [effect.stateDictionary mutableCopy];
        [legacy removeObjectForKey:@"bypass"];
        Check(![Effect effectWithStateDictionary:legacy].bypass, @"Legacy chains without bypass remain enabled");
        legacy[@"bypass"] = @"invalid";
        Check(![Effect effectWithStateDictionary:legacy].bypass, @"Malformed optional bypass does not disable an effect");
        Check([effect loadEQPresetInSlot:EQPresetSlotViolin] && effect.bypass, @"Preset recall retains bypass state");
        Effect *graphic = NewEffect(EmbraceMappedEffect10BandEQ);
        Effect *second = NewEffect(EmbraceEffectParametricEQ);
        player.effects = @[graphic, effect, second];
        Check(button.state == NSControlStateValueOn, @"A legacy mixed chain reports the parametric EQ state");
        originalAssignments = assignments;
        [button performClick:nil];
        Check(player.effects.count == 1 && player.effects.firstObject == effect && effect.bypass,
              @"First action removes graphic and duplicate EQ units while preserving the first parametric EQ");
        Check(delegate.editedEffect == effect, @"A legacy mixed chain opens the retained parametric EQ panel");
        [button performClick:nil];
        Check(!effect.bypass && assignments == originalAssignments + 1,
              @"On restores the retained parametric EQ without another graph assignment");
        player.effects = @[graphic];
        Check(button.state == NSControlStateValueOff, @"Removing custom EQ refreshes the button");
        [button performClick:nil];
        Check(player.effects.count == 1 && [player.effects.firstObject.type.name isEqualToString:EmbraceEffectParametricEQ],
              @"Enabling a legacy graphic-only chain replaces it with one parametric EQ");
        preferences.equalizerType = EqualizerTypeGraphic10Band;
        player.effects = @[graphic];
        Check(button.state == NSControlStateValueOff, @"A stale graphic preference cannot activate the removed graphic EQ");
        [button performClick:nil];
        Check(button.state == NSControlStateValueOn &&
              [player.effects.firstObject.type.name isEqualToString:EmbraceEffectParametricEQ] &&
              delegate.editedEffect == player.effects.firstObject,
              @"A stale graphic preference resolves to the sole parametric EQ");
        preferences.equalizerType = EqualizerTypeParametric;
        Check(saves > 5, @"Each button action persists the resulting chain state");
        TestGeometry(Preferences.sharedInstance);
        TestParametricAutomaticResize(Preferences.sharedInstance);
        TestLinkedButtons();
        TestCurvePreview();
        TestPresetControls();
        TestButtonColors();
        [defaults removePersistentDomainForName:domain];
        printf("PASS: %lu EQ toggle and geometry assertions\n", (unsigned long)checks);
    }
    return 0;
}
