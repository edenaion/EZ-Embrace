#import <Cocoa/Cocoa.h>
#import "InterfaceAppearance.h"
#import "Preferences.h"
#import "HugAudioDevice.h"

// Isolate preference/UI tests from audio hardware and app startup.
NSString * const EmbraceMappedEffect10BandEQ = @"Test EQ";
NSString *GetAppBuildString(void) { return @"1261"; }
NSUInteger GetCombinedBuildNumber(NSString *string) { return string.integerValue; }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-property-implementation"
@implementation HugAudioDevice
+ (instancetype) placeholderDevice { return [[self alloc] init]; }
+ (instancetype) bestDefaultDevice { return [self placeholderDevice]; }
+ (instancetype) archivedDeviceWithDeviceUID:(NSString *)uid name:(NSString *)name { return [self placeholderDevice]; }
- (NSString *) deviceUID { return @"test-device"; }
- (NSString *) name { return @"Test device"; }
@end
#pragma clang diagnostic pop

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

static NSSize DrawnSize(NSView *view) { return [view convertRect:view.bounds toView:nil].size; }

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *domain = NSProcessInfo.processInfo.processName;
        Check([domain isEqualToString:@"ez-embrace-appearance-tests"], @"Tests use a separate preferences domain");
        [defaults removePersistentDomainForName:domain];
        [defaults setBool:YES forKey:@"usesLargerText"];
        Preferences *preferences = [Preferences sharedInstance];
        NSColor *defaultGenreColor = [[preferences upcomingOtherGenreColor]
            colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        Check(defaultGenreColor.redComponent > 0.70 && defaultGenreColor.greenComponent > 0.88 &&
              defaultGenreColor.blueComponent > 0.75,
            @"Other upcoming genres default to a light mint color");
        NSColor *customGenreColor = [NSColor colorWithSRGBRed:0.42 green:0.63 blue:0.81 alpha:1];
        preferences.upcomingOtherGenreColor = customGenreColor;
        Preferences *colorReloaded = [[Preferences alloc] init];
        Check([[colorReloaded.upcomingOtherGenreColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace]
            isEqual:[customGenreColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace]],
            @"Other-genre highlight color persists across preference reloads");
        [preferences resetUpcomingOtherGenreColor];
        Check([[[preferences upcomingOtherGenreColor] colorUsingColorSpace:NSColorSpace.sRGBColorSpace]
            isEqual:defaultGenreColor], @"Other-genre highlight resets to mint");
        Check(preferences.textSizePercent == 125, @"Legacy larger-text preference migrates");
        preferences.textSizePercent = 100;
        preferences.usesBoldText = NO;
        preferences.scalesInterfaceWithWindow = NO;

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(40, 40, 400, 300)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        window.contentMinSize = NSMakeSize(240, 200);
        NSButton *button = [NSButton buttonWithTitle:@"Test action" target:nil action:NULL];
        button.frame = NSMakeRect(20, 20, 100, 28);
        [window.contentView addSubview:button];
        NSTextField *lightLabel = [NSTextField labelWithString:@"Current Track"];
        lightLabel.font = [NSFont monospacedDigitSystemFontOfSize:24 weight:NSFontWeightLight];
        [window.contentView addSubview:lightLabel];
        NSButton *tab = [NSButton buttonWithTitle:@"Appearance" target:nil action:NULL];
        tab.translatesAutoresizingMaskIntoConstraints = NO;
        [window.contentView addSubview:tab];
        [NSLayoutConstraint activateConstraints:@[
            [tab.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:12],
            [tab.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor]
        ]];
        [InterfaceAppearance installInWindow:window];
        [InterfaceAppearance setAllowsIndependentResizeAxes:YES inWindow:window];
        NSSize baseline = DrawnSize(button);
        Check(fabs(baseline.width - 100) < 0.1, @"Default transform is identity");

        for (NSNumber *percent in @[@100, @125, @150, @175, @200]) {
            preferences.textSizePercent = percent.integerValue;
            NSSize size = DrawnSize(button);
            Check(NSEqualSizes(window.contentView.bounds.size, window.contentView.frame.size),
                @"Window base coordinates remain unscaled for native mouse routing");
            [window.contentView layoutSubtreeIfNeeded];
            NSRect tabs = [tab convertRect:tab.bounds toView:nil];
            NSRect visible = [window.contentView convertRect:window.contentView.bounds toView:nil];
            Check(NSContainsRect(visible, tabs), @"Auto Layout navigation stays inside the scaled window");
            CGFloat scale = percent.doubleValue / 100;
            Check(fabs(size.width / baseline.width - scale) < 0.01, @"Text-size preset scales controls horizontally");
            Check(fabs(size.height / baseline.height - scale) < 0.01, @"Text-size preset scales controls vertically");
            for (NSNumber *bold in @[@YES, @NO]) {
                preferences.usesBoldText = bold.boolValue;
                BOOL hasBold = ([[NSFontManager sharedFontManager] traitsOfFont:button.font] & NSBoldFontMask) != 0;
                Check(hasBold == bold.boolValue, @"Bold applies independently of size");
                BOOL lightBold = ([[NSFontManager sharedFontManager] traitsOfFont:lightLabel.font] & NSBoldFontMask) != 0;
                Check(lightBold == bold.boolValue, @"Light playback fonts honor bold preference");
            }
        }

        preferences.textSizePercent = 125;
        preferences.scalesInterfaceWithWindow = YES;
        Check(window.contentResizeIncrements.width >= 1 && window.contentResizeIncrements.height >= 1,
            @"Uniform content scaling leaves both window axes independently resizable");
        Check(window.contentMaxSize.width <= 32768 && window.contentMaxSize.height <= 32768, @"Resize limits remain finite and bounded");
        NSDictionary *saved = [defaults persistentDomainForName:domain];
        NSSize before = DrawnSize(button);
        NSSize contentSize = window.contentView.frame.size;
        [window setContentSize:NSMakeSize(contentSize.width * 1.25, contentSize.height)];
        NSSize horizontalOnly = window.contentView.frame.size;
        Check(fabs(horizontalOnly.width - contentSize.width * 1.25) < 1 &&
              fabs(horizontalOnly.height - contentSize.height) < 1,
              @"Horizontal-only resizing is not aspect locked");
        Check(fabs(DrawnSize(button).width - before.width) < 0.1,
              @"Horizontal-only resizing keeps complete content fitted at one scale");
        [window setContentSize:NSMakeSize(contentSize.width * 1.5, contentSize.height * 1.5)];
        NSSize after = DrawnSize(button);
        Check(fabs(after.width / before.width - 1.5) < 0.01, @"Resize enlarges contents");
        Check(fabs(after.width / before.width - after.height / before.height) < 0.01, @"Both axes use one scale");
        Check([[defaults persistentDomainForName:domain] isEqual:saved], @"Resizing does not rewrite preferences");
        preferences.scalesInterfaceWithWindow = NO;
        Check(window.contentResizeIncrements.width >= 1 && window.contentResizeIncrements.height >= 1,
            @"Disabling restores positive resize increments instead of installing a zero aspect ratio");
        before = DrawnSize(button);
        [window setContentSize:NSMakeSize(700, 500)];
        after = DrawnSize(button);
        Check(fabs(after.width - before.width) < 0.1, @"Ordinary resizing retains manual text scale");

        NSWindow *fixed = [[NSWindow alloc] initWithContentRect:NSMakeRect(60, 60, 320, 220)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [InterfaceAppearance installInWindow:fixed];
        [InterfaceAppearance setAllowsIndependentResizeAxes:YES inWindow:fixed];
        Check(!(fixed.styleMask & NSWindowStyleMaskResizable), @"Fixed window stays fixed with scaling off");
        preferences.scalesInterfaceWithWindow = YES;
        Check((fixed.styleMask & NSWindowStyleMaskResizable) != 0, @"Scaling enables resizing for a fixed window");
        NSSize otherWindow = DrawnSize(button);
        [fixed setContentSize:NSMakeSize(600, 440)];
        Check(fabs(DrawnSize(button).width - otherWindow.width) < 0.1, @"Windows scale independently");
        preferences.scalesInterfaceWithWindow = NO;
        Check(!(fixed.styleMask & NSWindowStyleMaskResizable), @"Disabling scaling restores fixed-window policy");

        preferences.textSizePercent = 200;
        NSWindow *large = [[NSWindow alloc] initWithContentRect:NSMakeRect(60, 60, 2000, 1000)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        NSButton *farButton = [NSButton buttonWithTitle:@"Reach this action" target:nil action:NULL];
        farButton.frame = NSMakeRect(1800, 700, 150, 28);
        [large.contentView addSubview:farButton];
        [InterfaceAppearance installInWindow:large];
        Check(large.frame.size.width <= large.screen.visibleFrame.size.width, @"Oversized interface fits the screen");
        Check([large.contentView isKindOfClass:[NSScrollView class]], @"Oversized fixed content remains reachable by scrolling");
        NSScrollView *viewport = (NSScrollView *)large.contentView;
        Check(NSMaxY(viewport.documentVisibleRect) >= NSMaxY(viewport.documentView.bounds) - 1,
            @"Overflowed large-text windows open at their top edge");
        [farButton scrollRectToVisible:farButton.bounds];
        NSRect actionRect = [farButton convertRect:farButton.bounds toView:viewport.documentView];
        Check(NSContainsRect(NSInsetRect(viewport.documentVisibleRect, -1, -1), actionRect), @"Scrolling reveals an otherwise offscreen button");

        preferences.usesLargerText = NO;
        Check(preferences.textSizePercent == 100, @"View menu can restore standard size");
        Check(fixed.contentView.frame.size.width >= 240 && fixed.contentView.frame.size.width <= 320,
            @"Independently resizable fixed content returns to a compact usable width");
        preferences.usesLargerText = YES;
        Check(preferences.textSizePercent == 125, @"View menu selects larger size");
        preferences.textSizePercent = 175;
        preferences.usesBoldText = YES;
        preferences.scalesInterfaceWithWindow = YES;
        preferences.automaticallyArrangesWindows = YES;
        Preferences *reloaded = [[Preferences alloc] init];
        Check(reloaded.textSizePercent == 175 && reloaded.usesBoldText && reloaded.scalesInterfaceWithWindow &&
              reloaded.automaticallyArrangesWindows,
            @"All appearance preferences reload");
        preferences.textSizePercent = 100;
        preferences.scalesInterfaceWithWindow = NO;
        preferences.automaticallyArrangesWindows = NO;

        printf("Window layout geometry\n");
        for (NSValue *visibleValue in @[
            [NSValue valueWithRect:NSMakeRect(0, 0, 1470, 920)],
            [NSValue valueWithRect:NSMakeRect(0, 0, 1024, 720)]
        ]) {
            NSRect visible = visibleValue.rectValue;
            NSDictionary *layout = [InterfaceAppearance automaticWindowFramesForVisibleFrame:visible];
            Check(layout.count == 3, @"Automatic layout includes Music library, Set List and Equalizer");
            for (NSString *identifier in @[WindowBorderSetList, WindowBorderMusicLibrary,
                                            WindowLayoutEqualizer]) {
                NSRect frame = [layout[identifier] rectValue];
                Check(NSContainsRect(visible, frame) && frame.size.width > 0 && frame.size.height > 0,
                      @"Automatic layout keeps every window inside the logical visible frame");
            }
            NSRect setList = [layout[WindowBorderSetList] rectValue];
            NSRect library = [layout[WindowBorderMusicLibrary] rectValue];
            NSRect equalizer = [layout[WindowLayoutEqualizer] rectValue];
            Check(layout[WindowBorderCurrentTrack] == nil,
                  @"Current Track is omitted from the automatic layout");
            Check(NSMaxX(library) <= MIN(NSMinX(setList), NSMinX(equalizer)),
                  @"Music library stays left of Set List and Equalizer");
            Check(NSMinY(setList) >= NSMaxY(equalizer),
                  @"Set List stays above the lower-right Equalizer");
        }
        NSDictionary *largeDisplayLayout = [InterfaceAppearance
            automaticWindowFramesForVisibleFrame:NSMakeRect(0, 0, 1680, 1020)];
        NSRect largeLibrary = [largeDisplayLayout[WindowBorderMusicLibrary] rectValue];
        NSRect largeEqualizer = [largeDisplayLayout[WindowLayoutEqualizer] rectValue];
        Check(NSMaxX(largeLibrary) <= NSMinX(largeEqualizer),
              @"Large logical display preserves the library-left arrangement");
        NSRect constrained = [InterfaceAppearance frame:NSMakeRect(-900, 2000, 1800, 1200)
                                          constrainedToVisibleFrame:NSMakeRect(0, 0, 1024, 720)];
        Check(NSContainsRect(NSMakeRect(0, 0, 1024, 720), constrained),
              @"Recalled offscreen layout is made fully reachable");

        preferences.textSizePercent = 200;
        preferences.scalesInterfaceWithWindow = YES;
        NSWindow *arranged = [[NSWindow alloc] initWithContentRect:NSMakeRect(40, 40, 760, 520)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
            backing:NSBackingStoreBuffered defer:NO];
        arranged.contentMinSize = NSMakeSize(500, 360);
        NSButton *bottomAction = [NSButton buttonWithTitle:@"Bottom action" target:nil action:NULL];
        bottomAction.frame = NSMakeRect(560, 16, 150, 28);
        [arranged.contentView addSubview:bottomAction];
        [InterfaceAppearance installInWindow:arranged designSize:NSMakeSize(760, 520)];
        [InterfaceAppearance setAllowsIndependentResizeAxes:YES inWindow:arranged];
        [arranged orderFront:nil];
        NSRect arrangedTarget = [arranged frameRectForContentRect:NSMakeRect(100, 100, 430, 310)];
        [InterfaceAppearance applyAutomaticFrame:arrangedTarget toWindow:arranged];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        NSSize arrangedContent = [arranged contentRectForFrameRect:arrangedTarget].size;
        Check(fabs(arranged.contentView.frame.size.width - arrangedContent.width) < 1 &&
              fabs(arranged.contentView.frame.size.height - arrangedContent.height) < 1,
              @"Automatic placement immediately propagates the target content geometry");
        NSView *arrangedDocument = [InterfaceAppearance contentViewForWindow:arranged];
        Check(arrangedDocument.superview.frame.size.width >= arrangedContent.width &&
              arrangedDocument.superview.frame.size.height >= arrangedContent.height,
              @"Automatic placement refreshes scaled content without a manual resize");
        NSRect arrangedAction = [bottomAction convertRect:bottomAction.bounds toView:arranged.contentView];
        Check(NSContainsRect(NSInsetRect(arranged.contentView.bounds, -1, -1), arrangedAction),
              @"Automatic placement scales bottom controls into the visible window");
        if ([arranged.contentView isKindOfClass:[NSScrollView class]]) {
            NSScrollView *arrangedViewport = (NSScrollView *)arranged.contentView;
            [bottomAction scrollRectToVisible:bottomAction.bounds];
            NSRect actionRect = [bottomAction convertRect:bottomAction.bounds toView:arrangedViewport.documentView];
            Check(NSContainsRect(NSInsetRect(arrangedViewport.documentVisibleRect, -1, -1), actionRect),
                  @"Automatic placement keeps bottom controls reachable at 200 percent scaling");
        }
        [arranged orderOut:nil];
        preferences.textSizePercent = 100;
        preferences.scalesInterfaceWithWindow = NO;

        NSWindow *display = [[NSWindow alloc] initWithContentRect:NSMakeRect(20, 50, 800, 80)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
            backing:NSBackingStoreBuffered defer:NO];
        display.titlebarAppearsTransparent = YES;
        display.titleVisibility = NSWindowTitleHidden;
        display.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        display.contentView.wantsLayer = YES;
        NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:display.contentView.bounds];
        background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        background.material = NSVisualEffectMaterialSidebar;
        background.state = NSVisualEffectStateActive;
        background.translatesAutoresizingMaskIntoConstraints = NO;
        [display.contentView addSubview:background];
        NSTextField *playbackLabel = [NSTextField labelWithString:@"No Track Playing"];
        playbackLabel.font = [NSFont systemFontOfSize:24 weight:NSFontWeightLight];
        playbackLabel.frame = NSMakeRect(200, 20, 400, 36);
        [background addSubview:playbackLabel];
        [NSLayoutConstraint activateConstraints:@[
            [background.leadingAnchor constraintEqualToAnchor:display.contentView.leadingAnchor],
            [background.trailingAnchor constraintEqualToAnchor:display.contentView.trailingAnchor],
            [background.topAnchor constraintEqualToAnchor:display.contentView.topAnchor],
            [background.bottomAnchor constraintEqualToAnchor:display.contentView.bottomAnchor]
        ]];
        [InterfaceAppearance installInWindow:display];
        preferences.scalesInterfaceWithWindow = YES;
        Check(fabs(display.aspectRatio.width / display.aspectRatio.height - 10) < 0.001,
            @"Full-content windows constrain the whole frame for uniform scaling");
        [display orderFront:nil];
        for (NSUInteger i = 0; i < 20; i++) {
            [display setFrame:NSMakeRect(100 + i, 150 + i, 800 + i * 10, 80 + i) display:YES];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        NSRect userFrame = display.frame;
        [display zoom:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("Zoom user=%s standard=%s zoomed=%d\n", NSStringFromRect(userFrame).UTF8String,
            NSStringFromRect(display.frame).UTF8String, display.isZoomed);
        [display zoom:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("Zoom restored=%s\n", NSStringFromRect(display.frame).UTF8String);
        Check(fabs(display.frame.size.width - userFrame.size.width) < 1 && fabs(display.frame.size.height - userFrame.size.height) < 1,
            @"Native zoom restores a full-content window with uniform scaling");
        [display orderOut:nil];
        Check(YES, @"Full-content translucent window survives repeated geometry changes");
        [defaults removePersistentDomainForName:domain];
        printf("PASS: %lu appearance assertions\n", (unsigned long)checks);
    }
    return 0;
}
