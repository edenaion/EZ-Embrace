// (c) 2026 EmbraceNG contributors
// MIT License (or) 1-clause BSD License

// Prefix.pch defines `auto` as __auto_type for the Objective-C sources.  This is
// Objective-C++, where libc++ needs `auto` to mean what C++ says it means.
#undef auto

#import "ParametricEQView.h"
#import "EQStateButton.h"
#import "ParametricEQAudioUnit.h"
#import "EffectParameterDescribing.h"    // ParameterDescribing

#import <AVFoundation/AVFoundation.h>

#include <cmath>
#include <vector>


static const CGFloat sMargin        = 20;
static const CGFloat sColumnWidth   = 52;
static const CGFloat sSectionGap    = 12;

static const CGFloat sCurveHeight   = 132;
static const CGFloat sCurveGap      = 16;

static const CGFloat sTitleHeight   = 13;
static const CGFloat sLabelHeight   = 12;
static const CGFloat sKnobRowHeight = 42;
static const CGFloat sValueHeight   = 14;
static const CGFloat sSwitchHeight  = 21;

static const CGFloat sLargeKnob     = 40;
static const CGFloat sSmallKnob     = 30;

// Pixels of vertical drag for the full range of a knob.  Roughly the height of
// the window, which is the distance a hand expects to move for "all of it".
static const CGFloat sDragTravel    = 170;

static const double  sCurveMinHz    = 20.0;
static const double  sCurveMaxHz    = 20000.0;
static const double  sCurveMaxDb    = 24.0;
static char sBypassObservationContext;


static double sClamp(double v, double lo, double hi)
{
    return v < lo ? lo : (v > hi ? hi : v);
}


#pragma mark - Knob

@interface ParametricEQKnob : NSControl

@property (nonatomic) double minValue;
@property (nonatomic) double maxValue;
@property (nonatomic) double defaultValue;
@property (nonatomic) BOOL   logarithmic;
@property (nonatomic) BOOL   bipolar;

@end


@implementation ParametricEQKnob {
    double  _value;
    double  _dragStartValue;
    CGFloat _dragStartY;
}


- (instancetype) initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
        _minValue = 0;
        _maxValue = 1;
        [self setContinuous:YES];
    }

    return self;
}


- (double) doubleValue        { return _value; }
- (void) setDoubleValue:(double)v
{
    double clamped = sClamp(v, _minValue, _maxValue);

    if (clamped != _value) {
        _value = clamped;
        [self setNeedsDisplay:YES];
    }
}


#pragma mark - Scale

// A frequency knob has to be logarithmic or its whole bottom half is unusable:
// on a linear 1.5-16 kHz sweep, everything below 3 kHz lives in the first tenth
// of the travel.
//
- (double) _normalizedFromValue:(double)value
{
    if (_logarithmic && _minValue > 0 && _maxValue > _minValue) {
        return log(value / _minValue) / log(_maxValue / _minValue);
    }

    if (_maxValue <= _minValue) return 0;

    return (value - _minValue) / (_maxValue - _minValue);
}


- (double) _valueFromNormalized:(double)normalized
{
    normalized = sClamp(normalized, 0, 1);

    if (_logarithmic && _minValue > 0 && _maxValue > _minValue) {
        return _minValue * pow(_maxValue / _minValue, normalized);
    }

    return _minValue + (normalized * (_maxValue - _minValue));
}


#pragma mark - Drawing

// Minimum at 7:30, maximum at 4:30, 270 degrees of clockwise travel through
// straight up.  NSBezierPath measures counter-clockwise from the positive x
// axis, hence the subtraction.
static CGFloat sAngleForNormalized(double normalized)
{
    return (CGFloat)(225.0 - (270.0 * normalized));
}


- (void) drawRect:(NSRect)dirtyRect
{
    CGRect  bounds = [self bounds];
    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGFloat radius = (MIN(bounds.size.width, bounds.size.height) / 2) - 3;

    if (radius <= 2) return;

    double  normalized = [self _normalizedFromValue:_value];
    CGFloat angle      = sAngleForNormalized(normalized);
    double  originN    = _bipolar ? 0.5 : 0.0;

    NSBezierPath *track = [NSBezierPath bezierPath];
    [track appendBezierPathWithArcWithCenter:center radius:radius
                                  startAngle:sAngleForNormalized(0)
                                    endAngle:sAngleForNormalized(1)
                                   clockwise:YES];
    [track setLineWidth:3];
    [track setLineCapStyle:NSLineCapStyleRound];
    [[NSColor tertiaryLabelColor] set];
    [track stroke];

    if (fabs(normalized - originN) > 0.0005) {
        NSBezierPath *filled = [NSBezierPath bezierPath];
        [filled appendBezierPathWithArcWithCenter:center radius:radius
                                       startAngle:sAngleForNormalized(originN)
                                         endAngle:angle
                                        clockwise:(normalized > originN)];
        [filled setLineWidth:3];
        [filled setLineCapStyle:NSLineCapStyleRound];
        [[NSColor controlAccentColor] set];
        [filled stroke];
    }

    CGFloat radians = (CGFloat)(angle * M_PI / 180.0);
    CGFloat dx = cos(radians), dy = sin(radians);

    NSBezierPath *pointer = [NSBezierPath bezierPath];
    [pointer moveToPoint:CGPointMake(center.x + (dx * radius * 0.30),
                                     center.y + (dy * radius * 0.30))];
    [pointer lineToPoint:CGPointMake(center.x + (dx * (radius - 1)),
                                     center.y + (dy * (radius - 1)))];
    [pointer setLineWidth:2];
    [pointer setLineCapStyle:NSLineCapStyleRound];
    [[NSColor labelColor] set];
    [pointer stroke];

    if ([[self window] firstResponder] == self && [[self window] isKeyWindow]) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 1, 1)];
        [ring setLineWidth:2];
        [[NSColor keyboardFocusIndicatorColor] set];
        [ring stroke];
    }
}


#pragma mark - Interaction

- (BOOL) acceptsFirstResponder { return YES; }
- (BOOL) becomeFirstResponder  { [self setNeedsDisplay:YES]; return YES; }
- (BOOL) resignFirstResponder  { [self setNeedsDisplay:YES]; return YES; }


- (void) _commitNormalized:(double)normalized
{
    [self setDoubleValue:[self _valueFromNormalized:normalized]];
    [self sendAction:[self action] to:[self target]];
}


// No nested tracking loop: -mouseDown:/-mouseDragged:/-mouseUp: are what a
// synthetic event stream can drive.  See the note in the header.
//
- (void) mouseDown:(NSEvent *)event
{
    if ([event clickCount] == 2) {
        [self setDoubleValue:_defaultValue];
        [self sendAction:[self action] to:[self target]];
        return;
    }

    [[self window] makeFirstResponder:self];

    _dragStartValue = _value;
    _dragStartY     = [self convertPoint:[event locationInWindow] fromView:nil].y;
}


- (void) mouseDragged:(NSEvent *)event
{
    CGFloat delta = [self convertPoint:[event locationInWindow] fromView:nil].y - _dragStartY;
    double  scale = ([event modifierFlags] & NSEventModifierFlagShift) ? 0.25 : 1.0;

    double normalized = [self _normalizedFromValue:_dragStartValue] +
                        ((delta / sDragTravel) * scale);

    [self _commitNormalized:normalized];
}


- (void) scrollWheel:(NSEvent *)event
{
    CGFloat delta = [event scrollingDeltaY];
    if ([event hasPreciseScrollingDeltas]) delta *= 0.1;

    [self _commitNormalized:[self _normalizedFromValue:_value] + (delta * 0.01)];
}


- (void) keyDown:(NSEvent *)event
{
    NSString *characters = [event charactersIgnoringModifiers];

    if (![characters length]) {
        [super keyDown:event];
        return;
    }

    unichar character = [characters characterAtIndex:0];
    double  step      = ([event modifierFlags] & NSEventModifierFlagShift) ? 0.002 : 0.01;
    double  normalized = [self _normalizedFromValue:_value];

    if (character == NSUpArrowFunctionKey || character == NSRightArrowFunctionKey) {
        [self _commitNormalized:normalized + step];

    } else if (character == NSDownArrowFunctionKey || character == NSLeftArrowFunctionKey) {
        [self _commitNormalized:normalized - step];

    } else {
        [super keyDown:event];
    }
}


#pragma mark - Accessibility

- (NSAccessibilityRole) accessibilityRole { return NSAccessibilitySliderRole; }
- (id) accessibilityValue                 { return @(_value); }
- (id) accessibilityMinValue              { return @(_minValue); }
- (id) accessibilityMaxValue              { return @(_maxValue); }
- (BOOL) isAccessibilityElement           { return YES; }

- (void) setAccessibilityValue:(id)value
{
    if (![value isKindOfClass:[NSNumber class]] || !std::isfinite([value doubleValue])) return;
    [self setDoubleValue:[value doubleValue]];
    [self sendAction:[self action] to:[self target]];
}

- (BOOL) accessibilityPerformIncrement
{
    [self _commitNormalized:[self _normalizedFromValue:_value] + 0.01];
    return YES;
}

- (BOOL) accessibilityPerformDecrement
{
    [self _commitNormalized:[self _normalizedFromValue:_value] - 0.01];
    return YES;
}

@end


#pragma mark - Curve

typedef void (^ParametricEQCurveChangeHandler)(AUParameterAddress address, AUValue value,
                                                BOOL refreshControls);

typedef struct {
    const char        *name;
    AUParameterAddress gainAddress;
    AUParameterAddress frequencyAddress;
    AUParameterAddress qAddress;
} ParametricEQCurveBandSpec;

static const ParametricEQCurveBandSpec sCurveBands[] = {
    { "Bass",       EmbraceParametricEQParameterLFGain,  EmbraceParametricEQParameterLFFrequency,  EmbraceParametricEQParameterLFQ  },
    { "Reverb Cut", EmbraceParametricEQParameterLMFGain, EmbraceParametricEQParameterLMFFrequency, EmbraceParametricEQParameterLMFQ },
    { "Brilliance", EmbraceParametricEQParameterHMFGain, EmbraceParametricEQParameterHMFFrequency, EmbraceParametricEQParameterHMFQ },
    { "Hiss Cut",   EmbraceParametricEQParameterHFGain,  EmbraceParametricEQParameterHFFrequency,  EmbraceParametricEQParameterHFQ  }
};

static const NSInteger sCurveBandCount = sizeof(sCurveBands) / sizeof(sCurveBands[0]);
// Large targets make the curve practical for operators who are not used to
// rotary controls. Keep the hit area slightly larger than the visible point.
static const CGFloat sCurveHandleRadius = 12;
static const CGFloat sCurveHitRadius = 18;

@interface ParametricEQCurveView : NSControl
@property (nonatomic, weak) AUAudioUnit *audioUnit;
@property (nonatomic, copy) ParametricEQCurveChangeHandler changeHandler;
@end


@implementation ParametricEQCurveView {
    // The frequency axis, the trig table read off it, and the curve read off
    // that.  All three depend on the plot geometry and the sample rate and on
    // nothing a knob can move, which is what makes them worth keeping between
    // redraws -- see -_prepareCurveTableForPlot:rate: below.
    std::vector<double> _curveHz;
    std::vector<double> _curveTrig;
    std::vector<float>  _curveDb;
    CGFloat             _curveWidth;
    double              _curveRate;
    NSInteger           _hoveredBand;
    NSInteger           _draggedBand;
    NSTrackingArea     *_trackingArea;
}

- (instancetype) initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
        _hoveredBand = -1;
        _draggedBand = -1;
        [self setAccessibilityLabel:NSLocalizedString(@"Parametric EQ curve", nil)];
        [self setAccessibilityHelp:NSLocalizedString(@"Drag a numbered point to change frequency and gain. Scroll over a point to change Q.", nil)];
    }
    return self;
}

- (BOOL) isOpaque { return NO; }
- (BOOL) acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void) updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}


- (double) _sampleRate
{
    AUAudioUnitBusArray *busses = [_audioUnit outputBusses];

    if ([busses count] > 0) {
        double rate = [[[busses objectAtIndexedSubscript:0] format] sampleRate];
        if (rate > 0) return rate;
    }

    return 44100;
}


static CGFloat sXForFrequency(CGRect plot, double hz)
{
    double normalized = log(hz / sCurveMinHz) / log(sCurveMaxHz / sCurveMinHz);
    return plot.origin.x + (CGFloat)(normalized * plot.size.width);
}


static CGFloat sYForDecibels(CGRect plot, double db)
{
    double normalized = sClamp(db, -sCurveMaxDb, sCurveMaxDb) / sCurveMaxDb;
    return CGRectGetMidY(plot) + (CGFloat)(normalized * (plot.size.height / 2));
}


static double sFrequencyForX(CGRect plot, CGFloat x)
{
    double normalized = sClamp((x - CGRectGetMinX(plot)) / CGRectGetWidth(plot), 0, 1);
    return sCurveMinHz * pow(sCurveMaxHz / sCurveMinHz, normalized);
}


static double sDecibelsForY(CGRect plot, CGFloat y)
{
    double normalized = (y - CGRectGetMidY(plot)) / (CGRectGetHeight(plot) / 2);
    return sClamp(normalized, -1, 1) * sCurveMaxDb;
}


- (CGRect) _plot
{
    CGRect bounds = CGRectInset([self bounds], 1, 1);
    bounds.origin.y += 14;
    bounds.size.height -= 14;
    return bounds;
}


- (CGPoint) _pointForBand:(NSInteger)band plot:(CGRect)plot
{
    if (band < 0 || band >= sCurveBandCount || !_audioUnit) return CGPointZero;
    AUParameterTree *tree = [_audioUnit parameterTree];
    const ParametricEQCurveBandSpec *spec = &sCurveBands[band];
    double frequency = [[tree parameterWithAddress:spec->frequencyAddress] value];
    double gain = [[tree parameterWithAddress:spec->gainAddress] value];
    return CGPointMake(sXForFrequency(plot, frequency), sYForDecibels(plot, gain));
}


- (NSInteger) _bandNearPoint:(CGPoint)point
{
    CGRect plot = [self _plot];
    NSInteger nearest = -1;
    CGFloat nearestDistance = sCurveHitRadius;
    for (NSInteger band = 0; band < sCurveBandCount; band++) {
        CGPoint handle = [self _pointForBand:band plot:plot];
        CGFloat distance = hypot(point.x - handle.x, point.y - handle.y);
        if (distance <= nearestDistance) {
            nearest = band;
            nearestDistance = distance;
        }
    }
    return nearest;
}


- (void) _setHoveredBand:(NSInteger)band
{
    if (_hoveredBand == band) return;
    _hoveredBand = band;
    [self setNeedsDisplay:YES];
    if (band >= 0) [[NSCursor openHandCursor] set];
    else [[NSCursor arrowCursor] set];
}


- (void) _moveBand:(NSInteger)band toPoint:(CGPoint)point
{
    if (band < 0 || band >= sCurveBandCount || !_audioUnit || !_changeHandler) return;
    CGRect plot = [self _plot];
    const ParametricEQCurveBandSpec *spec = &sCurveBands[band];
    AUParameterTree *tree = [_audioUnit parameterTree];
    AUParameter *frequency = [tree parameterWithAddress:spec->frequencyAddress];
    AUParameter *gain = [tree parameterWithAddress:spec->gainAddress];
    double hz = sClamp(sFrequencyForX(plot, point.x), [frequency minValue], [frequency maxValue]);
    double db = sClamp(sDecibelsForY(plot, point.y), [gain minValue], [gain maxValue]);
    _changeHandler(spec->frequencyAddress, (AUValue)hz, NO);
    _changeHandler(spec->gainAddress, (AUValue)db, YES);
}


- (void) mouseMoved:(NSEvent *)event
{
    [self _setHoveredBand:[self _bandNearPoint:[self convertPoint:[event locationInWindow] fromView:nil]]];
}


- (void) mouseExited:(NSEvent *)event
{
    if (_draggedBand < 0) [self _setHoveredBand:-1];
}


- (void) mouseDown:(NSEvent *)event
{
    CGPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger band = [self _bandNearPoint:point];
    if (band < 0) {
        [super mouseDown:event];
        return;
    }
    _draggedBand = band;
    [self _setHoveredBand:band];
    [[NSCursor closedHandCursor] set];
    [self _moveBand:band toPoint:point];
}


- (void) mouseDragged:(NSEvent *)event
{
    if (_draggedBand < 0) {
        [super mouseDragged:event];
        return;
    }
    [self _moveBand:_draggedBand toPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}


- (void) mouseUp:(NSEvent *)event
{
    if (_draggedBand < 0) {
        [super mouseUp:event];
        return;
    }
    [self _moveBand:_draggedBand toPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    _draggedBand = -1;
    NSInteger band = [self _bandNearPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    [self _setHoveredBand:band];
    if (band >= 0) [[NSCursor openHandCursor] set];
}


- (void) scrollWheel:(NSEvent *)event
{
    CGPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger band = [self _bandNearPoint:point];
    CGFloat delta = [event scrollingDeltaY];
    if (band < 0 || fabs(delta) < 0.001 || !_changeHandler) {
        [super scrollWheel:event];
        return;
    }

    const ParametricEQCurveBandSpec *spec = &sCurveBands[band];
    AUParameter *q = [[_audioUnit parameterTree] parameterWithAddress:spec->qAddress];
    double minimum = [q minValue], maximum = [q maxValue];
    if (band == 0 && [[[_audioUnit parameterTree] parameterWithAddress:EmbraceParametricEQParameterLFBell] value] < 0.5) maximum = 1.0;
    if (band == 3 && [[[_audioUnit parameterTree] parameterWithAddress:EmbraceParametricEQParameterHFBell] value] < 0.5) maximum = 1.0;
    double current = sClamp([q value], minimum, maximum);
    double normalized = log(current / minimum) / log(maximum / minimum);
    double step = [event hasPreciseScrollingDeltas] ? delta * 0.012 : copysign(0.06, delta);
    double value = minimum * pow(maximum / minimum, sClamp(normalized + step, 0, 1));
    _changeHandler(spec->qAddress, (AUValue)value, YES);
    [self _setHoveredBand:band];
}


- (void) _drawGridInPlot:(CGRect)plot
{
    static const double lines[]  = { 20, 30, 50, 100, 200, 300, 500, 1000,
                                     2000, 3000, 5000, 10000, 20000 };
    static const double labels[] = { 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000 };
    static const double decibels[] = { -20, -10, 0, 10, 20 };

    NSDictionary *attributes = @{
        NSFontAttributeName:            [self font] ?: [NSFont systemFontOfSize:9],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
    };

    [[NSColor separatorColor] set];

    for (int i = 0; i < 13; i++) {
        CGFloat x = round(sXForFrequency(plot, lines[i])) + 0.5;

        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:CGPointMake(x, CGRectGetMinY(plot))];
        [path lineToPoint:CGPointMake(x, CGRectGetMaxY(plot))];
        [path setLineWidth:1];
        [path stroke];
    }

    for (int i = 0; i < 5; i++) {
        CGFloat y = round(sYForDecibels(plot, decibels[i])) + 0.5;

        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:CGPointMake(CGRectGetMinX(plot), y)];
        [path lineToPoint:CGPointMake(CGRectGetMaxX(plot), y)];
        [path setLineWidth:1];

        if (decibels[i] == 0) {
            [[NSColor secondaryLabelColor] set];
            [path stroke];
            [[NSColor separatorColor] set];
        } else {
            [path stroke];

            NSString *text = [NSString stringWithFormat:@"%+.0f", decibels[i]];
            [text drawAtPoint:CGPointMake(CGRectGetMinX(plot) + 3, y + 1) withAttributes:attributes];
        }
    }

    for (int i = 0; i < 10; i++) {
        NSString *text = labels[i] >= 1000 ?
            [NSString stringWithFormat:@"%gk", labels[i] / 1000] :
            [NSString stringWithFormat:@"%g", labels[i]];

        CGSize size = [text sizeWithAttributes:attributes];
        CGFloat x = sXForFrequency(plot, labels[i]) - (size.width / 2);
        x = sClamp(x, CGRectGetMinX(plot), CGRectGetMaxX(plot) - size.width);

        [text drawAtPoint:CGPointMake(x, 2) withAttributes:attributes];
    }
}


- (NSString *) _readoutForBand:(NSInteger)band
{
    const ParametricEQCurveBandSpec *spec = &sCurveBands[band];
    AUParameterTree *tree = [_audioUnit parameterTree];
    double hz = [[tree parameterWithAddress:spec->frequencyAddress] value];
    double gain = [[tree parameterWithAddress:spec->gainAddress] value];
    double q = [[tree parameterWithAddress:spec->qAddress] value];
    NSString *frequency = hz >= 1000 ? [NSString stringWithFormat:@"%.1f kHz", hz / 1000.0]
                                     : [NSString stringWithFormat:@"%.0f Hz", hz];
    return [NSString stringWithFormat:@"%s  %@  %+.1f dB  Q %.2f",
            spec->name, frequency, gain, q];
}


- (void) _drawBandHandlesInPlot:(CGRect)plot color:(NSColor *)color
{
    for (NSInteger band = 0; band < sCurveBandCount; band++) {
        CGPoint point = [self _pointForBand:band plot:plot];
        BOOL emphasized = band == _hoveredBand || band == _draggedBand;
        CGFloat radius = sCurveHandleRadius + (emphasized ? 3 : 0);
        NSRect rect = NSMakeRect(point.x - radius, point.y - radius, radius * 2, radius * 2);
        NSBezierPath *handle = [NSBezierPath bezierPathWithOvalInRect:rect];
        [color setFill];
        [handle fill];
        [[NSColor controlBackgroundColor] setStroke];
        [handle setLineWidth:emphasized ? 2.5 : 1.5];
        [handle stroke];

        NSString *number = [NSString stringWithFormat:@"%ld", (long)band + 1];
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor controlBackgroundColor]
        };
        NSSize size = [number sizeWithAttributes:attributes];
        [number drawAtPoint:NSMakePoint(point.x - size.width / 2, point.y - size.height / 2)
             withAttributes:attributes];
    }

    if (_hoveredBand >= 0) {
        NSString *readout = [self _readoutForBand:_hoveredBand];
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor labelColor]
        };
        NSSize textSize = [readout sizeWithAttributes:attributes];
        NSRect pill = NSMakeRect(CGRectGetMaxX(plot) - textSize.width - 12,
                                 CGRectGetMaxY(plot) - textSize.height - 8,
                                 textSize.width + 8, textSize.height + 4);
        [[NSColor controlBackgroundColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:4 yRadius:4] fill];
        [readout drawAtPoint:NSMakePoint(pill.origin.x + 4, pill.origin.y + 2)
              withAttributes:attributes];
    }
}


// Brings the frequency axis and its trig table into line with this plot and
// this sample rate, and answers how many points they hold -- 0 when the plot is
// too small to draw a line across.
//
// The table is the expensive half of drawing a curve.  Asking magnitudeDb() for
// one point costs four trig calls per stage and a logarithm per stage, and both
// are per-point constants in disguise: cos(w) and cos(2w) depend on the
// frequency and the sample rate, neither of which a knob can move, and the six
// stage magnitudes are multiplied, so their six logarithms are one logarithm of
// the product.  Built here, a redraw is arithmetic -- about a fifth of the work,
// which is worth having on a drag.  See the note above curveTrig() in
// paraeq_core.h.
- (size_t) _prepareCurveTableForPlot:(CGRect)plot rate:(double)rate
{
    if (!(plot.size.width >= 1) || !(rate > 0)) return 0;

    // The points the drawing loop below walks: one per pixel column from the
    // left edge of the plot to the right.  Normalized against the full width
    // rather than against the last index, so a point lands exactly where
    // sXForFrequency would put its frequency.
    const size_t count = (size_t)floor((double)plot.size.width) + 1;

    if (count != _curveHz.size() ||
        plot.size.width != _curveWidth ||
        rate != _curveRate)
    {
        _curveHz.resize(count);
        _curveTrig.resize(count * (size_t)paraeq::kCurveTrigStride);
        _curveDb.resize(count);

        for (size_t i = 0; i < count; i++) {
            double normalized = (double)i / (double)plot.size.width;
            _curveHz[i] = sCurveMinHz * pow(sCurveMaxHz / sCurveMinHz, normalized);
        }

        paraeq::curveTrig(_curveHz.data(), count, rate, _curveTrig.data());

        _curveWidth = plot.size.width;
        _curveRate  = rate;
    }

    return count;
}


- (void) drawRect:(NSRect)dirtyRect
{
    CGRect bounds = [self bounds];

    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:4 yRadius:4];
    [[NSColor controlBackgroundColor] set];
    [background fill];

    CGRect plot = [self _plot];

    [NSGraphicsContext saveGraphicsState];
    [background addClip];
    [self _drawGridInPlot:plot];

    if (_audioUnit) {
        paraeq::Params params = EmbraceParametricEQEffectiveParams(_audioUnit);
        // Preview the selected settings even while processing is bypassed.
        params.bypass = false;
        NSColor *curveColor = [_audioUnit shouldBypassEffect] ? NSColor.secondaryLabelColor : NSColor.systemBlueColor;

        double rate = [self _sampleRate];

        paraeq::Config config;
        config.compute(params, rate);

        const size_t count = [self _prepareCurveTableForPlot:plot rate:rate];

        if (count >= 2) {
            // The whole cascade in one pass over the table, including the
            // output trim.  Reads the targets rather than the coefficients
            // actually in use, so the curve shows where the controls are and
            // not where a glide has got to.
            paraeq::curveDb(config, _curveTrig.data(), count, _curveDb.data());

            NSBezierPath *curve = [NSBezierPath bezierPath];
            NSBezierPath *fill  = [NSBezierPath bezierPath];

            CGFloat zeroY = sYForDecibels(plot, 0);

            for (size_t i = 0; i < count; i++) {
                CGPoint point = CGPointMake(plot.origin.x + (CGFloat)i,
                                            sYForDecibels(plot, _curveDb[i]));

                if (i == 0) {
                    [curve moveToPoint:point];
                    [fill moveToPoint:CGPointMake(point.x, zeroY)];
                    [fill lineToPoint:point];
                } else {
                    [curve lineToPoint:point];
                    [fill lineToPoint:point];
                }
            }

            [fill lineToPoint:CGPointMake(plot.origin.x + (CGFloat)(count - 1), zeroY)];
            [fill closePath];

            [[curveColor colorWithAlphaComponent:0.16] set];
            [fill fill];

            [curve setLineWidth:1.5];
            [curveColor set];
            [curve stroke];
        }

        [self _drawBandHandlesInPlot:plot color:curveColor];
    }

    [NSGraphicsContext restoreGraphicsState];

    [[NSColor separatorColor] set];
    [background setLineWidth:1];
    [background stroke];
}

@end


#pragma mark - Layout table

enum {
    kKnobLogarithmic = 1 << 0,
    kKnobBipolar     = 1 << 1,
    kKnobLarge       = 1 << 2
};

typedef struct {
    int                column;
    int                columns;   //!< span, so a lone knob can centre itself
    AUParameterAddress address;
    const char        *label;
    unsigned           flags;
} ParametricEQKnobSpec;


// Twelve columns, read left to right as a console strip.  The four gain knobs
// are the large ones because they are the four an operator actually reaches for
// once the session has started.
//
static const ParametricEQKnobSpec sKnobs[] = {
    // Spans both of its section's columns so the slope switch underneath has
    // room for three legible segments.
    {  0, 2, EmbraceParametricEQParameterFilterFrequency, "Freq", kKnobLogarithmic },

    {  2, 1, EmbraceParametricEQParameterLFGain,          "Gain", kKnobBipolar | kKnobLarge },
    {  3, 1, EmbraceParametricEQParameterLFFrequency,     "Freq", kKnobLogarithmic },

    {  4, 1, EmbraceParametricEQParameterLMFGain,         "Gain", kKnobBipolar | kKnobLarge },
    {  5, 1, EmbraceParametricEQParameterLMFFrequency,    "Freq", kKnobLogarithmic },
    {  6, 1, EmbraceParametricEQParameterLMFQ,            "Q",    kKnobLogarithmic },

    {  7, 1, EmbraceParametricEQParameterHMFGain,         "Gain", kKnobBipolar | kKnobLarge },
    {  8, 1, EmbraceParametricEQParameterHMFFrequency,    "Freq", kKnobLogarithmic },
    {  9, 1, EmbraceParametricEQParameterHMFQ,            "Q",    kKnobLogarithmic },

    { 10, 1, EmbraceParametricEQParameterHFGain,          "Gain", kKnobBipolar | kKnobLarge },
    { 11, 1, EmbraceParametricEQParameterHFFrequency,     "Freq", kKnobLogarithmic },

    { 12, 1, EmbraceParametricEQParameterOutputGain,      "Trim", kKnobBipolar }
};

static const int sKnobCount = (int)(sizeof(sKnobs) / sizeof(sKnobs[0]));


typedef struct {
    const char        *title;
    int                firstColumn;
    int                columns;
    AUParameterAddress switchAddress;   // kNoSwitch for none
    int                switchSegments;
    // Segment titles, comma separated, or NULL to use the parameter's own
    // valueStrings.  The slope needs its own: "12 dB/oct" is what the parameter
    // is called everywhere else and it does not fit in a third of a section.
    const char        *switchLabels;
} ParametricEQSectionSpec;

static const AUParameterAddress kNoSwitch = EmbraceParametricEQParameterCount;

// The sections, named for the job rather than for the console.  An operator
// reaching for the hiss should not have to know that a strip would have called
// that band HF, and the names say which way the knob usually goes, which is the
// point of a fixed layout: these are four jobs, not four identical bands.  The
// shorthand survives in the parameter identifiers, which is where it has to
// stay - those are what a saved preset stores.
//
// The same names the foobar2000 port shows, and from the same place: the tango
// transfer literature, which calls them low cut, bass, reverb cut, brilliance
// and hiss cut.
//
static const ParametricEQSectionSpec sSections[] = {
    { "LOW CUT",     0, 2, EmbraceParametricEQParameterFilterSlope, 3, "Off,12,24" },
    { "BASS",        2, 2, EmbraceParametricEQParameterLFBell,      2, NULL        },
    { "REVERB CUT",  4, 3, kNoSwitch,                               0, NULL        },
    { "BRILLIANCE",  7, 3, kNoSwitch,                               0, NULL        },
    { "HISS CUT",   10, 2, EmbraceParametricEQParameterHFBell,      2, NULL        },
    { "OUTPUT",     12, 1, kNoSwitch,                               0, NULL        }
};

static const int sSectionCount = (int)(sizeof(sSections) / sizeof(sSections[0]));
static const int sColumnCount  = 13;


#pragma mark - Main view

@implementation ParametricEQView {
    AUAudioUnit              *_audioUnit;
    AUParameterTree          *_parameterTree;
    AUParameterObserverToken  _observerToken;

    ParametricEQCurveView    *_curveView;
    EQStateButton           *_statusButton;

    NSMutableArray<ParametricEQKnob *>   *_knobs;
    NSMutableArray<NSTextField *>        *_valueFields;
    NSMutableArray<NSSegmentedControl *> *_switches;
    NSSize _designSize;
}


- (void) _beginManualEdit
{
    // Automatic flat is a per-track starting point, not a lock. The next track
    // asks Player to choose automatic flat again from its own genre.
    EmbraceParametricEQSetAutomaticFlatResponse(_audioUnit, NO);
}

@synthesize audioUnit = _audioUnit;


+ (CGSize) fittingSize
{
    CGFloat width = (sMargin * 2) + (sColumnCount * sColumnWidth) +
                    ((sSectionCount - 1) * sSectionGap);

    CGFloat height = sMargin + sCurveHeight + sCurveGap + sTitleHeight + 4 +
                     sLabelHeight + 3 + sKnobRowHeight + 2 + sValueHeight + 6 +
                     sSwitchHeight + sMargin;

    return CGSizeMake(width, height);
}


- (instancetype) initWithAudioUnit:(AUAudioUnit *)audioUnit
{
    CGSize size = [[self class] fittingSize];

    if ((self = [super initWithFrame:NSMakeRect(0, 0, size.width, size.height)])) {
        _designSize = size;
        [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self setClipsToBounds:YES];
        _audioUnit     = audioUnit;
        _parameterTree = [audioUnit parameterTree];

        _knobs       = [NSMutableArray arrayWithCapacity:sKnobCount];
        _valueFields = [NSMutableArray arrayWithCapacity:sKnobCount];
        _switches    = [NSMutableArray arrayWithCapacity:sSectionCount];

        [self _build];
        [self _buildMenu];
        [self reloadData];
        [_audioUnit addObserver:self forKeyPath:@"shouldBypassEffect" options:0 context:&sBypassObservationContext];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(_automaticFlatResponseDidChange:)
            name:EmbraceParametricEQAutomaticFlatDidChangeNotification object:_audioUnit];

        // Catches everything that changes a value from outside this view: a
        // preset load, Restore Defaults, and a host automating a parameter.
        // Values this view sets carry the token as originator, so they do not
        // come back round.
        __weak ParametricEQView *weakSelf = self;

        _observerToken = [_parameterTree tokenByAddingParameterObserver:
            ^(AUParameterAddress address, AUValue value)
        {
            // Called on whatever thread set the value, the render thread
            // included, so nothing here may touch AppKit directly.
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf reloadData];
            });
        }];
    }

    return self;
}


- (void) setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];

    // Keep one logical coordinate system while AppKit maps it into a compact
    // frame. Drawing, controls, mouse hit testing and accessibility therefore
    // shrink together instead of clipping or rearranging independently.
    if (_designSize.width > 0 && _designSize.height > 0) {
        [super setBoundsSize:_designSize];
    }
}


- (void) setFrame:(NSRect)frame
{
    [super setFrame:frame];
    if (_designSize.width > 0 && _designSize.height > 0) {
        [super setBoundsSize:_designSize];
    }
}


- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:EmbraceParametricEQAutomaticFlatDidChangeNotification object:_audioUnit];
    [_audioUnit removeObserver:self forKeyPath:@"shouldBypassEffect" context:&sBypassObservationContext];
    if (_observerToken) {
        [_parameterTree removeParameterObserver:_observerToken];
    }
}


- (void) _automaticFlatResponseDidChange:(NSNotification *)notification
{
    (void)notification;
    if ([NSThread isMainThread]) {
        [self reloadData];
    } else {
        __weak ParametricEQView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadData]; });
    }
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != &sBypassObservationContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if ([NSThread isMainThread]) {
        [self reloadData];
    } else {
        __weak ParametricEQView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadData]; });
    }
}


- (BOOL) isFlipped { return YES; }


// Paints its own background rather than borrowing the window's.  The window
// does supply one, so this looks like a formality -- but every colour in here
// is a semantic one, and a semantic colour is only legible against a background
// from the same appearance.  Drawn detached from a window, which is how the
// tests draw it, white-in-dark-mode text on an unpainted view is invisible.
//
- (void) drawRect:(NSRect)dirtyRect
{
    [[NSColor windowBackgroundColor] set];
    NSRectFill(NSIntersectionRect(dirtyRect, [self bounds]));
}


#pragma mark - Building

static CGFloat sXForColumn(int column)
{
    CGFloat x = sMargin;

    for (int i = 0; i < sSectionCount; i++) {
        if (column < sSections[i].firstColumn + sSections[i].columns) {
            return x + ((column - sSections[i].firstColumn) * sColumnWidth);
        }

        x += (sSections[i].columns * sColumnWidth) + sSectionGap;
    }

    return x;
}


static NSTextField *sMakeLabel(NSString *string, CGRect frame, CGFloat fontSize,
                               NSColor *color, NSFontWeight weight)
{
    NSTextField *label = [NSTextField labelWithString:string];

    [label setFrame:frame];
    [label setAlignment:NSTextAlignmentCenter];
    [label setFont:[NSFont systemFontOfSize:fontSize weight:weight]];
    [label setTextColor:color];
    [[label cell] setLineBreakMode:NSLineBreakByClipping];

    return label;
}


// Keep Flatten available in the editor context menu as well as the EQ toolbar.


- (void) _buildMenu
{
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *item = [menu addItemWithTitle:NSLocalizedString(@"Flat EQ", nil)
                                       action:@selector(flatten)
                                keyEquivalent:@""];
    [item setTarget:self];

    [self setMenu:menu];
}


- (void) _build
{
    CGSize  size = [[self class] fittingSize];
    CGFloat contentWidth = size.width - (sMargin * 2);

    CGFloat y = sMargin;

    _statusButton = [[EQStateButton alloc] initWithFrame:NSMakeRect((size.width - 72) / 2, 0, 72, sMargin)];
    _statusButton.buttonType = NSButtonTypePushOnPushOff;
    _statusButton.font = [NSFont systemFontOfSize:16 weight:NSFontWeightBold];
    _statusButton.target = self;
    _statusButton.action = @selector(_toggleEQ:);
    _statusButton.identifier = @"EQStatus";
    _statusButton.accessibilityLabel = NSLocalizedString(@"Parametric EQ", nil);
    [self addSubview:_statusButton];

    _curveView = [[ParametricEQCurveView alloc] initWithFrame:
        NSMakeRect(sMargin, y, contentWidth, sCurveHeight)];
    [_curveView setFont:[NSFont systemFontOfSize:9]];
    [_curveView setAudioUnit:_audioUnit];
    [_curveView setToolTip:NSLocalizedString(@"Drag points to set frequency and gain. Scroll over a point to adjust Q.", nil)];
    __weak ParametricEQView *weakSelf = self;
    [_curveView setChangeHandler:^(AUParameterAddress address, AUValue value,
                                   BOOL refreshControls) {
        ParametricEQView *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf _beginManualEdit];
        AUParameter *parameter = [strongSelf->_parameterTree parameterWithAddress:address];
        [parameter setValue:value originator:strongSelf->_observerToken];
        if (refreshControls) [strongSelf reloadData];
    }];
    [self addSubview:_curveView];

    y += sCurveHeight + sCurveGap;

    CGFloat titleY  = y;
    CGFloat labelY  = titleY + sTitleHeight + 4;
    CGFloat knobY   = labelY + sLabelHeight + 3;
    CGFloat valueY  = knobY  + sKnobRowHeight + 2;
    CGFloat switchY = valueY + sValueHeight + 6;

    for (int i = 0; i < sSectionCount; i++) {
        const ParametricEQSectionSpec *section = &sSections[i];

        CGFloat x     = sXForColumn(section->firstColumn);
        CGFloat width = section->columns * sColumnWidth;

        // titleLabel rather than title: the segment loop below has a title of
        // its own, and one shadowing the other is a way to read this wrong.
        NSTextField *titleLabel = sMakeLabel(@(section->title),
            NSMakeRect(x, titleY, width, sTitleHeight), 10,
            [NSColor secondaryLabelColor], NSFontWeightSemibold);

        // Named so the tests can pick the titles out from the other labels and
        // check that each still fits its section.  They are centred and clipped
        // rather than shrunk, so a name that outgrew its columns would quietly
        // lose its ends.
        [titleLabel setIdentifier:@"sectionTitle"];

        [self addSubview:titleLabel];

        if (section->switchAddress == kNoSwitch) continue;

        AUParameter *parameter = [_parameterTree parameterWithAddress:section->switchAddress];

        // A segmented control rather than a popup, so a synthetic click cannot
        // open a modal menu loop.  See the note in the header.
        NSSegmentedControl *control = [[NSSegmentedControl alloc] initWithFrame:
            NSMakeRect(x + 2, switchY, width - 4, sSwitchHeight)];

        [control setSegmentCount:section->switchSegments];
        [control setSegmentStyle:NSSegmentStyleRounded];
        [control setControlSize:NSControlSizeSmall];
        [control setFont:[NSFont systemFontOfSize:9]];
        [control setTag:(NSInteger)section->switchAddress];
        [control setTarget:self];
        [control setAction:@selector(_handleSwitch:)];
        [control setToolTip:[self _toolTipForParameter:parameter]];

        NSArray<NSString *> *titles = section->switchLabels ?
            [@(section->switchLabels) componentsSeparatedByString:@","] :
            [parameter valueStrings];

        for (int segment = 0; segment < section->switchSegments; segment++) {
            NSString *title = (segment < (int)[titles count]) ?
                [titles objectAtIndex:segment] : @"";

            [control setLabel:title forSegment:segment];
            [control setWidth:((width - 4) / section->switchSegments) forSegment:segment];
        }

        [self addSubview:control];
        [_switches addObject:control];
    }

    for (int i = 0; i < sKnobCount; i++) {
        const ParametricEQKnobSpec *spec = &sKnobs[i];

        AUParameter *parameter = [_parameterTree parameterWithAddress:spec->address];
        NSString    *toolTip   = [self _toolTipForParameter:parameter];

        CGFloat columnX  = sXForColumn(spec->column);
        CGFloat columnW  = spec->columns * sColumnWidth;
        CGFloat diameter = (spec->flags & kKnobLarge) ? sLargeKnob : sSmallKnob;

        NSTextField *label = sMakeLabel(@(spec->label),
            NSMakeRect(columnX, labelY, columnW, sLabelHeight), 10,
            [NSColor tertiaryLabelColor], NSFontWeightRegular);
        [label setToolTip:toolTip];
        [self addSubview:label];

        ParametricEQKnob *knob = [[ParametricEQKnob alloc] initWithFrame:NSMakeRect(
            columnX + ((columnW - diameter) / 2),
            knobY + ((sKnobRowHeight - diameter) / 2),
            diameter, diameter)];

        [knob setMinValue:[parameter minValue]];
        [knob setMaxValue:[parameter maxValue]];
        [knob setDefaultValue:[self _defaultValueForParameter:parameter]];
        [knob setLogarithmic:(spec->flags & kKnobLogarithmic) ? YES : NO];
        [knob setBipolar:(spec->flags & kKnobBipolar) ? YES : NO];
        [knob setTag:i];
        [knob setTarget:self];
        [knob setAction:@selector(_handleKnob:)];
        [knob setToolTip:toolTip];
        [knob setAccessibilityLabel:[parameter displayName]];

        [self addSubview:knob];
        [_knobs addObject:knob];

        NSTextField *valueField = sMakeLabel(@"",
            NSMakeRect(columnX - 4, valueY, columnW + 8, sValueHeight), 10,
            [NSColor labelColor], NSFontWeightRegular);
        [valueField setToolTip:toolTip];
        [self addSubview:valueField];
        [_valueFields addObject:valueField];
    }
}


// The unit describes its own parameters, the same way it would for a generic
// form -- so the help text is written once and both editors show it.
- (id<ParameterDescribing>) _describing
{
    return (id<ParameterDescribing>)_audioUnit;
}


- (AUValue) _defaultValueForParameter:(AUParameter *)parameter
{
    id<ParameterDescribing> describing = [self _describing];

    if ([describing respondsToSelector:@selector(embrace_defaultValueForParameterAddress:)]) {
        return [describing embrace_defaultValueForParameterAddress:[parameter address]];
    }

    return [parameter value];
}


- (NSString *) _toolTipForParameter:(AUParameter *)parameter
{
    id<ParameterDescribing> describing = [self _describing];

    if ([describing respondsToSelector:@selector(embrace_helpTextForParameterAddress:)]) {
        NSString *help = [describing embrace_helpTextForParameterAddress:[parameter address]];
        if ([help length]) return help;
    }

    return NSLocalizedString(@"Double-click to restore the default value.", nil);
}


#pragma mark - Formatting

- (NSString *) _stringForParameter:(AUParameter *)parameter
{
    AUValue value = [parameter value];

    switch ([parameter unit]) {
    case kAudioUnitParameterUnit_Hertz:
        if (value >= 1000) {
            double kilohertz = value / 1000.0;
            NSString *number = (fabs(kilohertz - round(kilohertz)) < 0.05) ?
                [NSString stringWithFormat:@"%.0f", kilohertz] :
                [NSString stringWithFormat:@"%.1f", kilohertz];

            return [NSString stringWithFormat:NSLocalizedString(@"%@ kHz", nil), number];
        }

        return [NSString stringWithFormat:NSLocalizedString(@"%.0f Hz", nil), value];

    case kAudioUnitParameterUnit_Decibels:
        // Signed, because on a gain knob "5" and "-5" are the whole question
        // and the reader should not have to look at the knob to tell which.
        if (fabs(value) < 0.05) return NSLocalizedString(@"0.0 dB", nil);
        return [NSString stringWithFormat:NSLocalizedString(@"%+.1f dB", nil), value];

    default:
        return [NSString stringWithFormat:@"%.2f", value];
    }
}


#pragma mark - Actions

- (void) _toggleEQ:(id)sender
{
    BOOL enabled = [_audioUnit shouldBypassEffect];
    if (self.setEQEnabled) self.setEQEnabled(enabled);
    else [_audioUnit setShouldBypassEffect:!enabled];
    [self reloadData];
}

- (void) _handleKnob:(ParametricEQKnob *)knob
{
    NSInteger index = [knob tag];
    if (index < 0 || index >= sKnobCount) return;

    AUParameter *parameter = [_parameterTree parameterWithAddress:sKnobs[index].address];

    [self _beginManualEdit];
    [parameter setValue:(AUValue)[knob doubleValue] originator:_observerToken];

    [[_valueFields objectAtIndex:index] setStringValue:[self _stringForParameter:parameter]];
    [_curveView setNeedsDisplay:YES];
}


- (void) _handleSwitch:(NSSegmentedControl *)control
{
    AUParameter *parameter = [_parameterTree parameterWithAddress:(AUParameterAddress)[control tag]];

    [self _beginManualEdit];
    [parameter setValue:(AUValue)[control selectedSegment] originator:_observerToken];

    [_curveView setNeedsDisplay:YES];
}


#pragma mark - Public Methods

- (void) reloadData
{
    BOOL enabled = ![_audioUnit shouldBypassEffect];
    _statusButton.title = enabled ? NSLocalizedString(@"ON", nil) : NSLocalizedString(@"OFF", nil);
    _statusButton.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    _statusButton.toolTip = enabled ? NSLocalizedString(@"Parametric EQ on. Click to bypass.", nil) : NSLocalizedString(@"Parametric EQ off. Click to enable.", nil);
    _statusButton.needsDisplay = YES;
    for (int i = 0; i < sKnobCount; i++) {
        AUParameter *parameter = [_parameterTree parameterWithAddress:sKnobs[i].address];

        [[_knobs objectAtIndex:i] setDoubleValue:[parameter value]];
        [[_valueFields objectAtIndex:i] setStringValue:[self _stringForParameter:parameter]];
    }

    for (NSSegmentedControl *control in _switches) {
        AUParameter *parameter = [_parameterTree parameterWithAddress:(AUParameterAddress)[control tag]];
        NSInteger    segment   = (NSInteger)lround([parameter value]);

        if (segment >= 0 && segment < [control segmentCount]) {
            [control setSelectedSegment:segment];
        }
    }

    [_curveView setNeedsDisplay:YES];
}


- (void) flatten
{
    static const AUParameterAddress gains[] = {
        EmbraceParametricEQParameterLFGain,
        EmbraceParametricEQParameterLMFGain,
        EmbraceParametricEQParameterHMFGain,
        EmbraceParametricEQParameterHFGain,
        EmbraceParametricEQParameterOutputGain
    };

    [self _beginManualEdit];
    for (int i = 0; i < 5; i++) {
        [[_parameterTree parameterWithAddress:gains[i]] setValue:0 originator:_observerToken];
    }
    [[_parameterTree parameterWithAddress:EmbraceParametricEQParameterFilterSlope] setValue:0 originator:_observerToken];

    [self reloadData];
}

@end
