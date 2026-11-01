#import <Cocoa/Cocoa.h>
@class MusicLibrarySnapshot;

@interface MusicLibraryController : NSWindowController
// A supplied snapshot keeps fixture tests independent of the user's Music library.
- (instancetype) initWithSnapshot:(MusicLibrarySnapshot *)snapshot importHandler:(void (^)(NSArray<NSURL *> *))handler;
@end
