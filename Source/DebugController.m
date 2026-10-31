// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#if DEBUG

#import "DebugController.h"
#import "InterfaceAppearance.h"
#import "Player.h"
#import "SetlistController.h"
#import "AppDelegate.h"
#import "Track.h"
#import "WrappedUtils.h"

@interface DebugController ()

@end


@implementation DebugController

- (NSString *) windowNibName
{
    return @"DebugWindow";
}

- (void) windowDidLoad
{
    [super windowDidLoad];
    [InterfaceAppearance installInWindow:[self window]];
}


- (SetlistController *) _setlistController
{
    return [GetAppDelegate() valueForKey:@"setlistController"];
}


- (IBAction) populatePlaylist:(id)sender
{
    NSInteger tag = [sender selectedTag];

    NSMutableArray *fileURLs = [NSMutableArray array];

    void (^add)(NSString *) = ^(NSString *name) {
        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"m4a"];
        NSURL *result = [NSURL fileURLWithPath:path];
        if (result) [fileURLs addObject:result];
    };
    
    if (tag == 0) {
        add(@"test_c");
        add(@"test_d");
        add(@"test_e");
        add(@"test_f");
        add(@"test_g");

    } else if (tag == 1) {
        add(@"test_3s_c4");
        add(@"test_3s_d4");
        add(@"test_3s_e4");
        add(@"test_3s_f4");
        add(@"test_3s_g4");
        
    } else if (tag == 2) {
        add(@"rate_44");
        add(@"rate_44");
        add(@"rate_48");
        add(@"rate_88");
        add(@"rate_96");
        add(@"rate_88");
        add(@"rate_48");
        add(@"rate_44");
    }

    [[self _setlistController] clear];
    [[self _setlistController] addTracksWithURLs:fileURLs];
}


- (IBAction) playPauseLoop:(id)sender
{
    static NSTimer *playPauseTimer = nil;
    if (!playPauseTimer) {
        [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(debugPlayPauseTick:) userInfo:nil repeats:YES];
    }
}


- (IBAction) showIssueDialog:(id)sender
{
    NSInteger tag = [sender selectedTag];
    [[self _setlistController] showAlertForIssue:tag];
}


- (void) debugPlayPauseTick:(NSTimer *)timer
{
    Player *player = [Player sharedInstance];

    if ([player isPlaying]) {
        Track *track = [player currentTrack];
        [player hardStop];
        [track setTrackStatus:TrackStatusQueued];

    } else {
        [player play];
    }
}


- (IBAction) explode:(id)sender
{
#ifndef __clang_analyzer__
    NSInteger tag = [sender selectedTag];
    
    NSInteger action = tag % 3;
    NSInteger thread = tag / 3;
    
    dispatch_queue_t q = thread == 0 ? dispatch_get_main_queue() : dispatch_get_global_queue(0, 0);
    
    
    dispatch_async(q, ^{
        if (action == 0) {
            RaiseException();
            
        } else if (action == 1) {
            [[NSException exceptionWithName:@"Debug Exception" reason:@"Debug Exception" userInfo:nil] raise];

        } else if (action == 2) {
            for (NSInteger i = 0; i < 4096; i++) {
                int *moo = (int *)i;
                *moo = 0xdeadbeef;
            }
        }
    });
#endif
}


@end

#endif
