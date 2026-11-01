#import "InterfaceAppearance.h"
#import "Preferences.h"
#import <objc/runtime.h>

NSString * const WindowLayoutEqualizer = @"Equalizer";

@interface InterfaceBorderView : NSView
@property (nonatomic) NSColor *borderColor;
@end

@implementation InterfaceBorderView
- (NSView *) hitTest:(NSPoint)point { return nil; }
- (BOOL) isAccessibilityElement { return NO; }
- (void) drawRect:(NSRect)dirtyRect
{
    if (!_borderColor) return;
    CGFloat inset = 1.5;
    CGFloat width = 1.25;
    CGFloat radius = 12.5;
    NSRect outer = NSInsetRect(self.bounds, inset, inset);
    if (outer.size.width <= width * 2 || outer.size.height <= width * 2) return;
    NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:outer xRadius:radius yRadius:radius];
    [edge appendBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(outer, width, width)
        xRadius:radius - width yRadius:radius - width]];
    edge.windingRule = NSWindingRuleEvenOdd;
    NSColor *base = [_borderColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSColor *top = [[base blendedColorWithFraction:0.18 ofColor:NSColor.whiteColor] colorWithAlphaComponent:0.88];
    NSColor *bottom = [[base blendedColorWithFraction:0.08 ofColor:NSColor.blackColor] colorWithAlphaComponent:0.78];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:bottom endingColor:top];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext.shouldAntialias = YES;
    [gradient drawInBezierPath:edge angle:90];
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface InterfaceScaleView : NSView
@property (nonatomic) NSView *documentView;
@property (nonatomic) NSSize designSize;
@property (nonatomic) CGFloat textScale;
@property (nonatomic) BOOL scalesWithWindow;
- (void) updateGeometry;
@end

@implementation InterfaceScaleView
- (void) setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [self updateGeometry];
}

- (void) updateGeometry
{
    NSSize size = [self frame].size;
    CGFloat scale = MAX(1, _textScale);
    if (_scalesWithWindow && _designSize.width > 0 && _designSize.height > 0) {
        // Keep one visual scale factor, but let either window axis move freely.
        // A smaller window scales the complete interface down instead of
        // clipping it. Extra room on one axis remains available to flexible
        // layouts while the other axis determines the uniform scale.
        scale = MIN(size.width / _designSize.width, size.height / _designSize.height);
    }
    if (scale <= 0) return;
    // The same transform draws, lays out, and hit-tests every descendant.
    NSSize logical = NSMakeSize(size.width / scale, size.height / scale);
    if (!NSEqualSizes([self bounds].size, logical)) [self setBoundsSize:logical];
    if (!NSEqualRects([_documentView frame], [self bounds])) [_documentView setFrame:[self bounds]];
}
@end

@interface InterfaceAppearance ()
@property (nonatomic, weak) NSWindow *window;
- (void) _applyTheme;
- (void) _refreshGeometryAfterWindowFrameChange;
- (void) _viewportResized:(NSNotification *)note;
@end

@implementation InterfaceAppearance {
    InterfaceScaleView *_scaleView;
    NSView *_hostView;
    NSScrollView *_viewport;
    NSSize _scaledMinimum;
    NSSize _minimumSize;
    NSSize _maximumSize;
    NSSize _originalAspectRatio;
    NSSize _originalResizeIncrements;
    BOOL _layingOut;
    BOOL _wasResizable;
    BOOL _madeResizable;
    BOOL _updating;
    CGFloat _textScale;
    BOOL _scalesWithWindow;
    BOOL _allowsIndependentResizeAxes;
    NSMapTable<NSView *, NSFont *> *_originalFonts;
    NSMapTable<NSView *, NSFont *> *_appliedFonts;
    NSMapTable<NSView *, NSColor *> *_originalTextColors;
    NSMapTable<NSView *, NSColor *> *_appliedTextColors;
    NSMapTable<NSView *, NSNumber *> *_nativeTextContexts;
    NSString *_borderIdentifier;
    InterfaceBorderView *_borderView;
}

static char sAppearanceKey;
static char sBaseFontKey;
static char sBaseTextColorKey;
static char sAppliesTextContrastKey;

static NSFont *sPreferredFont(NSFont *original)
{
    if (![[Preferences sharedInstance] usesBoldText]) return original;
    NSFont *desired = [[NSFontManager sharedFontManager] convertFont:original toHaveTrait:NSBoldFontMask];
    if (!([[NSFontManager sharedFontManager] traitsOfFont:desired] & NSBoldFontMask)) {
        NSFontDescriptor *descriptor = [[original fontDescriptor] fontDescriptorWithSymbolicTraits:
            [[original fontDescriptor] symbolicTraits] | NSFontBoldTrait];
        desired = [NSFont fontWithDescriptor:descriptor size:original.pointSize];
        if (!([[NSFontManager sharedFontManager] traitsOfFont:desired] & NSBoldFontMask)) {
            desired = [NSFont monospacedDigitSystemFontOfSize:original.pointSize weight:NSFontWeightBold];
        }
    }
    return desired ?: original;
}

static BOOL sPreservesNativeTextColor(NSView *view)
{
    if ([view isKindOfClass:[NSControl class]] && ![(NSControl *)view isEnabled]) return YES;
    for (NSView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:[NSTableRowView class]]) {
            NSTableRowView *row = (NSTableRowView *)ancestor;
            return row.selected && row.emphasized;
        }
    }
    return NO;
}

static NSColor *sContrastingTextColor(NSColor *color, NSView *view)
{
    if ([[Preferences sharedInstance] themeType] == ThemeTypeBlush) return NSColor.blackColor;
    CGFloat strength = [[Preferences sharedInstance] textContrastPercent] / 100.0;
    if (!color || strength == 0 || sPreservesNativeTextColor(view)) return color;
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        __block NSColor *result = color;
        [appearance performAsCurrentDrawingAppearance:^{
            NSString *match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
            NSColor *target = [match isEqualToString:NSAppearanceNameDarkAqua] ? NSColor.whiteColor : NSColor.blackColor;
            // Preserve a visible difference between primary and secondary text.
            result = [color blendedColorWithFraction:strength * 0.8 ofColor:target] ?: color;
        }];
        return result;
    }];
}

+ (void) setFont:(NSFont *)font forControl:(NSControl *)control
{
    if (!font || !control) return;
    objc_setAssociatedObject(control, &sBaseFontKey, font, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control setFont:sPreferredFont(font)];
}

+ (void) setTextColor:(NSColor *)color forField:(NSTextField *)field
{
    [self setTextColor:color forField:field appliesContrast:YES];
}

+ (void) setTextColor:(NSColor *)color forField:(NSTextField *)field appliesContrast:(BOOL)appliesContrast
{
    if (!field) return;
    objc_setAssociatedObject(field, &sBaseTextColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(field, &sAppliesTextContrastKey, @(appliesContrast), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    field.textColor = appliesContrast ? sContrastingTextColor(color, field) : color;
}

+ (NSColor *) blushSetListColor
{
    return [NSColor colorWithSRGBRed:1 green:0.969 blue:0.980 alpha:1];
}

+ (NSColor *) blushCurrentTrackColor
{
    return [NSColor colorWithSRGBRed:0.992 green:0.922 blue:0.949 alpha:1];
}

+ (NSColor *) blushMusicLibraryColor
{
    return [NSColor colorWithSRGBRed:0.973 green:0.863 blue:0.910 alpha:1];
}

+ (NSDictionary<NSString *, NSValue *> *) automaticWindowFramesForVisibleFrame:(NSRect)visibleFrame
{
    if (NSIsEmptyRect(visibleFrame)) return @{};

    const CGFloat margin = 10;
    const CGFloat gap = 10;
    NSRect work = NSInsetRect(visibleFrame, margin, margin);
    CGFloat libraryWidth = round((work.size.width - gap) * 0.64);
    NSRect library = NSMakeRect(NSMinX(work), NSMinY(work), libraryWidth, NSHeight(work));
    NSRect right = NSMakeRect(NSMaxX(library) + gap, NSMinY(work),
                              MAX(0, NSMaxX(work) - NSMaxX(library) - gap), NSHeight(work));
    CGFloat equalizerHeight = round((right.size.height - gap) * 0.44);
    NSRect equalizer = NSMakeRect(NSMinX(right), NSMinY(right), NSWidth(right), equalizerHeight);
    NSRect setList = NSMakeRect(NSMinX(right), NSMaxY(equalizer) + gap, NSWidth(right),
                                MAX(0, NSMaxY(right) - NSMaxY(equalizer) - gap));

    return @{
        WindowBorderSetList: [NSValue valueWithRect:setList],
        WindowBorderMusicLibrary: [NSValue valueWithRect:library],
        WindowLayoutEqualizer: [NSValue valueWithRect:equalizer]
    };
}

+ (void) applyAutomaticFrame:(NSRect)frame toWindow:(NSWindow *)window
{
    if (!window) return;
    InterfaceAppearance *appearance = objc_getAssociatedObject(window, &sAppearanceKey);
    if (!appearance) {
        [window setFrame:frame display:YES animate:NO];
        return;
    }

    NSSize targetContent = [window contentRectForFrameRect:frame].size;
    if (targetContent.width + 1 < appearance->_scaledMinimum.width ||
        targetContent.height + 1 < appearance->_scaledMinimum.height) {
        [window setContentMinSize:NSMakeSize(MIN(240, targetContent.width), MIN(100, targetContent.height))];
        appearance->_scaledMinimum = NSMakeSize(MIN(appearance->_scaledMinimum.width, targetContent.width),
                                                MIN(appearance->_scaledMinimum.height, targetContent.height));
    }
    [window setFrame:frame display:YES animate:NO];
    [appearance _refreshGeometryAfterWindowFrameChange];

    // AppKit can finish propagating a programmatic window frame on the next
    // main-loop turn. Re-converge once so automatic placement behaves like a
    // completed user resize without requiring the user to move the window.
    __weak InterfaceAppearance *weakAppearance = appearance;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakAppearance _refreshGeometryAfterWindowFrameChange];
    });
}

+ (NSRect) frame:(NSRect)frame constrainedToVisibleFrame:(NSRect)visibleFrame
{
    if (NSIsEmptyRect(visibleFrame)) return frame;
    frame.size.width = MIN(MAX(240, frame.size.width), visibleFrame.size.width);
    frame.size.height = MIN(MAX(100, frame.size.height), visibleFrame.size.height);
    frame.origin.x = MAX(NSMinX(visibleFrame), MIN(frame.origin.x, NSMaxX(visibleFrame) - frame.size.width));
    frame.origin.y = MAX(NSMinY(visibleFrame), MIN(frame.origin.y, NSMaxY(visibleFrame) - frame.size.height));
    return frame;
}

+ (void) setBorderIdentifier:(NSString *)identifier inWindow:(NSWindow *)window
{
    [self installInWindow:window];
    InterfaceAppearance *appearance = objc_getAssociatedObject(window, &sAppearanceKey);
    appearance->_borderIdentifier = [identifier copy];
    [appearance _applyTheme];
    [appearance _updateBorder:nil];
}

+ (void) setAllowsIndependentResizeAxes:(BOOL)allowed inWindow:(NSWindow *)window
{
    [self installInWindow:window];
    InterfaceAppearance *appearance = objc_getAssociatedObject(window, &sAppearanceKey);
    if (!appearance || appearance->_allowsIndependentResizeAxes == allowed) return;
    appearance->_allowsIndependentResizeAxes = allowed;
    [appearance _applyPreferencesResizing:NO];
}

+ (void) installInWindow:(NSWindow *)window
{
    [self installInWindow:window designSize:NSZeroSize];
}

+ (void) installInWindow:(NSWindow *)window designSize:(NSSize)designSize
{
    if (!window || objc_getAssociatedObject(window, &sAppearanceKey)) return;
    InterfaceAppearance *appearance = [[self alloc] initWithWindow:window designSize:designSize];
    objc_setAssociatedObject(window, &sAppearanceKey, appearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (BOOL) isInstalledInWindow:(NSWindow *)window
{
    return window && objc_getAssociatedObject(window, &sAppearanceKey) != nil;
}

+ (NSView *) contentViewForWindow:(NSWindow *)window
{
    InterfaceAppearance *appearance = objc_getAssociatedObject(window, &sAppearanceKey);
    return appearance ? appearance->_scaleView.documentView : [window contentView];
}

+ (void) setContentSize:(NSSize)size inWindow:(NSWindow *)window
{
    InterfaceAppearance *appearance = objc_getAssociatedObject(window, &sAppearanceKey);
    if (!appearance) { [window setContentSize:size]; return; }
    CGFloat scale = appearance->_textScale;
    NSSize oldDesign = appearance->_scaleView.designSize;
    if (appearance->_scalesWithWindow && oldDesign.width > 0) {
        scale = MAX(scale, appearance->_scaleView.frame.size.width / oldDesign.width);
    }
    appearance->_scaleView.designSize = size;
    appearance->_minimumSize = size;
    [appearance _applyPreferencesResizing:NO];
    [appearance _resizeWindowToSize:NSMakeSize(size.width * scale, size.height * scale)];
}

- (instancetype) initWithWindow:(NSWindow *)window designSize:(NSSize)designSize
{
    if ((self = [super init])) {
        _window = window;
        _minimumSize = [window contentMinSize];
        _maximumSize = [window contentMaxSize];
        // Keep resize limits finite and bounded, including inherited default maxima.
        _maximumSize.width = MIN(_maximumSize.width, 32768);
        _maximumSize.height = MIN(_maximumSize.height, 32768);
        _originalAspectRatio = [window contentAspectRatio];
        _originalResizeIncrements = [window contentResizeIncrements];
        _wasResizable = ([window styleMask] & NSWindowStyleMaskResizable) != 0;
        _textScale = [[Preferences sharedInstance] textSizePercent] / 100.0;
        _scalesWithWindow = [[Preferences sharedInstance] scalesInterfaceWithWindow];
        _originalFonts = [NSMapTable weakToStrongObjectsMapTable];
        _appliedFonts = [NSMapTable weakToStrongObjectsMapTable];
        _originalTextColors = [NSMapTable weakToStrongObjectsMapTable];
        _appliedTextColors = [NSMapTable weakToStrongObjectsMapTable];
        _nativeTextContexts = [NSMapTable weakToStrongObjectsMapTable];

        NSView *content = [window contentView];
        _scaleView = [[InterfaceScaleView alloc] initWithFrame:[content frame]];
        _scaleView.wantsLayer = YES;
        _scaleView.clipsToBounds = YES;
        _scaleView.designSize = [content bounds].size;
        BOOL hasFlexibleLayout = _wasResizable && !NSEqualSizes(_minimumSize, _maximumSize);
        if (designSize.width > 0 && designSize.height > 0) {
            _scaleView.designSize = designSize;
        } else if (hasFlexibleLayout) {
            _scaleView.designSize = NSMakeSize(_scaleView.designSize.width / _textScale, _scaleView.designSize.height / _textScale);
            NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:[self _windowStateKey]];
            NSSize savedSize = NSSizeFromString(saved ?: @"");
            if (_scalesWithWindow && savedSize.width > 0 && savedSize.height > 0) _scaleView.designSize = savedSize;
        }
        _scaleView.documentView = content;
        _scaleView.autoresizesSubviews = NO;
        // Window base coordinates must remain unscaled for native mouse routing.
        // Apply the transform below a normal content view, with Auto Layout below it.
        _hostView = [[NSView alloc] initWithFrame:[content frame]];
        _hostView.wantsLayer = YES;
        [window setContentView:_hostView];
        [_scaleView setFrame:[_hostView bounds]];
        _scaleView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_hostView addSubview:_scaleView];
        [content setTranslatesAutoresizingMaskIntoConstraints:YES];
        [content setClipsToBounds:YES];
        [content setAutoresizingMask:0];
        [_scaleView addSubview:content];

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(_preferencesChanged:) name:PreferencesDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(_textContrastChanged:) name:TextContrastDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(_updateBorder:) name:WindowBorderColorsDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(_windowUpdated:) name:NSWindowDidUpdateNotification object:window];
        [center addObserver:self selector:@selector(_screenChanged:) name:NSWindowDidChangeScreenNotification object:window];
        [center addObserver:self selector:@selector(_saveWindowState:) name:NSWindowWillCloseNotification object:window];
        [center addObserver:self selector:@selector(_saveWindowState:) name:NSApplicationWillTerminateNotification object:nil];
        [self _applyTheme];
        [self _applyPreferencesResizing:YES];
    }
    return self;
}

- (void) dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void) _applyBoldToView:(NSView *)view force:(BOOL)force
{
    if ([view isKindOfClass:[NSControl class]] || [view isKindOfClass:[NSTextView class]]) {
        id control = view;
        NSFont *font = [control font];
        if (font && (force || ![font isEqual:[_appliedFonts objectForKey:view]])) {
            NSFont *original = objc_getAssociatedObject(control, &sBaseFontKey) ?: [_originalFonts objectForKey:control];
            if (!original) {
                original = font;
                [_originalFonts setObject:font forKey:control];
            }
            NSFont *desired = sPreferredFont(original);
            if (desired && ![desired isEqual:font]) [control setFont:desired];
            [_appliedFonts setObject:[control font] forKey:view];
        }
    }
    for (NSView *child in [view subviews]) [self _applyBoldToView:child force:force];
}

- (void) _applyTextContrastToView:(NSView *)view force:(BOOL)force
{
    if ([view isKindOfClass:[NSTextField class]] || [view isKindOfClass:[NSTextView class]]) {
        id text = view;
        NSColor *color = [text textColor];
        NSColor *applied = [_appliedTextColors objectForKey:view];
        NSNumber *native = @(sPreservesNativeTextColor(view));
        if (color && (force || ![color isEqual:applied] || ![native isEqual:[_nativeTextContexts objectForKey:view]])) {
            NSColor *original = objc_getAssociatedObject(view, &sBaseTextColorKey);
            if (!original) {
                original = ![color isEqual:applied] ? color : [_originalTextColors objectForKey:view];
                if (original) [_originalTextColors setObject:original forKey:view];
            }
            NSNumber *appliesContrast = objc_getAssociatedObject(view, &sAppliesTextContrastKey);
            NSColor *base = original ?: color;
            NSColor *desired = appliesContrast == nil || appliesContrast.boolValue ? sContrastingTextColor(base, view) : base;
            if (![desired isEqual:color]) [text setTextColor:desired];
            [_appliedTextColors setObject:[text textColor] forKey:view];
            [_nativeTextContexts setObject:native forKey:view];
        }
    }
    for (NSView *child in [view subviews]) [self _applyTextContrastToView:child force:force];
}

- (void) _textContrastChanged:(NSNotification *)note
{
    [self _applyTextContrastToView:_scaleView force:YES];
    [_scaleView setNeedsDisplay:YES];
}

- (NSColor *) _blushBackgroundColor
{
    if ([_borderIdentifier isEqualToString:WindowBorderCurrentTrack]) {
        return [InterfaceAppearance blushCurrentTrackColor];
    }
    if ([_borderIdentifier isEqualToString:WindowBorderMusicLibrary]) {
        return [InterfaceAppearance blushMusicLibraryColor];
    }
    return [InterfaceAppearance blushSetListColor];
}

- (void) _applyThemeToView:(NSView *)view color:(NSColor *)color enabled:(BOOL)enabled
{
    if ([view isKindOfClass:[NSScrollView class]]) {
        NSScrollView *scroll = (NSScrollView *)view;
        scroll.drawsBackground = enabled;
        if (enabled) scroll.backgroundColor = color;
    } else if ([view isKindOfClass:[NSClipView class]]) {
        NSClipView *clip = (NSClipView *)view;
        clip.drawsBackground = enabled;
        if (enabled) clip.backgroundColor = color;
    } else if ([view isKindOfClass:[NSTableView class]]) {
        NSTableView *table = (NSTableView *)view;
        if (enabled) table.backgroundColor = color;
        else table.backgroundColor = NSColor.controlBackgroundColor;
    }
    if ([view isKindOfClass:[NSTextView class]]) {
        NSTextView *text = (NSTextView *)view;
        if (enabled) {
            text.textColor = NSColor.blackColor;
            if (text.drawsBackground) text.backgroundColor = color;
        }
    }
    for (NSView *child in view.subviews) [self _applyThemeToView:child color:color enabled:enabled];
}

- (void) _applyTheme
{
    BOOL enabled = [[Preferences sharedInstance] themeType] == ThemeTypeBlush;
    NSColor *color = [self _blushBackgroundColor];
    _window.backgroundColor = enabled ? color : NSColor.windowBackgroundColor;
    for (NSView *view in @[_hostView, _scaleView]) {
        view.wantsLayer = YES;
        view.layer.backgroundColor = enabled ? color.CGColor : nil;
    }
    [self _applyThemeToView:_scaleView color:color enabled:enabled];
}

- (void) _applyPreferencesResizing:(BOOL)resize
{
    if (_updating) return;
    _updating = YES;
    NSWindow *window = _window;
    Preferences *preferences = [Preferences sharedInstance];
    CGFloat textScale = [preferences textSizePercent] / 100.0;
    BOOL scales = [preferences scalesInterfaceWithWindow];

    if (scales && !_scalesWithWindow) {
        _scaleView.designSize = [_scaleView.documentView bounds].size;
    }
    _scalesWithWindow = scales;
    _scaleView.scalesWithWindow = scales;
    _scaleView.textScale = textScale;

    BOOL fixedLayout = !_wasResizable || NSEqualSizes(_minimumSize, _maximumSize);
    NSSize minimum = NSMakeSize(MAX(_minimumSize.width, 240) * textScale,
                               MAX(_minimumSize.height, 80) * textScale);
    if (fixedLayout && !_allowsIndependentResizeAxes) {
        minimum = NSMakeSize(_scaleView.designSize.width * textScale, _scaleView.designSize.height * textScale);
    }
    NSSize windowMinimum = minimum;
    if (scales && _allowsIndependentResizeAxes) {
        // Window scaling can preserve the whole logical canvas below the text
        // preset's native size, so do not force a scroll view at that size.
        windowMinimum = NSMakeSize(MAX(_minimumSize.width, 240), MAX(_minimumSize.height, 80));
    }
    _scaledMinimum = windowMinimum;
    NSSize available = [window contentRectForFrameRect:[[window screen] visibleFrame]].size;
    if (available.width <= 0 || available.height <= 0) available = NSMakeSize(1440, 900);
    [window setContentMinSize:NSMakeSize(MIN(windowMinimum.width, available.width), MIN(windowMinimum.height, available.height))];
    [window setContentMaxSize:scales ? NSMakeSize(32768, 32768)
        : NSMakeSize(MIN(_maximumSize.width * textScale, 32768), MIN(_maximumSize.height * textScale, 32768))];
    if (scales && !_allowsIndependentResizeAxes) {
        if ([window styleMask] & NSWindowStyleMaskFullSizeContentView) {
            [window setContentResizeIncrements:NSMakeSize(1, 1)];
            [window setAspectRatio:_scaleView.designSize];
        } else {
            [window setContentAspectRatio:_scaleView.designSize];
        }
    } else if (_allowsIndependentResizeAxes) {
        [window setContentResizeIncrements:NSMakeSize(MAX(1, _originalResizeIncrements.width),
                                                      MAX(1, _originalResizeIncrements.height))];
    } else if (_originalAspectRatio.width > 0 && _originalAspectRatio.height > 0) {
        [window setContentAspectRatio:_originalAspectRatio];
    } else {
        // Cancel an aspect constraint using positive resize increments. A zero ratio is invalid.
        [window setContentResizeIncrements:NSMakeSize(MAX(1, _originalResizeIncrements.width), MAX(1, _originalResizeIncrements.height))];
    }
    NSWindowStyleMask mask = [window styleMask];
    if (scales && !(mask & NSWindowStyleMaskResizable)) {
        [window setStyleMask:mask | NSWindowStyleMaskResizable];
        _madeResizable = YES;
    } else if (!scales && _madeResizable) {
        [window setStyleMask:mask & ~NSWindowStyleMaskResizable];
        _madeResizable = NO;
    }

    if (resize) {
        NSSize size = [[window contentView] frame].size;
        CGFloat ratio = textScale / _textScale;
        size.width = MAX(windowMinimum.width, scales ? size.width * ratio : size.width);
        size.height = MAX(windowMinimum.height, size.height * ratio);
        if (fixedLayout && !scales) size = minimum;
        if (scales && !_allowsIndependentResizeAxes) {
            size.width = size.height * _scaleView.designSize.width / _scaleView.designSize.height;
        }
        [self _resizeWindowToSize:size];
    }
    _textScale = textScale;
    [self _viewportResized:nil];
    [self _applyBoldToView:_scaleView force:YES];
    [self _applyTextContrastToView:_scaleView force:YES];
    _updating = NO;
}

- (void) _preferencesChanged:(NSNotification *)note
{
    [self _applyTheme];
    [self _applyPreferencesResizing:YES];
    [_scaleView setNeedsDisplay:YES];
}
- (void) _windowUpdated:(NSNotification *)note
{
    if (_updating) return;
    _updating = YES;
    [self _applyBoldToView:_scaleView force:NO];
    [self _applyTextContrastToView:_scaleView force:NO];
    [self _applyTheme];
    [self _updateBorder:nil];
    _updating = NO;
}

- (void) _updateBorder:(NSNotification *)note
{
    if (!_borderIdentifier) return;
    if (!_borderView) {
        _borderView = [[InterfaceBorderView alloc] initWithFrame:NSZeroRect];
        _borderView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    NSView *root = [_window contentView];
    if (_borderView.superview != root) {
        [_borderView removeFromSuperview];
        [root addSubview:_borderView positioned:NSWindowAbove relativeTo:nil];
    }
    if (!NSEqualRects(_borderView.frame, root.bounds)) _borderView.frame = root.bounds;
    NSColor *color = [[Preferences sharedInstance] windowBorderColorForIdentifier:_borderIdentifier];
    if (_borderView.borderColor != color && ![_borderView.borderColor isEqual:color]) {
        _borderView.borderColor = color;
        _borderView.hidden = !color;
        _borderView.needsDisplay = YES;
    }
}
- (void) _screenChanged:(NSNotification *)note { [self _applyPreferencesResizing:YES]; }

- (NSString *) _windowStateKey
{
    NSString *name = [_window frameAutosaveName];
    if (!name.length) name = NSStringFromClass([[_window windowController] class]) ?: @"Window";
    return [@"InterfaceDesignSize." stringByAppendingString:name];
}

- (void) _saveWindowState:(NSNotification *)note
{
    if (_scalesWithWindow) {
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromSize(_scaleView.designSize) forKey:[self _windowStateKey]];
    }
}

- (void) _viewportResized:(NSNotification *)note
{
    if (_layingOut) return;
    _layingOut = YES;
    BOOL createdViewport = NO;
    NSSize size = [[_window contentView] frame].size;
    BOOL needsScroll = size.width + 1 < _scaledMinimum.width || size.height + 1 < _scaledMinimum.height;
    if (needsScroll && !_viewport) {
        _viewport = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
        _viewport.wantsLayer = YES;
        _viewport.drawsBackground = NO;
        _viewport.borderType = NSNoBorder;
        _viewport.hasHorizontalScroller = YES;
        _viewport.hasVerticalScroller = YES;
        _viewport.autohidesScrollers = YES;
        [_scaleView removeFromSuperview];
        _scaleView.autoresizingMask = 0;
        [_window setContentView:_viewport];
        _viewport.documentView = _scaleView;
        createdViewport = YES;
        [_viewport.contentView setPostsFrameChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_viewportResized:) name:NSViewFrameDidChangeNotification object:_viewport.contentView];
    } else if (!needsScroll && _viewport) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:_viewport.contentView];
        _viewport.documentView = nil;
        [_window setContentView:_hostView];
        [_scaleView setFrameOrigin:NSZeroPoint];
        _scaleView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_hostView addSubview:_scaleView];
        _viewport = nil;
    }
    if (_viewport) size = [_viewport.contentView bounds].size;
    size.width = MAX(size.width, _scaledMinimum.width);
    size.height = MAX(size.height, _scaledMinimum.height);
    [_scaleView setFrameSize:size];
    if (createdViewport) {
        CGFloat top = MAX(0, NSHeight(_scaleView.frame) - NSHeight(_viewport.contentView.bounds));
        [_viewport.contentView scrollToPoint:NSMakePoint(0, top)];
        [_viewport reflectScrolledClipView:_viewport.contentView];
    }
    _layingOut = NO;
}

- (void) _refreshGeometryAfterWindowFrameChange
{
    if (!_window) return;
    NSView *root = [_window contentView];
    [root setNeedsLayout:YES];
    [root layoutSubtreeIfNeeded];
    [self _viewportResized:nil];
    [_scaleView updateGeometry];
    [_scaleView.documentView setNeedsLayout:YES];
    [_scaleView.documentView layoutSubtreeIfNeeded];
    [self _updateBorder:nil];
    [_window displayIfNeeded];
}

- (void) _resizeWindowToSize:(NSSize)size
{
    NSWindow *window = _window;
    NSRect frame = [window frame];
    NSSize content = [[window contentView] frame].size;
    frame.size.width += size.width - content.width;
    frame.size.height += size.height - content.height;
    frame.origin.y += [window frame].size.height - frame.size.height;
    NSRect screen = [[window screen] visibleFrame];
    if (!NSIsEmptyRect(screen)) {
        frame.size.width = MIN(frame.size.width, screen.size.width);
        frame.size.height = MIN(frame.size.height, screen.size.height);
        frame.origin.x = MAX(NSMinX(screen), MIN(frame.origin.x, NSMaxX(screen) - frame.size.width));
        frame.origin.y = MAX(NSMinY(screen), MIN(frame.origin.y, NSMaxY(screen) - frame.size.height));
    }
    [window setFrame:frame display:YES];
    [self _refreshGeometryAfterWindowFrameChange];
}
@end
