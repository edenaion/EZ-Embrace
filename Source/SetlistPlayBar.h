// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Cocoa/Cocoa.h>
#import "PlaybackSeekView.h"


@interface SetlistPlayBar : PlaybackSeekView <EmbraceWindowListener>

@property (nonatomic, getter=isPlaying) BOOL playing;

@end
