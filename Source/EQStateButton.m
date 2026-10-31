#import "EQStateButton.h"

@implementation EQStateButton

- (void) drawRect:(NSRect)dirtyRect
{
    BOOL active = self.state == NSControlStateValueOn;
    NSColor *fill = active ? NSColor.systemBlueColor : NSColor.unemphasizedSelectedContentBackgroundColor;
    NSColor *foreground = active ? NSColor.whiteColor : NSColor.secondaryLabelColor;
    NSRect bezel = NSInsetRect(self.bounds, 1, 1);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bezel xRadius:4 yRadius:4];
    [fill setFill];
    [path fill];
    [[NSColor colorWithWhite:0 alpha:self.highlighted ? .25 : .12] setStroke];
    path.lineWidth = 0.5;
    [path stroke];

    if (self.image && self.imagePosition == NSImageOnly) {
        NSImage *image = self.image;
        NSImage *tinted = [NSImage imageWithSize:image.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
            [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
            [foreground setFill];
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceIn);
            return YES;
        }];
        NSSize size = image.size;
        NSRect rect = NSMakeRect(NSMidX(self.bounds) - size.width / 2,
            NSMidY(self.bounds) - size.height / 2, size.width, size.height);
        [tinted drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    } else {
        NSDictionary *attributes = @{
            NSFontAttributeName:self.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize],
            NSForegroundColorAttributeName:foreground
        };
        NSSize size = [self.title sizeWithAttributes:attributes];
        NSRect title = NSMakeRect(NSMidX(self.bounds) - size.width / 2,
            NSMidY(self.bounds) - size.height / 2, size.width, size.height);
        [self.title drawInRect:title withAttributes:attributes];
    }
}

@end
