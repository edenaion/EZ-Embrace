// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "TrackTableRowView.h"
#import "TrackTableView.h"
#import "Preferences.h"
#import "InterfaceAppearance.h"


@implementation TrackTableRowView

- (void) setPlaying:(BOOL)playing
{
    if (_playing == playing) return;
    _playing = playing;
    [self setNeedsDisplay:YES];
}

- (void) setEndsLastPlayedTrack:(BOOL)endsLastPlayedTrack
{
    if (_endsLastPlayedTrack == endsLastPlayedTrack) return;
    _endsLastPlayedTrack = endsLastPlayedTrack;
    [self setNeedsDisplay:YES];
}

- (void) setHighlightsUpcomingOtherGenre:(BOOL)highlightsUpcomingOtherGenre
{
    if (_highlightsUpcomingOtherGenre == highlightsUpcomingOtherGenre) return;
    _highlightsUpcomingOtherGenre = highlightsUpcomingOtherGenre;
    [self setNeedsDisplay:YES];
}

- (BOOL) drawsUpcomingOtherGenreHighlight
{
    return _highlightsUpcomingOtherGenre && !_trackColorOverride && !self.isSelected;
}

- (void) setTrackColorOverride:(NSColor *)trackColorOverride
{
    if ((_trackColorOverride == trackColorOverride) || [_trackColorOverride isEqual:trackColorOverride]) return;
    _trackColorOverride = [trackColorOverride copy];
    [self setNeedsDisplay:YES];
}

- (BOOL) drawsTrackColorOverride
{
    return _trackColorOverride && !self.isSelected;
}

- (void) drawBackgroundInRect:(NSRect)dirtyRect
{
    [super drawBackgroundInRect:dirtyRect];
    if ([[Preferences sharedInstance] themeType] == ThemeTypeBlush) {
        NSColor *pink = [InterfaceAppearance blushSetListColor];
        [pink set];
        NSRectFill(self.bounds);
    }
    if (self.drawsUpcomingOtherGenreHighlight) {
        [[[Preferences sharedInstance] upcomingOtherGenreColor] set];
        NSRectFill(self.bounds);
    }
    if (self.drawsTrackColorOverride) {
        [_trackColorOverride set];
        NSRectFill(self.bounds);
    }
    if (!_playing || [self isSelected]) return;
    NSRectClip(dirtyRect);
    [[[NSColor controlAccentColor] colorWithAlphaComponent:0.20] set];
    NSRectFill([self bounds]);
    [[NSColor controlAccentColor] set];
    NSRect stripe = [self bounds];
    stripe.size.width = 4;
    NSRectFill(stripe);
}


- (void) drawSelectionInRect:(NSRect)dirtyRect
{
    BOOL emphasized = ([self interiorBackgroundStyle] == NSBackgroundStyleEmphasized);

    [TrackTableViewGetRowHighlightColor(emphasized) set];

    NSRectFillUsingOperation([self bounds], NSCompositingOperationSourceOver);
}


- (void) drawSeparatorInRect:(NSRect)dirtyRect
{
    CGFloat scale = [[self window] backingScaleFactor];
    if (!scale) scale = 1;

    NSRectClip(dirtyRect);

    if (![self isSelected]) {
        CGFloat onePixel = 1.0 / scale;
        CGRect rect = [self bounds];
        rect.origin.y = rect.size.height - onePixel;
        rect.size.height = onePixel;

        NSColor *separator = [[Preferences sharedInstance] themeType] == ThemeTypeBlush
            ? [NSColor colorWithSRGBRed:0.91 green:0.72 blue:0.79 alpha:0.55]
            : [NSColor colorNamed:@"SetlistSeparator"];
        [separator set];
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    }

    if (_endsLastPlayedTrack) {
        CGFloat thickness = 2.0;
        CGRect divider = [self bounds];
        divider.origin.y = [self isFlipped] ? NSMaxY([self bounds]) - thickness : NSMinY([self bounds]);
        divider.size.height = thickness;

        [[[NSColor labelColor] colorWithAlphaComponent:0.62] set];
        NSRectFillUsingOperation(divider, NSCompositingOperationSourceOver);
    }
}


@end
