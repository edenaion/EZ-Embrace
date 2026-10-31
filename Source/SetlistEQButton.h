#import "EQStateButton.h"

@class Player;

@interface SetlistEQButton : EQStateButton
// Uses the existing summary row without changing window or header geometry.
+ (instancetype) buttonUnderMenu:(NSButton *)menu besideSummary:(NSTextField *)summary player:(Player *)player;
- (instancetype) initWithFrame:(NSRect)frame player:(Player *)player;
- (instancetype) initWithFrame:(NSRect)frame NS_UNAVAILABLE;
@end
