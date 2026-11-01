// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "EditSystemEffectController.h"
#import "InterfaceAppearance.h"
#import "Effect.h"
#import "EffectAdditions.h"
#import "EffectType.h"
#import "ParametricEQView.h"
#import "ParameterFormView.h"
#import "Player.h"
#import <objc/runtime.h>

#import <CoreAudioKit/CoreAudioKit.h>

NSNotificationName const EditSystemEffectControllerDidLoadViewNotification = @"EditSystemEffectControllerDidLoadViewNotification";

@implementation EditSystemEffectController {
    NSView *_effectView;
    NSViewController *_effectViewController;
    ParameterFormView *_parameterFormView;
    BOOL _inViewFrameCallback;
}


- (NSString *) windowNibName
{
    return @"EditSystemEffectWindow";
}


- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (void) windowDidLoad
{
    [super windowDidLoad];
    [self moveToolbarControlsIntoContentView];

    Effect *effect = [self effect];
    if (!effect) return;

    if (![[effect audioUnit] providesUserInterface]) {
        _parameterFormView = [[ParameterFormView alloc] initWithAudioUnit:[effect audioUnit]];
        NSViewController *viewController = [[NSViewController alloc] init];
        [viewController setView:_parameterFormView];

        __weak id weakFormSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakFormSelf _didReceiveViewController:viewController];
        });
        return;
    }

    __weak id weakSelf = self;

    [[effect audioUnit] requestViewControllerWithCompletionHandler:^(AUViewControllerBase *viewController) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf _didReceiveViewController:viewController];
        });
    }];
}


#pragma mark - Private Methods

- (void) _didReceiveViewController:(NSViewController *)vc
{
    if (!vc || ![vc view] || ![self effect]) return;
    NSWindow *window = [self window];

    NSRect contentLayoutRect = [window contentLayoutRect];
    contentLayoutRect.size.height -= 36;
        
    NSViewController *contentViewController = [self contentViewController];
    
    [contentViewController addChildViewController:vc];
    
    NSView *effectView = [vc view];
    _effectView = effectView;
    _effectViewController = vc;
    BOOL isParametricEQ = [effectView isKindOfClass:[ParametricEQView class]];

    if (isParametricEQ) {
        ((ParametricEQView *)effectView).setEQEnabled = ^(BOOL enabled) {
            if (![Player.sharedInstance setParametricEQEnabled:enabled]) NSBeep();
        };
        [effectView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    }
    
    NSRect effectViewFrame = [_effectView frame];

    NSRect newWindowFrame = [window frame];
    newWindowFrame.size.width  += (effectViewFrame.size.width  - contentLayoutRect.size.width);
    newWindowFrame.size.height += (effectViewFrame.size.height - contentLayoutRect.size.height);

    NSAutoresizingMaskOptions oldAutoresizingMask = [_effectView autoresizingMask];
    
    if ((oldAutoresizingMask & (NSViewWidthSizable|NSViewHeightSizable)) == 0) {
        NSWindowStyleMask styleMask = [[self window] styleMask];
        styleMask &= ~NSWindowStyleMaskResizable;
        [window setStyleMask:styleMask];
    }   
    
    [_effectView setAutoresizingMask:0];
    [window setFrame:newWindowFrame display:NO animate:NO];

    NSRect editorFrame = [window contentLayoutRect];
    editorFrame.size.height -= 36;
    [_effectView setFrame:editorFrame];
    [_effectView setAutoresizingMask:oldAutoresizingMask];

    [[[self window] contentView] addSubview:_effectView];

    [self _tweakView:_effectView];

    if (isParametricEQ) {
        // The custom editor uses a fixed logical canvas which scales into this
        // smaller native window. The toolbar remains at a normal readable size.
        [window setContentMinSize:NSMakeSize(400, 200)];
    }

    [InterfaceAppearance installInWindow:window];
    if (isParametricEQ) [InterfaceAppearance setAllowsIndependentResizeAxes:YES inWindow:window];

    if (!isParametricEQ) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleViewFrameDidChange:) name:NSViewFrameDidChangeNotification object:_effectView];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:EditSystemEffectControllerDidLoadViewNotification object:self];
}


- (void) _tweakView:(NSView *)view
{
    Class AppleAUCustomViewBase   = NSClassFromString(@"AppleAUCustomViewBase");
    Class CAAppleAUCustomViewBase = NSClassFromString(@"CAAppleAUCustomViewBase");

    if ((  AppleAUCustomViewBase && [view isKindOfClass:  AppleAUCustomViewBase]) ||
        (CAAppleAUCustomViewBase && [view isKindOfClass:CAAppleAUCustomViewBase]))
    {
        for (NSView *subview in [view subviews]) {
            if ([subview isKindOfClass:[NSTextField class]]) {
                if ([[(NSTextField *)subview font] pointSize] >= 16) {
                    [subview setHidden:YES];
                }
            }
        }
    }
}


- (void) reloadData
{
    [super reloadData];
    [_parameterFormView reloadData];
    if ([_effectView isKindOfClass:[ParametricEQView class]]) [(ParametricEQView *)_effectView reloadData];
}


- (IBAction) flatten:(id)sender
{
    if ([_effectView isKindOfClass:[ParametricEQView class]]) [(ParametricEQView *)_effectView flatten];
    [super reloadData];
}


- (void) _handleViewFrameDidChange:(NSNotification *)note
{
    if (!_inViewFrameCallback && ![[self window] inLiveResize]) {
        _inViewFrameCallback = YES;

        NSRect contentLayoutRect = [[InterfaceAppearance contentViewForWindow:[self window]] bounds];
        contentLayoutRect.size.height -= 36;
        NSRect effectViewFrame   = [_effectView frame];

        if (fabs(contentLayoutRect.size.width - effectViewFrame.size.width) > 0.5 ||
            fabs(contentLayoutRect.size.height - effectViewFrame.size.height) > 0.5) {
            [InterfaceAppearance setContentSize:NSMakeSize(effectViewFrame.size.width, effectViewFrame.size.height + 36) inWindow:[self window]];
        }

        _inViewFrameCallback = NO;
    }
}

@end
