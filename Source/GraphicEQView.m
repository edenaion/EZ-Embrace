// (c) 2015-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "GraphicEQView.h"
#import "SetlistSlider.h"
#import <AudioToolbox/AudioToolbox.h>


const CGFloat sKnobHeight      = 15;
const CGFloat sVerticalPadding = 2;
const CGFloat sTrackWidth      = 5;


@interface GraphicEQControlView : NSControl
@end


@interface GraphicEQBandView : NSView

@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic) Float32 value;    // Normalized to +1.0/-1.0

- (CGRect) knobRectWithValue:(Float32)value;
- (BOOL) isWindowLocationInsideKnob:(CGPoint)point;
- (void) jumpKnobToWindowLocation:(CGPoint)point;

@property (nonatomic, readonly) CGRect trackRect;
@property (nonatomic, readonly) CGFloat draggableHeight;

@end

//
//@interface GraphicEQBackgroundView : NSView
//@property (nonatomic, strong) GraphicEQBandView *alignedBandView;
//@end


#pragma mark - Main View

@implementation GraphicEQView {
    NSArray  *_bandViews;
    NSArray  *_labelViews;
    
    GraphicEQControlView *_controlView;
    GraphicEQBandView    *_selectedBandView;

    NSTextField *_topLabel;
    NSTextField *_middleLabel;
    NSTextField *_bottomLabel;

    Float32   _startBandValue;
    CGPoint   _startLocation;
    CGFloat   _draggableHeight;
    BOOL      _dragIsSlow;
    
    BOOL _firstEventInsideKnob;
}


- (id) initWithFrame:(CGRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
        _controlView = [[GraphicEQControlView alloc] initWithFrame:[self bounds]];
        [_controlView setTranslatesAutoresizingMaskIntoConstraints:NO];
        
        [self addSubview:_controlView];
    }

    return self;
}


- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (void) viewDidChangeEffectiveAppearance
{
    [self _updateBandAlpha];
}


- (BOOL) wantsUpdateLayer
{
    return YES;
}


- (void) updateLayer { }


- (void) layout
{
    [super layout];
    
    CGRect bounds = [self bounds];
   
    CGRect bandRect = CGRectMake(0, 20, 19, bounds.size.height - 20);
    bandRect.size.width = _numberOfBands > 10 ? 23 : 31;

    CGFloat firstX = 44;
    
    CGFloat bandMinX = bounds.size.width;
    CGFloat bandMaxX = 0;
    
    void (^alignLabel)(NSTextField *, GraphicEQBandView *, Float32) = ^(NSTextField *label, GraphicEQBandView *bandView, Float32 value) {
        CGRect knobRect = [bandView knobRectWithValue:value];
        knobRect = [self convertRect:knobRect fromView:bandView];
        
        CGFloat knobY = knobRect.origin.y;
        CGFloat bandX = [bandView frame].origin.x;
        
        CGRect topFrame = [label frame];
        
        topFrame.origin.x = bandX - topFrame.size.width;
        topFrame.origin.y = knobY;
        [label setFrame:topFrame];
    };
    
    if (_numberOfBands) {
        CGRect controlFrame = CGRectNull;

        for (NSInteger i = 0; i < _numberOfBands; i++) {
            bandRect.origin.x = firstX + (i * bandRect.size.width);
            
            GraphicEQBandView *bandView = [_bandViews  objectAtIndex:i];
            NSTextField       *label    = [_labelViews objectAtIndex:i];
            
            [bandView setFrame:bandRect];
            controlFrame = CGRectUnion(controlFrame, bandRect);
     
            bandMinX = MIN(bandMinX, CGRectGetMinX(bandRect));
            bandMaxX = MAX(bandMaxX, CGRectGetMaxX(bandRect));
            
            CGRect labelRect = CGRectInset(bandRect, -32, 0);
            labelRect.size.height = 20;
            labelRect.origin.y = 0;
            [label setFrame:labelRect];
        }

        [_controlView setFrame:controlFrame];
    }

    // Background view and labels
    {
        GraphicEQBandView *firstBand = [_bandViews firstObject];

        if (firstBand) {
            alignLabel(_topLabel,    firstBand,  1.0);
            alignLabel(_middleLabel, firstBand,  0.0);
            alignLabel(_bottomLabel, firstBand, -1.0);
        }
    }
}


#pragma mark - Events

- (NSInteger) _bandIndexAtPoint:(CGPoint)point
{
    NSInteger i = 0;

    for (GraphicEQBandView *bandView in _bandViews) {
        if (CGRectContainsPoint([bandView frame], point)) {
            return i;
        }

        i++;
    }
    
    return NSNotFound;
}


- (GraphicEQBandView *) _bandViewWithWindowLocation:(CGPoint)windowLocation insideKnob:(BOOL *)insideKnob
{
    CGPoint pointInView = [self convertPoint:windowLocation fromView:nil];

    NSInteger bandIndex = [self _bandIndexAtPoint:pointInView];
    
    if (bandIndex >= 0 && bandIndex < [_bandViews count]) {
        GraphicEQBandView *bandView = [_bandViews objectAtIndex:bandIndex];
        
        if (insideKnob) {
            *insideKnob = [bandView isWindowLocationInsideKnob:windowLocation];
        }

        return bandView;
    }
    
    return nil;
}


- (void) _beginUpdateWithWindowLocation:(CGPoint)windowLocation slow:(BOOL)isSlow
{
    _startBandValue   = [_selectedBandView value];
    _startLocation    = [_selectedBandView convertPoint:windowLocation fromView:nil];
    _draggableHeight  = [_selectedBandView draggableHeight];
    _dragIsSlow       = isSlow;

    [_selectedBandView setSelected:YES];
}


- (void) _continueUpdateWithWindowLocation:(CGPoint)windowLocation
{
    CGPoint location = [_selectedBandView convertPoint:windowLocation fromView:nil];
    CGFloat delta = ((location.y - _startLocation.y) / (_draggableHeight / 2));
    if (_dragIsSlow) delta /= 4.0;

    CGFloat newValue = _startBandValue + delta;
    if (newValue >  1.0) newValue =  1.0;
    if (newValue < -1.0) newValue = -1.0;
    
    [_selectedBandView setValue:newValue];
}


- (void) _endUpdate
{
    [_selectedBandView setSelected:NO];
}


- (void) _updateBandAlpha
{
    CGFloat alpha = 1.0;

    if (IsAppearanceDarkAqua(self)) {
        alpha = [[NSColor colorNamed:@"EQDarkAlpha"] alphaComponent];

        for (GraphicEQBandView *bandView in _bandViews) {
            [bandView setAlphaValue:alpha];
        }
    }
}


- (void) _controlViewMouseDown:(NSEvent *)firstEvent
{
    CGPoint pointInView = CGPointZero;
    
    pointInView = [self convertPoint:[firstEvent locationInWindow] fromView:nil];
    NSInteger index = [self _bandIndexAtPoint:pointInView];
    
    BOOL slow     = ([firstEvent modifierFlags] & NSEventModifierFlagOption)  > 0;
    BOOL drawMode = ([firstEvent modifierFlags] & NSEventModifierFlagControl) > 0;

    CGPoint windowLocation = [firstEvent locationInWindow];

    if (index == NSNotFound) {
        [super mouseDown:firstEvent];
        return;
    }

    AUParameterTree *tree = [_audioUnit parameterTree];

    void (^sendValue)() = ^{
        NSInteger bandIndex = [_bandViews indexOfObject:_selectedBandView];
        
        if (bandIndex != NSNotFound) {
            AUParameter *parameter = [tree parameterWithID:(AudioUnitParameterID)bandIndex scope:kAudioUnitScope_Global element:0];

            AUValue value = [_selectedBandView value] * 12.0;
            [parameter setValue:value originator:NULL];
        }
    };
    
    BOOL insideKnob = NO;

    if ([firstEvent type] == NSEventTypeLeftMouseDown) {
        _selectedBandView = [self _bandViewWithWindowLocation:windowLocation insideKnob:&insideKnob];

        NSInteger clickCount = [firstEvent clickCount];

        if (insideKnob) {
            if (clickCount > 1) {
                if (_firstEventInsideKnob) {
                    [_selectedBandView setValue:0];
                    sendValue();
                    return;
                }
            } else {
                _firstEventInsideKnob = YES; 
            }
           
        } else if (!insideKnob) {
            if (clickCount == 1) {
                [_selectedBandView jumpKnobToWindowLocation:windowLocation];
                _firstEventInsideKnob = NO;
                sendValue();
            }
        }

        [self _beginUpdateWithWindowLocation:windowLocation slow:slow];

        while (1) {
            NSEvent *event = [[self window] nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp | NSEventMaskFlagsChanged)];

            if ([event type] == NSEventTypeLeftMouseDragged) {
                windowLocation = [event locationInWindow];

                if (drawMode) {
                    GraphicEQBandView *bandView = [self _bandViewWithWindowLocation:windowLocation insideKnob:&insideKnob];

                    if (bandView != _selectedBandView) {
                        [self _endUpdate];
                        _selectedBandView = bandView;
                        
                        if (!insideKnob) {
                            [_selectedBandView jumpKnobToWindowLocation:windowLocation];
                        }

                        [self _beginUpdateWithWindowLocation:windowLocation slow:slow];
                    }
                }

                [self _continueUpdateWithWindowLocation:windowLocation];
                sendValue();

            } else if ([event type] == NSEventTypeFlagsChanged) {
                BOOL newSlow  = ([event modifierFlags] & NSEventModifierFlagOption)  > 0;
                     drawMode = ([event modifierFlags] & NSEventModifierFlagControl) > 0;

                if (slow != newSlow) {
                    slow = newSlow;
                    [self _endUpdate];
                    [self _beginUpdateWithWindowLocation:windowLocation slow:slow];
                }
                
            } else if ([event type] == NSEventTypeLeftMouseUp) {
                [self _endUpdate];
                break;
            }
        }
    }
    
    for (GraphicEQBandView *bandView in _bandViews) {
        [bandView setSelected:NO];
    }

    _selectedBandView = nil;
}


#pragma mark - Audio Unit

- (void) reloadData
{
    AudioUnitParameterID parameterID = 0;
    AUParameterTree *tree = [_audioUnit parameterTree];

    for (GraphicEQBandView *bandView in _bandViews) {
        AUParameter *parameter = [tree parameterWithID:parameterID scope:kAudioUnitScope_Global element:0];
        [bandView setValue:([parameter value] / 12.0)];

        parameterID++;
    }
}


- (void) flatten
{
    AudioUnitParameterID parameterID = 0;
    AUParameterTree *tree = [_audioUnit parameterTree];

    for (GraphicEQBandView *bandView in _bandViews) {
        AUParameter *parameter = [tree parameterWithID:parameterID scope:kAudioUnitScope_Global element:0];

        [parameter setValue:0];
        [bandView setValue:0];

        parameterID++;
    }
}


- (void) _rebuild
{
    AUParameterTree *tree = [_audioUnit parameterTree];
    AUParameter *parameter = [tree parameterWithID:kGraphicEQParam_NumberOfBands scope:kAudioUnitScope_Global element:0];

    AUValue parameterValue = [parameter value];
    
    NSInteger numberOfBands = parameterValue > 0 ? 31 : 10;
    if (numberOfBands == _numberOfBands) return;

    [_bandViews  makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [_labelViews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSTextField *(^makeLabel)(NSControlSize) = ^(NSControlSize controlSize) {
        NSTextField *label = [[NSTextField alloc] initWithFrame:CGRectZero];

        [label setTranslatesAutoresizingMaskIntoConstraints:NO];
        [label setEditable:NO];
        [label setSelectable:NO];
        [label setBordered:NO];
        [label setBackgroundColor:[NSColor clearColor]];
        [label setDrawsBackground:NO];
        [label setAlignment:NSTextAlignmentCenter];
        [label setTextColor:[NSColor labelColor]];
        [label setControlSize:controlSize];
        [label setFont:[NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:controlSize]]];

        return label;
    };

    NSMutableArray *bandViews  = [NSMutableArray array];
    NSMutableArray *labelViews = [NSMutableArray array];

    NSArray *labels10 = @[
        @"32",
        @"64",
        @"128",
        @"256",
        @"512",
        @"1k",
        @"2k",
        @"4k",
        @"8k",
        @"16k"
    ];

    NSArray *labels31 = @[
        @"20",  @"25",  @"31.5",
        @"40",  @"50",  @"63",
        @"80",  @"100", @"125",
        @"160", @"200", @"250",
        @"315", @"400", @"500",
        @"630", @"800", @"1k",
        @"1.2k", @"1.6k", @"2k",
        @"2.5k", @"3.1k", @"4k",
        @"5k",   @"6.3k", @"8k",
        @"10k",  @"12k",  @"16k",
        @"20k"
    ];
    
    NSArray *labelsToUse = (numberOfBands == 31) ? labels31 : labels10;

    for (NSInteger i = 0; i < numberOfBands; i++) {
        GraphicEQBandView *bandView = [[GraphicEQBandView alloc] initWithFrame:CGRectZero];

        [bandView setTranslatesAutoresizingMaskIntoConstraints:NO];
        
        [self addSubview:bandView];

        NSTextField *label = makeLabel(numberOfBands > 10 ? NSControlSizeMini : NSControlSizeSmall);
        [label setStringValue:[labelsToUse objectAtIndex:i]];
        [self addSubview:label];

        [bandViews  addObject:bandView];
        [labelViews addObject:label];
    }

    _bandViews     = bandViews;
    _labelViews    = labelViews;
    _numberOfBands = numberOfBands;
    
    if (!_topLabel) {
        _topLabel = makeLabel(NSControlSizeSmall);
        [_topLabel setAlignment:NSTextAlignmentRight];
        [_topLabel setStringValue:NSLocalizedString(@"+12dB", nil)];

        [self addSubview:_topLabel];
        [_topLabel sizeToFit];
    }

    if (!_middleLabel) {
        _middleLabel = makeLabel(NSControlSizeSmall);
        [_middleLabel setAlignment:NSTextAlignmentRight];
        [_middleLabel setStringValue:NSLocalizedString(@"0dB", nil)];

        [self addSubview:_middleLabel];
        [_middleLabel sizeToFit];
    }

    if (!_bottomLabel) {
        _bottomLabel = makeLabel(NSControlSizeSmall);
        [_bottomLabel setAlignment:NSTextAlignmentRight];
        [_bottomLabel setStringValue:NSLocalizedString(@"-12dB", nil)];

        [self addSubview:_bottomLabel];
        [_bottomLabel sizeToFit];
    }
    
    [self _updateBandAlpha];
    [self reloadData];
}


- (void) setAudioUnit:(AUAudioUnit *)audioUnit
{
    if (_audioUnit != audioUnit) {
        _audioUnit = audioUnit;
        [self _rebuild];
    }
}


@end


#pragma mark - Control View

@implementation GraphicEQControlView

- (void) mouseDown:(NSEvent *)event
{
    [(GraphicEQView *)[self superview] _controlViewMouseDown:event];
}

@end


#pragma mark - Band View

@implementation GraphicEQBandView


- (id) initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
        [self setWantsLayer:YES];
    }
    
    return self;
}


- (CGRect) trackRect
{
    CGRect bounds = [self bounds];

    CGFloat trackPadding = (sVerticalPadding + (sKnobHeight / 2.0)) - (sTrackWidth / 2.0);
    trackPadding -= 2.0;
    
    CGRect result = CGRectInset(bounds, 0, trackPadding);
    result.size.width = sTrackWidth;
    result.origin.x = (bounds.size.width - sTrackWidth) / 2;

    return result;
}


- (CGRect) knobRectWithValue:(Float32)value
{
    CGRect bounds = [self bounds];

    CGFloat minKnobY = sVerticalPadding;
    CGFloat maxKnobY = (bounds.size.height - sVerticalPadding) - sKnobHeight;
    
    CGFloat y = floor(((maxKnobY - minKnobY) * ((value + 1.0) / 2.0)) + minKnobY);
    
    CGRect result = CGRectMake(0, y, sKnobHeight, sKnobHeight);
    result.origin.x = (bounds.size.width - sKnobHeight) / 2;

    return result;
}


- (BOOL) isWindowLocationInsideKnob:(CGPoint)windowLocation
{
    CGPoint point = [self convertPoint:windowLocation fromView:nil];
    CGRect knobRect = [self knobRectWithValue:_value];
    return CGRectContainsPoint(knobRect, point);
}


- (void) jumpKnobToWindowLocation:(CGPoint)windowLocation
{
    CGFloat y = [self convertPoint:windowLocation fromView:nil].y;

    CGRect bounds = [self bounds];

    CGFloat minKnobY = sVerticalPadding;
    CGFloat maxKnobY = (bounds.size.height - sVerticalPadding) - sKnobHeight;

    y -= (sKnobHeight / 2);

    Float32 value = (y - minKnobY) / maxKnobY;
    value = (value * 2) - 1.0;
    
    if (value > 1.0) {
        value = 1.0;
    } else if (value < -1.0) {
        value = -1.0;
    }
    
    [self setValue:value];
}


- (void) drawRect:(NSRect)dirtyRect
{
    CGRect bounds    = [self bounds];
    CGRect trackRect = [self trackRect];

    CGRect (^getTickRect)(Float32) = ^(Float32 value) {
        CGRect valueRect = [self knobRectWithValue:value];

        CGRect lineRect = bounds;
        lineRect.origin.y = valueRect.origin.y;
        lineRect.size.height = 1;
        
        lineRect.origin.y += (valueRect.size.height - 1.0) / 2.0;
        
        return lineRect;
    };

    NSBezierPath *secondaryPath = [NSBezierPath bezierPath];

    void (^appendTick)(Float32) = ^(Float32 value) {
        NSBezierPath *tickPath = [NSBezierPath bezierPathWithRect:getTickRect(value)];
        [secondaryPath appendBezierPath:tickPath];
    };
   
    appendTick( 1.00 );
    appendTick(-1.00 );
    appendTick( 0.50 );
    appendTick(-0.50 );

    appendTick( 0.75 );
    appendTick( 0.25 );
    appendTick(-0.25 );
    appendTick(-0.75 );

    NSBezierPath *trackPath = [NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:2.5 yRadius:2.5];
    [secondaryPath appendBezierPath:trackPath];

    [[NSColor colorNamed:@"EQSecondary"] set];
    [secondaryPath fill];

    [[NSColor colorNamed:@"EQPrimary"] set];
    [[NSBezierPath bezierPathWithRect:getTickRect(0)] fill];
    
    CGRect knobRect  = [self knobRectWithValue:_value];

    NSRect filledRect = NSUnionRect(getTickRect(0), getTickRect(_value));
    filledRect.origin.x = trackRect.origin.x;
    filledRect.size.width = trackRect.size.width;

    [[NSBezierPath bezierPathWithRect:filledRect] fill];

    [self _drawKnobWithRect:knobRect highlighted:_selected];
}

- (void) _drawKnobWithRect:(CGRect)rect highlighted:(BOOL)highlighted
{   
    NSShadow *(^makeShadow)(CGFloat, CGFloat, CGFloat) = ^(CGFloat alpha, CGFloat yOffset, CGFloat blurRadius) {
        NSShadow *shadow = [[NSShadow alloc] init];
        
        [shadow setShadowColor:[NSColor colorWithCalibratedWhite:0 alpha:alpha]];
        [shadow setShadowOffset:NSMakeSize(0, -yOffset)];
        [shadow setShadowBlurRadius:blurRadius];

        return shadow;
    };

    BOOL isMainWindow = [[self window] isMainWindow];
    
    NSColor *start = nil;
    NSColor *end   = nil;
    
    NSShadow *shadow1 = nil;
    NSShadow *shadow2 = nil;
    
    if (IsAppearanceDarkAqua(self)) {
        if (isMainWindow) {
            shadow1 = makeShadow( 0.6, 1, 2 );
            shadow2 = makeShadow( 0.8, 0, 1 );
        } else {
            shadow1 = makeShadow( 0.9, 0, 1 );
        }

    } else {
        if (isMainWindow) {
            shadow1 = makeShadow( 0.4, 1, 1 );
            shadow2 = makeShadow( 0.6, 0, 1 );
        } else {
            shadow1 = makeShadow( 0.45, 0, 1 );
        }
    }

    if (highlighted) {
        start = [NSColor colorNamed:@"EQKnobPressed1"];
        end   = [NSColor colorNamed:@"EQKnobPressed2"];

    } else if (isMainWindow) {
        start = [NSColor colorNamed:@"EQKnobMain1"];
        end   = [NSColor colorNamed:@"EQKnobMain2"];

    } else {
        start = [NSColor colorNamed:@"EQKnobResigned1"];
        end   = [NSColor colorNamed:@"EQKnobResigned2"];
    }

    [shadow1 set];
    [start set];
   
    [[NSBezierPath bezierPathWithOvalInRect:rect] fill];
    
    if (shadow2 && start && end) {
        [shadow2 set];

        NSGradient *g = [[NSGradient alloc] initWithColors:@[ start, end ]];
        
        CGFloat angle = [self isFlipped] ? 90 : -90;
        [g drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:rect] angle:angle];
    }
}


- (CGFloat) draggableHeight
{
    return [self bounds].size.height - (sKnobHeight + (sVerticalPadding * 2));
}


- (void) setValue:(Float32)value
{
    if (_value != value) {
        _value = value;
        [self setNeedsDisplay:YES];
    }
}


- (void) setSelected:(BOOL)selected
{
    if (_selected != selected) {
        _selected = selected;
        [self setNeedsDisplay:YES];
    }
}

@end

