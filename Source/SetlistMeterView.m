// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "SetlistMeterView.h"
#import "HugMeterData.h"

static double sDecibels(float level)
{
    return isfinite(level) && level > 0 ? MAX(-60, MIN(0, 20 * log10(level))) : -60;
}

@interface SetlistLevelBar : NSView
@property (nonatomic, strong) HugMeterData *meterData;
@property (nonatomic, copy) NSString *channelName;
@end

@implementation SetlistLevelBar

- (void) setMeterData:(HugMeterData *)meterData
{
    if ([_meterData isEqual:meterData] || _meterData == meterData) return;
    _meterData = meterData;
    [self setNeedsDisplay:YES];
}

- (void) drawRect:(NSRect)dirtyRect
{
    NSRect bounds = NSInsetRect([self bounds], 1, 0);
    CGFloat barWidth = MAX(0, bounds.size.width - 8);
    NSInteger segments = MAX(1, floor(barWidth / 5));
    CGFloat segmentWidth = barWidth / segments;
    CGFloat fraction = (sDecibels([_meterData peakLevel]) + 60) / 60;
    NSInteger filled = ceil(fraction * segments);
    for (NSInteger i = 0; i < segments; i++) {
        double decibels = -60 + 60.0 * (i + 1) / segments;
        NSColor *color = [NSColor separatorColor];
        if (i < filled) {
            color = decibels <= -12 ? [NSColor systemGreenColor] :
                decibels < -3 ? [NSColor systemOrangeColor] : [NSColor systemRedColor];
        }
        [color set];
        NSRect segment = NSMakeRect(bounds.origin.x + i * segmentWidth, bounds.origin.y, MAX(0, segmentWidth - 1), bounds.size.height);
        [[NSBezierPath bezierPathWithRoundedRect:segment xRadius:1 yRadius:1] fill];
    }
    if ([_meterData heldLevel] > 0) {
        CGFloat held = (sDecibels([_meterData heldLevel]) + 60) / 60;
        [[NSColor labelColor] set];
        NSRectFill(NSMakeRect(bounds.origin.x + MAX(0, MIN(barWidth - 2, held * barWidth)), bounds.origin.y, 2, bounds.size.height));
    }
    BOOL overloaded = [_meterData isLimiterActive] || [_meterData peakLevel] >= 1 || !isfinite([_meterData peakLevel]);
    [(overloaded ? [NSColor systemRedColor] : [NSColor separatorColor]) set];
    CGFloat dot = MIN(6, bounds.size.height);
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMaxX(bounds) - dot, NSMidY(bounds) - dot / 2, dot, dot)] fill];
}

- (BOOL) isAccessibilityElement { return YES; }
- (NSString *) accessibilityRole { return NSAccessibilityLevelIndicatorRole; }
- (NSString *) accessibilityLabel { return _channelName; }
- (id) accessibilityValue { return @(sDecibels([_meterData peakLevel])); }
- (id) accessibilityMinValue { return @(-60); }
- (id) accessibilityMaxValue { return @0; }
- (NSString *) accessibilityValueDescription
{
    NSString *level = [_meterData peakLevel] > 0 ? [NSString stringWithFormat:@"%.1f dBFS", sDecibels([_meterData peakLevel])] : NSLocalizedString(@"Silence", nil);
    return [_meterData isLimiterActive] || [_meterData peakLevel] >= 1 ?
        [level stringByAppendingString:NSLocalizedString(@", overload or safety limiter active", nil)] : level;
}
@end

@implementation SetlistMeterView {
    SetlistLevelBar *_leftChannelBar;
    SetlistLevelBar *_rightChannelBar;
}

+ (NSColor *) colorForPeakLevel:(float)peak limiterActive:(BOOL)limiterActive
{
    if (limiterActive || !isfinite(peak) || peak >= pow(10, -3.0 / 20)) return [NSColor systemRedColor];
    if (peak >= pow(10, -12.0 / 20)) return [NSColor systemOrangeColor];
    return [NSColor systemGreenColor];
}

- (instancetype) initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) [self _commonLevelMeterInit];
    return self;
}

- (instancetype) initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) [self _commonLevelMeterInit];
    return self;
}

- (void) _commonLevelMeterInit
{
    [self setAutoresizesSubviews:NO];
    _leftChannelBar = [[SetlistLevelBar alloc] initWithFrame:NSZeroRect];
    _rightChannelBar = [[SetlistLevelBar alloc] initWithFrame:NSZeroRect];
    [_leftChannelBar setChannelName:NSLocalizedString(@"Left output level", nil)];
    [_rightChannelBar setChannelName:NSLocalizedString(@"Right output level", nil)];
    NSString *help = NSLocalizedString(@"Output peaks in dBFS. Green below -12 dBFS; amber from -12 to -3 dBFS; red near 0 dBFS. The separate red dot indicates overload or safety limiter activity.", nil);
    [self setToolTip:help];
    [_leftChannelBar setToolTip:help];
    [_rightChannelBar setToolTip:help];
    [self addSubview:_leftChannelBar];
    [self addSubview:_rightChannelBar];
}

- (void) layout
{
    [super layout];
    CGFloat height = MAX(1, ([self bounds].size.height - 2) / 2);
    [_leftChannelBar setFrame:NSMakeRect(0, height + 2, [self bounds].size.width, height)];
    [_rightChannelBar setFrame:NSMakeRect(0, 0, [self bounds].size.width, height)];
}

- (void) windowDidUpdateMain:(EmbraceWindow *)window
{
    [_leftChannelBar setNeedsDisplay:YES];
    [_rightChannelBar setNeedsDisplay:YES];
}

- (void) setLeftMeterData:(HugMeterData *)leftMeterData rightMeterData:(HugMeterData *)rightMeterData
{
    _leftMeterData = leftMeterData;
    _rightMeterData = rightMeterData;
    [_leftChannelBar setMeterData:leftMeterData];
    [_rightChannelBar setMeterData:rightMeterData];
}

- (void) setMetering:(BOOL)metering
{
    if (_metering == metering) return;
    _metering = metering;
    [self setLeftMeterData:nil rightMeterData:nil];
}
@end
