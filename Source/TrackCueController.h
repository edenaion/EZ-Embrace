#import <Cocoa/Cocoa.h>

@class Track;

@interface TrackCueButton : NSButton
@property (nonatomic) BOOL cueActive;
@end

@interface TrackCueController : NSViewController
+ (NSPopover *) showForTrack:(Track *)track relativeToView:(NSView *)view;
@end
