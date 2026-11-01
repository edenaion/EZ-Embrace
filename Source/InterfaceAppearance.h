#import <Cocoa/Cocoa.h>

extern NSString * const WindowLayoutEqualizer;

// Owns one coordinate transform per app window. Native window chrome is unchanged.
@interface InterfaceAppearance : NSObject
+ (void) installInWindow:(NSWindow *)window;
+ (void) installInWindow:(NSWindow *)window designSize:(NSSize)designSize;
+ (BOOL) isInstalledInWindow:(NSWindow *)window;
+ (void) setAllowsIndependentResizeAxes:(BOOL)allowed inWindow:(NSWindow *)window;
+ (void) setBorderIdentifier:(NSString *)identifier inWindow:(NSWindow *)window;
+ (NSView *) contentViewForWindow:(NSWindow *)window;
+ (void) setContentSize:(NSSize)size inWindow:(NSWindow *)window;
+ (void) setFont:(NSFont *)font forControl:(NSControl *)control;
+ (void) setTextColor:(NSColor *)color forField:(NSTextField *)field;
+ (void) setTextColor:(NSColor *)color forField:(NSTextField *)field appliesContrast:(BOOL)appliesContrast;
+ (NSDictionary<NSString *, NSValue *> *) automaticWindowFramesForVisibleFrame:(NSRect)visibleFrame;
+ (NSRect) frame:(NSRect)frame constrainedToVisibleFrame:(NSRect)visibleFrame;
+ (void) applyAutomaticFrame:(NSRect)frame toWindow:(NSWindow *)window;
+ (NSColor *) blushSetListColor;
+ (NSColor *) blushCurrentTrackColor;
+ (NSColor *) blushMusicLibraryColor;
@end
