// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "EditGraphicEQEffectController.h"
#import "InterfaceAppearance.h"
#import "Effect.h"
#import "EffectAdditions.h"
#import "EffectType.h"
#import "GraphicEQView.h"

#import <AudioUnit/AUCocoaUIView.h>

@interface EditGraphicEQEffectController ()

@property (nonatomic, weak) IBOutlet NSVisualEffectView *backgroundView;
@property (nonatomic, weak) IBOutlet GraphicEQView *graphicEQView;

@end


@implementation EditGraphicEQEffectController

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (NSString *) windowNibName
{
    return @"EditGraphicEQEffectWindow";
}


- (void) windowDidLoad
{
    [super windowDidLoad];

    [_graphicEQView setAudioUnit:[[self effect] audioUnit]];
   
    CGSize contentSize = CGSizeMake(
        [_graphicEQView numberOfBands] == 10 ? 362 : 765,
        215
    );

    NSWindow *window = [self window];
    [window setContentMinSize:contentSize];
    [window setContentMaxSize:contentSize];
    [window setMovableByWindowBackground:YES];
    [window setTitleVisibility:NSWindowTitleHidden];
    [window setTitlebarAppearsTransparent:YES];

    CGRect rect = [window contentRectForFrameRect:[window frame]];
    rect.size = contentSize;
    rect = [window frameRectForContentRect:rect];

    [window setFrame:rect display:YES animate:NO];
    
    // Adjust subviews (we can't do this in Interface Builder as the NSVisualEffectView
    // obscures the toolbar
    //
    [self moveToolbarControlsIntoContentView];
    [[self backgroundView] setFrame:[[window contentView] bounds]];

    CGRect eqViewFrame = [[self backgroundView] bounds];
    eqViewFrame.size.height -= 34;
    [[self graphicEQView] setFrame:eqViewFrame];
    [InterfaceAppearance installInWindow:window];
}


- (void) reloadData
{
    [super reloadData];
    [_graphicEQView reloadData];
}


#pragma mark - IBActions

- (IBAction) flatten:(id)sender
{
    [_graphicEQView flatten];
    [super reloadData];
}


@end
