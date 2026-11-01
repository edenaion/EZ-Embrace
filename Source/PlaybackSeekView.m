#import "PlaybackSeekView.h"
#import "Player.h"
#import "Track.h"

@implementation PlaybackSeekView {
    BOOL _trackingSeek;
}

- (Track *) seekTrack
{
    Track *track = [[Player sharedInstance] currentTrack];
    return [track didAnalyzeLoudness] && [track playDuration] > 0 ? track : nil;
}

- (BOOL) acceptsFirstResponder { return [self seekTrack] != nil; }
- (BOOL) mouseDownCanMoveWindow { return NO; }
- (BOOL) acceptsFirstMouse:(NSEvent *)event { return YES; }

- (NSView *) hitTest:(NSPoint)point
{
    return [super hitTest:point] ? self : nil;
}

- (void) resetCursorRects
{
    if ([self seekTrack]) [self addCursorRect:[self bounds] cursor:[NSCursor pointingHandCursor]];
}

- (void) _previewEvent:(NSEvent *)event
{
    NSRect bounds = [self bounds];
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    _percentage = bounds.size.width > 0 ? MIN(MAX(0, (point.x - NSMinX(bounds)) / bounds.size.width), 1) : 0;
    [self seekPercentageDidChange];
}

- (void) mouseDown:(NSEvent *)event
{
    Track *track = [self seekTrack];
    if (!track) return;
    [[self window] makeFirstResponder:self];
    _trackingSeek = YES;
    BOOL cancelled = NO;
    [self _previewEvent:event];

    while (YES) {
        NSEvent *next = [[self window] nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp | NSEventMaskKeyDown
            untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
        if (!next || ([next type] == NSEventTypeKeyDown && [next keyCode] == 53)) {
            cancelled = YES;
            break;
        }
        if ([next type] == NSEventTypeKeyDown) continue;
        [self _previewEvent:next];
        if ([next type] == NSEventTypeLeftMouseUp) break;
    }

    _trackingSeek = NO;
    if (!cancelled) [[Player sharedInstance] seekToTime:_percentage * [track playDuration] forTrack:track];
    [self setPercentage:[[Player sharedInstance] percentage]];
}

- (void) keyDown:(NSEvent *)event
{
    if ([event modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) {
        [super keyDown:event];
        return;
    }
    Track *track = [self seekTrack];
    if (!track) { [super keyDown:event]; return; }
    NSTimeInterval time = [[Player sharedInstance] timeElapsed];
    NSTimeInterval step = ([event modifierFlags] & NSEventModifierFlagShift) ? 15 : 5;
    switch ([event keyCode]) {
        case 123: time -= step; break;
        case 124: time += step; break;
        case 115: time = 0; break;
        case 119: time = [track playDuration]; break;
        default: [super keyDown:event]; return;
    }
    [[Player sharedInstance] seekToTime:time forTrack:track];
}

- (void) setPercentage:(float)percentage
{
    if (_trackingSeek) return;
    percentage = isfinite(percentage) ? MIN(MAX(percentage, 0), 1) : 0;
    if (_percentage == percentage) return;
    _percentage = percentage;
    [self seekPercentageDidChange];
}

- (void) seekPercentageDidChange { [self setNeedsDisplay:YES]; }

- (BOOL) isAccessibilityElement { return YES; }
- (NSString *) accessibilityRole { return NSAccessibilitySliderRole; }
- (NSString *) accessibilityLabel { return @"Playback position"; }
- (NSString *) accessibilityHelp { return @"Click or drag to seek. Use Left and Right Arrow for 5 seconds, or Shift for 15 seconds."; }
- (id) accessibilityValue { return @([self percentage] * 100); }
- (id) accessibilityMinValue { return @0; }
- (id) accessibilityMaxValue { return @100; }
- (BOOL) isAccessibilityEnabled { return [self seekTrack] != nil; }
- (BOOL) isAccessibilitySelectorAllowed:(SEL)selector
{
    if (selector == @selector(setAccessibilityValue:)) return [self seekTrack] != nil;
    return [super isAccessibilitySelectorAllowed:selector];
}
- (void) setAccessibilityValue:(id)value
{
    if (![value respondsToSelector:@selector(doubleValue)]) return;
    Track *track = [self seekTrack];
    [[Player sharedInstance] seekToTime:[value doubleValue] * [track playDuration] / 100 forTrack:track];
}
- (BOOL) accessibilityPerformIncrement
{
    return [[Player sharedInstance] seekToTime:[[Player sharedInstance] timeElapsed] + 5 forTrack:[self seekTrack]];
}
- (BOOL) accessibilityPerformDecrement
{
    return [[Player sharedInstance] seekToTime:[[Player sharedInstance] timeElapsed] - 5 forTrack:[self seekTrack]];
}
@end
