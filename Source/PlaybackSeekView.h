#import <Cocoa/Cocoa.h>

@class Track;

// Shared interaction for the playback bar and current-track waveform.
@interface PlaybackSeekView : NSView
@property (nonatomic) float percentage;
- (Track *) seekTrack;
- (void) seekPercentageDidChange;
@end
