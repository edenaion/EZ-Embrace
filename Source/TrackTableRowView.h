// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

@class Track;

@interface TrackTableRowView : NSTableRowView
@property (nonatomic, getter=isPlaying) BOOL playing;
@property (nonatomic) BOOL endsLastPlayedTrack;
@property (nonatomic) BOOL highlightsUpcomingOtherGenre;
@property (nonatomic, readonly) BOOL drawsUpcomingOtherGenreHighlight;

@end
