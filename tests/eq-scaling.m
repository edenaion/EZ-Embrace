#import <Cocoa/Cocoa.h>
#import "GraphicEQView.h"

BOOL IsAppearanceDarkAqua(NSView *view) { return NO; }

@interface GraphicEQView (GeometryTests)
- (void)_rebuild;
- (void)_beginUpdateWithWindowLocation:(CGPoint)point slow:(BOOL)slow;
- (void)_continueUpdateWithWindowLocation:(CGPoint)point;
- (void)_endUpdate;
@end
@interface NSView (BandGeometryTests)
@property (nonatomic) Float32 value;
@property (nonatomic, readonly) CGFloat draggableHeight;
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (NSNumber *scaleNumber in @[@1, @1.25, @1.5, @1.75, @2, @3]) {
            CGFloat scale = scaleNumber.doubleValue;
            NSRect design = NSMakeRect(0, 0, 400, 200);
            NSRect frame = NSMakeRect(0, 0, design.size.width * scale, design.size.height * scale);
            NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
            NSView *scaled = [[NSView alloc] initWithFrame:frame];
            scaled.bounds = design;
            [window.contentView addSubview:scaled];
            GraphicEQView *eq = [[GraphicEQView alloc] initWithFrame:design];
            [scaled addSubview:eq];
            // Nil unit supplies zero-valued bands. Exercise production view geometry without audio I/O.
            [eq _rebuild];
            [eq layout];
            NSView *band = [[eq valueForKey:@"bandViews"] firstObject];
            Check(band != nil, @"EQ bands created");
            [eq setValue:band forKey:@"selectedBandView"];
            NSPoint center = NSMakePoint(NSMidX(band.bounds), NSMidY(band.bounds));
            NSPoint from = [band convertPoint:center toView:nil];
            NSPoint to = [band convertPoint:NSMakePoint(center.x, center.y + band.draggableHeight / 8) toView:nil];
            [eq _beginUpdateWithWindowLocation:from slow:NO];
            [eq _continueUpdateWithWindowLocation:to];
            Check(fabs(band.value - 0.25) < 0.001,
                [NSString stringWithFormat:@"EQ knob follows pointer by the same fraction at %.0f%% scale", scale * 100]);
            [eq _endUpdate];
            band.value = 0;
            [eq _beginUpdateWithWindowLocation:from slow:YES];
            [eq _continueUpdateWithWindowLocation:to];
            Check(fabs(band.value - 0.0625) < 0.001, @"Option-drag retains quarter speed at every scale");
            [eq _endUpdate];
        }
        printf("PASS: %lu EQ-scaling assertions\n", (unsigned long)checks);
    }
    return 0;
}
