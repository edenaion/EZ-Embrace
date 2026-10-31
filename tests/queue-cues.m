#define main TrackCueHarnessUnusedMain
#include "track-cues.m"
#undef main

#import "TracksController.h"
#import "TrackTableView.h"
#import "TrackTableCellView.h"
#import "TrackTableRowView.h"
#import "MusicLibrary.h"
#import "Preferences.h"
#import "Player.h"
#import "ExportManager.h"

#import <objc/runtime.h>

@interface TracksController (QueueCueTestPrivate)
- (BOOL)writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pasteboard;
- (void)_loadState;
- (void)tableView:(NSTableView *)tableView
  draggingSession:(NSDraggingSession *)session
      endedAtPoint:(NSPoint)screenPoint
         operation:(NSDragOperation)operation;
@end

NSString * const MusicLibraryPlaylistPasteboardType = @"com.ezscape.ez-embrace.music-playlist";
NSString * const PreferencesDidChangeNotification = @"PreferencesDidChangeNotification";

@implementation MusicAppPasteboardParseResult
@end

@implementation Preferences
+ (id)sharedInstance { return nil; }
@end

@implementation Player
+ (instancetype)sharedInstance { return nil; }
@end

@implementation ExportManager
+ (instancetype)sharedInstance { return nil; }
@end

static NSUserDefaults *sQueueTestDefaults;
static NSString *sQueueTestDefaultsSuite;

@interface NSUserDefaults (QueueCueTestDefaults)
+ (NSUserDefaults *)queueCue_testStandardUserDefaults;
@end

@implementation NSUserDefaults (QueueCueTestDefaults)
+ (NSUserDefaults *)queueCue_testStandardUserDefaults
{
    return sQueueTestDefaults;
}
@end

static void QueueCueInstallIsolatedDefaults(void)
{
    sQueueTestDefaultsSuite = [NSString stringWithFormat:@"EZ-Embrace-Queue-Cues-%@", NSUUID.UUID.UUIDString];
    sQueueTestDefaults = [[NSUserDefaults alloc] initWithSuiteName:sQueueTestDefaultsSuite];
    Method original = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
    Method replacement = class_getClassMethod(NSUserDefaults.class, @selector(queueCue_testStandardUserDefaults));
    method_exchangeImplementations(original, replacement);
}

static void QueueCueRestoreDefaults(void)
{
    Method original = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
    Method replacement = class_getClassMethod(NSUserDefaults.class, @selector(queueCue_testStandardUserDefaults));
    method_exchangeImplementations(original, replacement);
}

@implementation MusicAppManager (QueueCueTestSupport)
- (MusicAppPasteboardParseResult *)parsePasteboard:(NSPasteboard *)pasteboard
{
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
        id playlistLocations = [item propertyListForType:MusicLibraryPlaylistPasteboardType];
        if ([playlistLocations isKindOfClass:NSArray.class]) {
            for (id location in playlistLocations) {
                if (![location isKindOfClass:NSString.class]) continue;
                NSURL *url = [NSURL URLWithString:location];
                if (url.isFileURL) [urls addObject:url];
            }
            continue;
        }
        NSString *location = [item propertyListForType:NSPasteboardTypeFileURL];
        if ([location isKindOfClass:NSString.class]) {
            NSURL *url = [NSURL URLWithString:location];
            if (url.isFileURL) [urls addObject:url];
        }
    }
    MusicAppPasteboardParseResult *result = [MusicAppPasteboardParseResult new];
    result.fileURLs = urls;
    result.metadataArray = @[];
    return result;
}
- (void)addPasteboardMetadataArray:(NSArray *)array {}
@end

@implementation TrackTableView
- (NSInteger)rowWithMouseInside { return NSNotFound; }
@end

@interface QueueCueTestTableView : TrackTableView
@property (nonatomic, copy) NSIndexSet *syntheticSelectedRows;
@property (nonatomic) NSUInteger moveCount;
@property (nonatomic) NSInteger lastMoveFrom;
@property (nonatomic) NSInteger lastMoveTo;
@property (nonatomic) NSInteger syntheticDropRow;
@property (nonatomic) NSTableViewDropOperation syntheticDropOperation;
@property (nonatomic) NSUInteger finishDragModificationCount;
@end

@implementation QueueCueTestTableView
- (void)beginUpdates {}
- (void)endUpdates {}
- (void)moveRowAtIndex:(NSInteger)oldIndex toIndex:(NSInteger)newIndex
{
    self.moveCount++;
    self.lastMoveFrom = oldIndex;
    self.lastMoveTo = newIndex;
}
- (void)insertRowsAtIndexes:(NSIndexSet *)indexes withAnimation:(NSTableViewAnimationOptions)animationOptions {}
- (NSIndexSet *)selectedRowIndexes { return self.syntheticSelectedRows ?: [NSIndexSet indexSet]; }
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
    self.syntheticSelectedRows = indexes;
}
- (void)reloadData {}
- (void)setDropRow:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation
{
    self.syntheticDropRow = row;
    self.syntheticDropOperation = dropOperation;
}
- (void)finishDragModification
{
    self.finishDragModificationCount++;
}
@end

@implementation TrackTableCellView
@end

@implementation TrackTableRowView
@end

@interface QueueCueTestDraggingInfo : NSObject <NSDraggingInfo>
@property (nonatomic, strong) NSPasteboard *pasteboard;
@property (nonatomic) NSDragOperation operationMask;
@property NSInteger numberOfValidItemsForDrop;
@property NSDraggingFormation draggingFormation;
@property BOOL animatesToDestination;
@end

@implementation QueueCueTestDraggingInfo
- (NSWindow *)draggingDestinationWindow { return nil; }
- (NSDragOperation)draggingSourceOperationMask { return self.operationMask; }
- (NSPoint)draggingLocation { return NSZeroPoint; }
- (NSPoint)draggedImageLocation { return NSZeroPoint; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return self.pasteboard; }
- (id)draggingSource { return nil; }
- (NSInteger)draggingSequenceNumber { return 0; }
- (void)slideDraggedImageTo:(NSPoint)screenPoint {}
- (NSArray<NSString *> *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination { return nil; }
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)enumOpts
                                  forView:(NSView *)view
                                  classes:(NSArray<Class> *)classArray
                            searchOptions:(NSDictionary<NSPasteboardReadingOptionKey,id> *)searchOptions
                               usingBlock:(void (^)(NSDraggingItem *, NSInteger, BOOL *))block {}
- (NSSpringLoadingHighlight)springLoadingHighlight { return NSSpringLoadingHighlightNone; }
- (void)resetSpringLoading {}
@end

@interface QueueCueTestTracksController : TracksController
@end

@implementation QueueCueTestTracksController
- (void)detectDuplicates {}
@end

NSString *GetBundleIdentifierWithSuffix(NSString *suffix)
{
    return [@"com.ezscape.queue-cues-test" stringByAppendingFormat:@".%@", suffix];
}

void _EmbraceLogMethod(const char *function) {}

static Track *MakeNamedTrack(NSString *name, NSString *supportDirectory)
{
    NSString *path = [supportDirectory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"wav"]];
    NSError *error = nil;
    [name writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    Check(error == nil, [NSString stringWithFormat:@"create %@ track fixture", name]);
    Track *track = MakeTrack([NSURL fileURLWithPath:path]);
    track.cueStartTime = 10.0 + (double)([name characterAtIndex:0] - 'A') * 10.0;
    return track;
}

static QueueCueTestTracksController *MakeController(NSArray<Track *> *tracks, QueueCueTestTableView **outTableView)
{
    QueueCueTestTracksController *controller = [QueueCueTestTracksController new];
    QueueCueTestTableView *tableView = [[QueueCueTestTableView alloc] initWithFrame:NSZeroRect];
    Check(tableView.window == nil, @"test table has no real window");
    [controller setValue:tableView forKey:@"tableView"];
    [controller setValue:[tracks mutableCopy] forKey:@"tracks"];
    if (outTableView) *outTableView = tableView;
    return controller;
}

static NSArray<NSString *> *UUIDOrder(TracksController *controller)
{
    NSMutableArray *result = [NSMutableArray array];
    for (Track *track in controller.tracks) [result addObject:track.UUID.UUIDString];
    return result;
}

static NSDictionary<NSString *, NSNumber *> *CueMap(NSArray<Track *> *tracks)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (Track *track in tracks) result[track.UUID.UUIDString] = @(track.cueStartTime);
    return result;
}

static void AssertTrackOrder(TracksController *controller, NSArray<Track *> *expected, NSString *message)
{
    NSMutableArray *expectedUUIDs = [NSMutableArray array];
    for (Track *track in expected) [expectedUUIDs addObject:track.UUID.UUIDString];
    Check([UUIDOrder(controller) isEqualToArray:expectedUUIDs], message);
}

static void AssertCuesUnchanged(NSArray<Track *> *tracks, NSDictionary<NSString *, NSNumber *> *before, NSString *message)
{
    for (Track *track in tracks) {
        NSNumber *expected = before[track.UUID.UUIDString];
        Check(expected != nil, [NSString stringWithFormat:@"%@ preserves existing UUID %@", message, track.UUID.UUIDString]);
        CheckNear(track.cueStartTime, expected.doubleValue,
                  [NSString stringWithFormat:@"%@ preserves cue for %@", message, track.UUID.UUIDString]);
    }
}

static NSPasteboard *WriteDrag(TracksController *controller, NSIndexSet *indexes, NSDragOperation operationMask)
{
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [pasteboard clearContents];
    Check([controller writeRowsWithIndexes:indexes toPasteboard:pasteboard], @"write drag marker to a real pasteboard");
    return pasteboard;
}

static void MoveRows(QueueCueTestTracksController *controller, NSIndexSet *indexes,
                     NSInteger row, NSDragOperation operationMask, NSString *message)
{
    NSPasteboard *pasteboard = WriteDrag(controller, indexes, operationMask);
    QueueCueTestDraggingInfo *info = [QueueCueTestDraggingInfo new];
    info.pasteboard = pasteboard;
    info.operationMask = operationMask;

    NSDragOperation validated = [controller validateDrop:info proposedRow:row proposedDropOperation:NSTableViewDropAbove];
    Check(validated == ((operationMask & NSDragOperationCopy) ? NSDragOperationCopy : NSDragOperationGeneric),
          [message stringByAppendingString:@" validates the expected operation"]);
    Check([controller acceptDrop:info row:row dropOperation:NSTableViewDropAbove],
          [message stringByAppendingString:@" is accepted by the production drop path"]);
}

static void DropRowsOnRow(QueueCueTestTracksController *controller,
                          QueueCueTestTableView *tableView,
                          NSIndexSet *indexes,
                          NSInteger targetRow,
                          NSInteger expectedInsertionRow,
                          NSDragOperation operationMask,
                          NSString *message)
{
    NSPasteboard *pasteboard = WriteDrag(controller, indexes, operationMask);
    QueueCueTestDraggingInfo *info = [QueueCueTestDraggingInfo new];
    info.pasteboard = pasteboard;
    info.operationMask = operationMask;

    NSDragOperation expectedOperation =
        ((operationMask & (NSDragOperationGeneric | NSDragOperationCopy)) == NSDragOperationCopy)
            ? NSDragOperationCopy
            : NSDragOperationGeneric;
    Check([controller validateDrop:info
                      proposedRow:targetRow
            proposedDropOperation:NSTableViewDropOn] == expectedOperation,
          [message stringByAppendingString:@" validates the expected operation"]);
    Check(tableView.syntheticDropRow == expectedInsertionRow &&
          tableView.syntheticDropOperation == NSTableViewDropAbove,
          [message stringByAppendingString:@" resolves to the expected insertion line"]);
    Check([controller acceptDrop:info row:targetRow dropOperation:NSTableViewDropOn],
          [message stringByAppendingString:@" is accepted without relying on a second delegate callback"]);
}

static NSPasteboard *WriteExternalDrag(NSArray<NSURL *> *urls, BOOL playlistRepresentation)
{
    static NSPasteboard *pasteboard;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ pasteboard = [NSPasteboard pasteboardWithUniqueName]; });
    [pasteboard clearContents];
    if (playlistRepresentation) {
        NSPasteboardItem *item = [NSPasteboardItem new];
        NSMutableArray<NSString *> *locations = [NSMutableArray array];
        for (NSURL *url in urls) [locations addObject:url.absoluteString];
        [item setPropertyList:locations forType:MusicLibraryPlaylistPasteboardType];
        Check([pasteboard writeObjects:@[ item ]], @"write Music Library playlist drag data");
    } else {
        Check([pasteboard writeObjects:urls], @"write Music Library track drag data");
    }
    return pasteboard;
}

static void DropExternalURLs(QueueCueTestTracksController *controller, NSArray<NSURL *> *urls,
                             BOOL playlistRepresentation, NSInteger row, NSString *message)
{
    QueueCueTestDraggingInfo *info = [QueueCueTestDraggingInfo new];
    info.pasteboard = WriteExternalDrag(urls, playlistRepresentation);
    info.operationMask = NSDragOperationCopy;
    Check([controller validateDrop:info proposedRow:row proposedDropOperation:NSTableViewDropAbove] == NSDragOperationCopy,
          [message stringByAppendingString:@" validates as an external copy"]);
    Check(info.numberOfValidItemsForDrop == (NSInteger)urls.count,
          [message stringByAppendingString:@" reports every local item"]);
    Check([controller acceptDrop:info row:row dropOperation:NSTableViewDropAbove],
          [message stringByAppendingString:@" is accepted by the production drop path"]);
}

static void CheckSavedUUIDOrder(NSArray<NSString *> *expected, NSString *message)
{
    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:@"track-uuids"];
    Check([saved isEqualToArray:expected], message);
}

int main(void)
{
    @autoreleasepool {
        QueueCueInstallIsolatedDefaults();

        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"EZ-Embrace-queue-cues-%@", NSUUID.UUID.UUIDString]];
        sSupportDirectory = directory;
        sAppDelegate = [AppDelegate new];
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
        Check(error == nil, @"create isolated Track support directory");

        Track *a = MakeNamedTrack(@"A", directory);
        Track *b = MakeNamedTrack(@"B", directory);
        Track *c = MakeNamedTrack(@"C", directory);
        NSArray<Track *> *originalTracks = @[ a, b, c ];
        NSDictionary *originalCues = CueMap(originalTracks);
        QueueCueTestTableView *tableView = nil;
        QueueCueTestTracksController *controller = MakeController(originalTracks, &tableView);

        [controller saveState];
        CheckSavedUUIDOrder(@[ a.UUID.UUIDString, b.UUID.UUIDString, c.UUID.UUIDString ],
                            @"production saveState writes the initial entry order to isolated defaults");
        Check(controller.firstQueuedTrack == a, @"the planned next provider starts with the first queued entry");

        MoveRows(controller, [NSIndexSet indexSetWithIndex:0], 3, NSDragOperationGeneric, @"move a queued entry forward");
        AssertTrackOrder(controller, @[ b, c, a ], @"forward move reorders the original entry objects");
        AssertCuesUnchanged(originalTracks, originalCues, @"forward move");
        Check(controller.firstQueuedTrack == b, @"first queued provider follows the forward-moved order");
        CheckSavedUUIDOrder(@[ b.UUID.UUIDString, c.UUID.UUIDString, a.UUID.UUIDString ],
                            @"accepted forward move persists the new UUID order");

        MoveRows(controller, [NSIndexSet indexSetWithIndex:2], 0, NSDragOperationGeneric, @"move a queued entry backward");
        AssertTrackOrder(controller, @[ a, b, c ], @"backward move restores the original entry order");
        AssertCuesUnchanged(originalTracks, originalCues, @"backward move");

        NSMutableIndexSet *multipleRows = [NSMutableIndexSet indexSet];
        [multipleRows addIndex:0];
        [multipleRows addIndex:2];
        MoveRows(controller, multipleRows, 3, NSDragOperationGeneric, @"move multiple queued entries");
        AssertTrackOrder(controller, @[ b, a, c ], @"multi-select move keeps selected entries in their drag order");
        AssertCuesUnchanged(originalTracks, originalCues, @"multi-select move");
        Check(controller.firstQueuedTrack == b, @"first queued provider follows the multi-select result");

        NSPasteboard *copyPasteboard = WriteDrag(controller, [NSIndexSet indexSetWithIndex:0], NSDragOperationCopy);
        QueueCueTestDraggingInfo *copyInfo = [QueueCueTestDraggingInfo new];
        copyInfo.pasteboard = copyPasteboard;
        copyInfo.operationMask = NSDragOperationCopy;
        Track *copySource = controller.tracks[0];
        NSUUID *copySourceUUID = copySource.UUID;
        NSTimeInterval copySourceCue = copySource.cueStartTime;
        Check([controller validateDrop:copyInfo proposedRow:3 proposedDropOperation:NSTableViewDropAbove] == NSDragOperationCopy,
              @"copy drag validates as a copy operation");
        Check([controller acceptDrop:copyInfo row:3 dropOperation:NSTableViewDropAbove],
              @"copy drag is accepted by the production drop path");
        Track *duplicate = controller.tracks[3];
        Check(![duplicate.UUID isEqual:copySourceUUID], @"copy creates an entry with a new UUID");
        CheckNear(duplicate.cueStartTime, 0, @"copy starts with no single-use cue");
        Check([copySource.UUID isEqual:copySourceUUID], @"copy leaves the source UUID unchanged");
        CheckNear(copySource.cueStartTime, copySourceCue, @"copy leaves the source cue unchanged");
        CheckNear(a.cueStartTime, [originalCues[a.UUID.UUIDString] doubleValue], @"copy leaves another queued cue unchanged");
        Check(controller.firstQueuedTrack == b, @"copy leaves the first queued entry in the same position");

        Track *cancelledDragQueued = MakeNamedTrack(@"cancelled-drag-queued", directory);
        Track *cancelledDragPlayed = MakeNamedTrack(@"cancelled-drag-played", directory);
        cancelledDragPlayed.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *cancelledDragTableView = nil;
        QueueCueTestTracksController *cancelledDragController =
            MakeController(@[ cancelledDragQueued, cancelledDragPlayed ], &cancelledDragTableView);
        WriteDrag(cancelledDragController, [NSIndexSet indexSetWithIndex:1], NSDragOperationGeneric);
        [cancelledDragController tableView:cancelledDragTableView
                           draggingSession:nil
                               endedAtPoint:NSZeroPoint
                                  operation:NSDragOperationGeneric];
        Check(cancelledDragTableView.finishDragModificationCount == 1,
              @"ending a rejected or cancelled local drag releases the playback-transition guard");

        Track *queued = MakeNamedTrack(@"D", directory);
        Track *played = MakeNamedTrack(@"E", directory);
        Track *olderPlayed = MakeNamedTrack(@"F", directory);
        played.trackStatus = TrackStatusPlayed;
        olderPlayed.trackStatus = TrackStatusPlayed;
        NSUUID *playedUUID = played.UUID;
        NSTimeInterval playedCue = played.cueStartTime;
        Check(played.playedTime > 0, @"played fixture has a played timestamp before requeue");
        QueueCueTestTableView *lockedTableView = nil;
        QueueCueTestTracksController *lockedController = MakeController(@[ queued, played, olderPlayed ], &lockedTableView);
        NSPasteboard *playedPasteboard = WriteDrag(lockedController, [NSIndexSet indexSetWithIndex:1], NSDragOperationGeneric);
        QueueCueTestDraggingInfo *playedInfo = [QueueCueTestDraggingInfo new];
        playedInfo.pasteboard = playedPasteboard;
        playedInfo.operationMask = NSDragOperationGeneric;
        Check([playedPasteboard dataForType:EmbraceLockedTrackPasteboardType] != nil,
              @"played row drag uses the locked marker");
        Check([lockedController validateDrop:playedInfo proposedRow:0 proposedDropOperation:NSTableViewDropAbove] == NSDragOperationGeneric,
              @"played row validates when dragged upward across the history divider");
        Check([lockedController acceptDrop:playedInfo row:0 dropOperation:NSTableViewDropAbove],
              @"played row drop is accepted by the production drop path");
        AssertTrackOrder(lockedController, @[ played, queued, olderPlayed ],
                         @"played row enters the requested Up Next position above history");
        Check(played.trackStatus == TrackStatusQueued, @"played row becomes queued after crossing the divider");
        Check(played.playedTime == 0, @"requeued row clears its played timestamp");
        Check([played.UUID isEqual:playedUUID], @"requeue keeps the original entry UUID");
        CheckNear(played.cueStartTime, playedCue, @"requeue keeps the entry cue attached");
        Check(lockedController.firstQueuedTrack == played, @"requeued row becomes the next provider entry at row zero");
        CheckSavedUUIDOrder(@[ played.UUID.UUIDString, queued.UUID.UUIDString, olderPlayed.UUID.UUIDString ],
                            @"accepted played-row requeue persists the new UUID order");

        Track *copyQueued = MakeNamedTrack(@"T", directory);
        Track *copyPlayed = MakeNamedTrack(@"U", directory);
        copyPlayed.trackStatus = TrackStatusPlayed;
        NSUUID *copyPlayedUUID = copyPlayed.UUID;
        QueueCueTestTracksController *playedCopyController = MakeController(@[ copyQueued, copyPlayed ], NULL);
        NSPasteboard *playedCopyPasteboard = WriteDrag(playedCopyController, [NSIndexSet indexSetWithIndex:1], NSDragOperationCopy);
        QueueCueTestDraggingInfo *playedCopyInfo = [QueueCueTestDraggingInfo new];
        playedCopyInfo.pasteboard = playedCopyPasteboard;
        playedCopyInfo.operationMask = NSDragOperationCopy;
        Check([playedCopyController validateDrop:playedCopyInfo proposedRow:0 proposedDropOperation:NSTableViewDropAbove] == NSDragOperationCopy,
              @"Option-dragging played history preserves explicit copy behavior");
        Check([playedCopyController acceptDrop:playedCopyInfo row:0 dropOperation:NSTableViewDropAbove],
              @"played-history copy is accepted above the divider");
        Track *playedDuplicate = playedCopyController.tracks[0];
        AssertTrackOrder(playedCopyController, @[ playedDuplicate, copyQueued, copyPlayed ],
                         @"played-history copy enters Up Next without moving its source");
        Check(![playedDuplicate.UUID isEqual:copyPlayedUUID], @"played-history copy receives a new UUID");
        CheckNear(playedDuplicate.cueStartTime, 0, @"played-history copy starts with no cue");
        Check(copyPlayed.trackStatus == TrackStatusPlayed, @"played-history copy leaves the source played");

        Track *dropOnQueuedA = MakeNamedTrack(@"V-drop-on-a", directory);
        Track *dropOnQueuedB = MakeNamedTrack(@"W-drop-on-b", directory);
        Track *dropOnPlayed = MakeNamedTrack(@"X-drop-on-played", directory);
        dropOnPlayed.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *dropOnTableView = nil;
        QueueCueTestTracksController *dropOnController =
            MakeController(@[ dropOnQueuedA, dropOnQueuedB, dropOnPlayed ], &dropOnTableView);
        DropRowsOnRow(dropOnController, dropOnTableView,
                      [NSIndexSet indexSetWithIndex:2], 0, 1, NSDragOperationGeneric,
                      @"played row dropped on an Up Next row");
        AssertTrackOrder(dropOnController, @[ dropOnQueuedA, dropOnPlayed, dropOnQueuedB ],
                         @"played-row drop on Up Next enters immediately after the target");
        Check(dropOnPlayed.trackStatus == TrackStatusQueued,
              @"played-row drop-on changes the original entry to queued");

        Track *playedOnlyA = MakeNamedTrack(@"Y-played-only-a", directory);
        Track *playedOnlyB = MakeNamedTrack(@"Z-played-only-b", directory);
        playedOnlyA.trackStatus = TrackStatusPlayed;
        playedOnlyB.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *playedOnlyTableView = nil;
        QueueCueTestTracksController *playedOnlyController =
            MakeController(@[ playedOnlyA, playedOnlyB ], &playedOnlyTableView);
        DropRowsOnRow(playedOnlyController, playedOnlyTableView,
                      [NSIndexSet indexSetWithIndex:1], 0, 0, NSDragOperationGeneric,
                      @"played-only row dropped on the first history row");
        AssertTrackOrder(playedOnlyController, @[ playedOnlyB, playedOnlyA ],
                         @"played-only drop-on puts the dragged entry above history");
        Check(playedOnlyB.trackStatus == TrackStatusQueued,
              @"played-only drop-on requeues the dragged entry");

        Track *activeDropTarget = MakeNamedTrack(@"A-active-drop-target", directory);
        Track *activeDropQueued = MakeNamedTrack(@"B-active-drop-queued", directory);
        Track *activeDropPlayed = MakeNamedTrack(@"C-active-drop-played", directory);
        activeDropTarget.trackStatus = TrackStatusPlaying;
        activeDropPlayed.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *activeDropTableView = nil;
        QueueCueTestTracksController *activeDropController =
            MakeController(@[ activeDropTarget, activeDropQueued, activeDropPlayed ], &activeDropTableView);
        DropRowsOnRow(activeDropController, activeDropTableView,
                      [NSIndexSet indexSetWithIndex:2], 0, 1, NSDragOperationGeneric,
                      @"played row dropped on the active track");
        AssertTrackOrder(activeDropController, @[ activeDropTarget, activeDropPlayed, activeDropQueued ],
                         @"active playback stays first when history is requeued by dropping on it");

        Track *queuedDropOnA = MakeNamedTrack(@"D-queued-drop-on-a", directory);
        Track *queuedDropOnB = MakeNamedTrack(@"E-queued-drop-on-b", directory);
        Track *queuedDropOnC = MakeNamedTrack(@"F-queued-drop-on-c", directory);
        QueueCueTestTableView *queuedDropOnTableView = nil;
        QueueCueTestTracksController *queuedDropOnController =
            MakeController(@[ queuedDropOnA, queuedDropOnB, queuedDropOnC ], &queuedDropOnTableView);
        DropRowsOnRow(queuedDropOnController, queuedDropOnTableView,
                      [NSIndexSet indexSetWithIndex:2], 0, 1, NSDragOperationGeneric,
                      @"queued row dropped on another queued row");
        AssertTrackOrder(queuedDropOnController, @[ queuedDropOnA, queuedDropOnC, queuedDropOnB ],
                         @"queued-row drop-on reorders immediately after the target");

        Track *copyOnQueued = MakeNamedTrack(@"G-copy-on-queued", directory);
        Track *copyOnPlayed = MakeNamedTrack(@"H-copy-on-played", directory);
        copyOnPlayed.trackStatus = TrackStatusPlayed;
        NSUUID *copyOnSourceUUID = copyOnPlayed.UUID;
        QueueCueTestTableView *copyOnTableView = nil;
        QueueCueTestTracksController *copyOnController =
            MakeController(@[ copyOnQueued, copyOnPlayed ], &copyOnTableView);
        DropRowsOnRow(copyOnController, copyOnTableView,
                      [NSIndexSet indexSetWithIndex:1], 0, 1, NSDragOperationCopy,
                      @"Option-copy of played history dropped on Up Next");
        Track *copyOnDuplicate = copyOnController.tracks[1];
        AssertTrackOrder(copyOnController, @[ copyOnQueued, copyOnDuplicate, copyOnPlayed ],
                         @"played-history drop-on copy inserts after its Up Next target");
        Check(![copyOnDuplicate.UUID isEqual:copyOnSourceUUID],
              @"played-history drop-on copy receives a new UUID");
        Check(copyOnDuplicate.trackStatus == TrackStatusQueued,
              @"played-history drop-on copy is queued");
        Check(copyOnPlayed.trackStatus == TrackStatusPlayed,
              @"played-history drop-on copy leaves its source in history");
        CheckNear(copyOnDuplicate.cueStartTime, 0,
                  @"played-history drop-on copy starts with its flag Off");

        Track *multiQueuedA = MakeNamedTrack(@"I-multi-queued-a", directory);
        Track *multiQueuedB = MakeNamedTrack(@"J-multi-queued-b", directory);
        Track *multiPlayedA = MakeNamedTrack(@"K-multi-played-a", directory);
        Track *multiPlayedB = MakeNamedTrack(@"L-multi-played-b", directory);
        Track *multiPlayedC = MakeNamedTrack(@"M-multi-played-c", directory);
        Track *multiPlayedD = MakeNamedTrack(@"N-multi-played-d", directory);
        multiPlayedA.trackStatus = TrackStatusPlayed;
        multiPlayedB.trackStatus = TrackStatusPlayed;
        multiPlayedC.trackStatus = TrackStatusPlayed;
        multiPlayedD.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *multiPlayedTableView = nil;
        QueueCueTestTracksController *multiPlayedController =
            MakeController(@[ multiQueuedA, multiQueuedB, multiPlayedA, multiPlayedB,
                              multiPlayedC, multiPlayedD ],
                           &multiPlayedTableView);
        NSMutableIndexSet *noncontiguousPlayedRows = [NSMutableIndexSet indexSetWithIndex:2];
        [noncontiguousPlayedRows addIndex:4];
        DropRowsOnRow(multiPlayedController, multiPlayedTableView,
                      noncontiguousPlayedRows, 0, 1, NSDragOperationGeneric,
                      @"noncontiguous played selection dropped on Up Next");
        AssertTrackOrder(multiPlayedController,
                         @[ multiQueuedA, multiPlayedA, multiPlayedC, multiQueuedB,
                            multiPlayedB, multiPlayedD ],
                         @"multi-row history replay preserves selected order and remaining history");
        Check(multiPlayedA.trackStatus == TrackStatusQueued &&
              multiPlayedC.trackStatus == TrackStatusQueued &&
              multiPlayedB.trackStatus == TrackStatusPlayed,
              @"multi-row replay requeues only the dragged history entries");

        NSPasteboard *deepHistoryPasteboard =
            WriteDrag(multiPlayedController, [NSIndexSet indexSetWithIndex:5], NSDragOperationGeneric);
        QueueCueTestDraggingInfo *deepHistoryInfo = [QueueCueTestDraggingInfo new];
        deepHistoryInfo.pasteboard = deepHistoryPasteboard;
        deepHistoryInfo.operationMask = NSDragOperationGeneric;
        Check([multiPlayedController validateDrop:deepHistoryInfo
                                      proposedRow:5
                            proposedDropOperation:NSTableViewDropOn] == NSDragOperationNone,
              @"drop on deeper played history remains invalid");
        Check(![multiPlayedController acceptDrop:deepHistoryInfo row:5 dropOperation:NSTableViewDropOn],
              @"deeper-history drop-on is rejected by the production path");

        NSPasteboard *historyPasteboard = WriteDrag(lockedController, [NSIndexSet indexSetWithIndex:2], NSDragOperationGeneric);
        QueueCueTestDraggingInfo *historyInfo = [QueueCueTestDraggingInfo new];
        historyInfo.pasteboard = historyPasteboard;
        historyInfo.operationMask = NSDragOperationGeneric;
        Check([lockedController validateDrop:historyInfo proposedRow:3 proposedDropOperation:NSTableViewDropAbove] == NSDragOperationNone,
              @"played row cannot be rearranged inside played history");
        Check(![lockedController acceptDrop:historyInfo row:3 dropOperation:NSTableViewDropAbove],
              @"invalid played-history drop is rejected by the production drop path");
        AssertTrackOrder(lockedController, @[ played, queued, olderPlayed ],
                         @"rejected history-only drop leaves order unchanged");

        NSMutableIndexSet *mixedRows = [NSMutableIndexSet indexSet];
        [mixedRows addIndex:1];
        [mixedRows addIndex:2];
        NSPasteboard *mixedPasteboard = [NSPasteboard pasteboardWithUniqueName];
        [mixedPasteboard clearContents];
        Check(![lockedController writeRowsWithIndexes:mixedRows toPasteboard:mixedPasteboard],
              @"mixed played and queued selection is rejected at drag start");
        AssertTrackOrder(lockedController, @[ played, queued, olderPlayed ], @"rejected mixed drag leaves the order unchanged");

        Track *active = MakeNamedTrack(@"G", directory);
        Track *activeHistory = MakeNamedTrack(@"S", directory);
        active.trackStatus = TrackStatusPlaying;
        activeHistory.trackStatus = TrackStatusPlayed;
        QueueCueTestTracksController *activeController = MakeController(@[ active, queued, activeHistory ], NULL);
        NSPasteboard *activePasteboard = [NSPasteboard pasteboardWithUniqueName];
        [activePasteboard clearContents];
        Check(![activeController writeRowsWithIndexes:[NSIndexSet indexSetWithIndex:0] toPasteboard:activePasteboard],
              @"playing row is rejected at drag start");
        NSPasteboard *activeHistoryPasteboard = WriteDrag(activeController, [NSIndexSet indexSetWithIndex:2], NSDragOperationGeneric);
        QueueCueTestDraggingInfo *activeHistoryInfo = [QueueCueTestDraggingInfo new];
        activeHistoryInfo.pasteboard = activeHistoryPasteboard;
        activeHistoryInfo.operationMask = NSDragOperationGeneric;
        Check([activeController validateDrop:activeHistoryInfo proposedRow:0 proposedDropOperation:NSTableViewDropAbove] == NSDragOperationNone,
              @"played row cannot move above the active track");
        Check([activeController validateDrop:activeHistoryInfo proposedRow:1 proposedDropOperation:NSTableViewDropAbove] == NSDragOperationGeneric,
              @"played row can become the first Up Next entry after the active track");
        Check([activeController acceptDrop:activeHistoryInfo row:1 dropOperation:NSTableViewDropAbove],
              @"played row requeues during active playback");
        AssertTrackOrder(activeController, @[ active, activeHistory, queued ],
                         @"active playback stays first while requeued history becomes next");
        Check(activeHistory.trackStatus == TrackStatusQueued,
              @"history requeued during playback becomes queued");

        Track *finished = MakeNamedTrack(@"H", directory);
        Track *remaining = MakeNamedTrack(@"I", directory);
        Track *previouslyPlayed = MakeNamedTrack(@"J", directory);
        finished.trackStatus = TrackStatusPlayed;
        previouslyPlayed.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *completionTableView = nil;
        QueueCueTestTracksController *completionController = MakeController(@[ finished, remaining, previouslyPlayed ], &completionTableView);
        [completionController saveState];
        [completionController didFinishTrack:finished];
        AssertTrackOrder(completionController, @[ finished, remaining, previouslyPlayed ],
                         @"completed current track stays gray in its timeline position");
        Check(completionController.firstQueuedTrack == remaining,
              @"completion leaves the first remaining Up Next row as provider entry");
        CheckSavedUUIDOrder(@[ finished.UUID.UUIDString, remaining.UUID.UUIDString, previouslyPlayed.UUID.UUIDString ],
                            @"completion preserves persisted timeline order");
        Check(completionTableView.moveCount == 0, @"completion does not move a visible table row");

        NSPasteboard *recentPlayedPasteboard = WriteDrag(completionController, [NSIndexSet indexSetWithIndex:0], NSDragOperationGeneric);
        QueueCueTestDraggingInfo *recentPlayedInfo = [QueueCueTestDraggingInfo new];
        recentPlayedInfo.pasteboard = recentPlayedPasteboard;
        recentPlayedInfo.operationMask = NSDragOperationGeneric;
        Check([completionController validateDrop:recentPlayedInfo proposedRow:2 proposedDropOperation:NSTableViewDropAbove] == NSDragOperationGeneric,
              @"gray timeline row can still be dragged into Up Next");
        Check([completionController acceptDrop:recentPlayedInfo row:2 dropOperation:NSTableViewDropAbove],
              @"gray timeline row manual requeue is accepted");
        AssertTrackOrder(completionController, @[ remaining, finished, previouslyPlayed ],
                         @"manual requeue places gray timeline row at requested queue position");
        Check(finished.trackStatus == TrackStatusQueued,
              @"manual drag changes completed timeline row back to queued");

        Track *importQueued = MakeNamedTrack(@"K", directory);
        Track *importHistory = MakeNamedTrack(@"L", directory);
        importHistory.trackStatus = TrackStatusPlayed;
        QueueCueTestTracksController *importController = MakeController(@[ importQueued, importHistory ], NULL);
        NSString *importPath = [directory stringByAppendingPathComponent:@"M.wav"];
        [@"M" writeToFile:importPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        Check(error == nil, @"create import-order fixture");
        Check([importController addTracksWithURLs:@[ [NSURL fileURLWithPath:importPath] ]],
              @"production add path accepts a queued fixture with played history present");
        Track *importedTrack = importController.tracks[1];
        AssertTrackOrder(importController, @[ importQueued, importedTrack, importHistory ],
                         @"new imports enter Up Next before played history");
        Check(importedTrack.trackStatus == TrackStatusQueued, @"new import remains queued above history");

        Track *externalQueued = MakeNamedTrack(@"V", directory);
        Track *externalHistory = MakeNamedTrack(@"W", directory);
        externalHistory.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *externalTableView = nil;
        QueueCueTestTracksController *externalController = MakeController(@[ externalQueued, externalHistory ], &externalTableView);
        NSMutableArray<Track *> *externallyImportedTracks = [NSMutableArray array];
        NSMutableArray<NSURL *> *externalURLs = [NSMutableArray array];
        for (NSString *name in @[ @"Library one.wav", @"Library two.wav", @"Library three.wav", @"Library duplicate.wav" ]) {
            NSString *path = [directory stringByAppendingPathComponent:name];
            Check([name writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error],
                  [NSString stringWithFormat:@"create %@ Music Library drag fixture", name]);
            [externalURLs addObject:[NSURL fileURLWithPath:path]];
        }

        DropExternalURLs(externalController, @[ externalURLs[0] ], NO, 0,
                         @"single Music Library track drop at the top of Up Next");
        Track *externalTop = externalController.tracks[0];
        [externallyImportedTracks addObject:externalTop];
        AssertTrackOrder(externalController, @[ externalTop, externalQueued, externalHistory ],
                         @"single external drop enters the requested top position");
        Check(externalTop.trackStatus == TrackStatusQueued, @"single external drop is queued");
        CheckNear(externalTop.cueStartTime, 0, @"single external drop starts with its flag Off");

        DropExternalURLs(externalController, @[ externalURLs[1], externalURLs[2] ], YES, 2,
                         @"Music Library playlist drop at the bottom of Up Next");
        Track *externalMiddleA = externalController.tracks[2];
        Track *externalMiddleB = externalController.tracks[3];
        [externallyImportedTracks addObjectsFromArray:@[ externalMiddleA, externalMiddleB ]];
        AssertTrackOrder(externalController, @[ externalTop, externalQueued, externalMiddleA, externalMiddleB, externalHistory ],
                         @"playlist drop preserves source order above played history");
        Check(externalMiddleA.trackStatus == TrackStatusQueued && externalMiddleB.trackStatus == TrackStatusQueued,
              @"every playlist-drop entry is queued");
        CheckNear(externalMiddleA.cueStartTime, 0, @"first playlist-drop entry starts with its flag Off");
        CheckNear(externalMiddleB.cueStartTime, 0, @"second playlist-drop entry starts with its flag Off");

        DropExternalURLs(externalController, @[ externalURLs[3] ], NO, 1,
                         @"Music Library track drop into the middle of Up Next");
        Track *externalInserted = externalController.tracks[1];
        [externallyImportedTracks addObject:externalInserted];
        AssertTrackOrder(externalController,
                         @[ externalTop, externalInserted, externalQueued, externalMiddleA, externalMiddleB, externalHistory ],
                         @"external middle drop keeps all queue and history sections canonical");
        CheckNear(externalInserted.cueStartTime, 0, @"middle external drop starts with its flag Off");

        QueueCueTestDraggingInfo *dropOnInfo = [QueueCueTestDraggingInfo new];
        dropOnInfo.pasteboard = WriteExternalDrag(@[ externalURLs[0] ], NO);
        dropOnInfo.operationMask = NSDragOperationCopy;
        Check([externalController validateDrop:dropOnInfo proposedRow:0 proposedDropOperation:NSTableViewDropOn] == NSDragOperationCopy,
              @"external drop on an Up Next row validates as a copy");
        Check(externalTableView.syntheticDropRow == 1 && externalTableView.syntheticDropOperation == NSTableViewDropAbove,
              @"drop on an Up Next row converts to an insertion line after that row");
        Check([externalController acceptDrop:dropOnInfo row:0 dropOperation:NSTableViewDropOn],
              @"external row drop is accepted without relying on a second delegate callback");
        Track *externalDuplicate = externalController.tracks[1];
        [externallyImportedTracks addObject:externalDuplicate];
        Check(![externalDuplicate.UUID isEqual:externalTop.UUID], @"reimporting one Music source creates an independent entry UUID");
        CheckNear(externalDuplicate.cueStartTime, 0, @"reimported Music source does not inherit another entry cue");
        Check(externalHistory.trackStatus == TrackStatusPlayed && externalController.tracks.lastObject == externalHistory,
              @"all external drop forms leave played history below Up Next");
        CheckSavedUUIDOrder(UUIDOrder(externalController), @"accepted external drops persist their exact UUID order");

        Track *loadQueued = MakeNamedTrack(@"N", directory);
        Track *loadHistory = MakeNamedTrack(@"O", directory);
        loadHistory.trackStatus = TrackStatusPlayed;
        [NSUserDefaults.standardUserDefaults setObject:@[ loadHistory.UUID.UUIDString, loadQueued.UUID.UUIDString ]
                                                forKey:@"track-uuids"];
        QueueCueTestTracksController *loadController = MakeController(@[], NULL);
        [loadController _loadState];
        Check([[(Track *)loadController.tracks[0] UUID] isEqual:loadHistory.UUID],
              @"restart preserves a gray track in its saved timeline position");
        Check([[(Track *)loadController.tracks[1] UUID] isEqual:loadQueued.UUID],
              @"restart preserves the following queued row");
        CheckSavedUUIDOrder(@[ loadHistory.UUID.UUIDString, loadQueued.UUID.UUIDString ],
                            @"restart leaves saved timeline order unchanged");

        Track *markQueuedA = MakeNamedTrack(@"P", directory);
        Track *markQueuedB = MakeNamedTrack(@"Q", directory);
        Track *markHistory = MakeNamedTrack(@"R", directory);
        markHistory.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *markTableView = nil;
        QueueCueTestTracksController *markController = MakeController(@[ markQueuedA, markQueuedB, markHistory ], &markTableView);
        markTableView.syntheticSelectedRows = [NSIndexSet indexSetWithIndex:0];
        [markController toggleMarkAsPlayed:nil];
        AssertTrackOrder(markController, @[ markQueuedB, markQueuedA, markHistory ],
                         @"Mark as Played moves an Up Next row below the divider");
        Check(markQueuedA.trackStatus == TrackStatusPlayed, @"Mark as Played updates queued row status");
        markTableView.syntheticSelectedRows = [NSIndexSet indexSetWithIndex:1];
        [markController toggleMarkAsPlayed:nil];
        AssertTrackOrder(markController, @[ markQueuedB, markQueuedA, markHistory ],
                         @"unmarking the first history row places it at the end of Up Next");
        Check(markQueuedA.trackStatus == TrackStatusQueued, @"unmarking played history restores queued status");

        TrackTableRowView *upNextRow = (TrackTableRowView *)[lockedController tableView:lockedTableView rowViewForRow:0];
        TrackTableRowView *historyRow = (TrackTableRowView *)[lockedController tableView:lockedTableView rowViewForRow:2];
        Check(!upNextRow.endsLastPlayedTrack, @"Up Next row does not draw the last-played divider");
        Check(historyRow.endsLastPlayedTrack, @"Most recently played row draws the solid divider below itself");

        Track *olderDividerTrack = MakeNamedTrack(@"Older divider history", directory);
        olderDividerTrack.trackStatus = TrackStatusPlayed;
        Track *queuedDividerTrack = MakeNamedTrack(@"Queued after latest", directory);
        Track *latestDividerTrack = MakeNamedTrack(@"Latest played", directory);
        latestDividerTrack.trackStatus = TrackStatusPlayed;
        QueueCueTestTableView *dividerTableView = nil;
        QueueCueTestTracksController *dividerController = MakeController(
            @[ latestDividerTrack, queuedDividerTrack, olderDividerTrack ], &dividerTableView);
        TrackTableRowView *latestDividerRow = (TrackTableRowView *)[dividerController tableView:dividerTableView rowViewForRow:0];
        TrackTableRowView *olderDividerRow = (TrackTableRowView *)[dividerController tableView:dividerTableView rowViewForRow:2];
        Check(latestDividerRow.endsLastPlayedTrack && !olderDividerRow.endsLastPlayedTrack,
              @"Divider follows the latest played timestamp instead of trailing older history");

        Check(tableView.window == nil, @"all queue moves ran against a table without a window");

        NSMutableArray<Track *> *allTracks = [NSMutableArray arrayWithArray:originalTracks];
        [allTracks addObject:duplicate];
        [allTracks addObjectsFromArray:@[ queued, played, olderPlayed, copyQueued, copyPlayed, playedDuplicate,
                                          active, activeHistory, finished, remaining, previouslyPlayed,
                                          importQueued, importHistory, importedTrack, loadQueued, loadHistory ]];
        [allTracks addObjectsFromArray:@[ markQueuedA, markQueuedB, markHistory ]];
        [allTracks addObjectsFromArray:@[ olderDividerTrack, queuedDividerTrack, latestDividerTrack ]];
        [allTracks addObjectsFromArray:@[ externalQueued, externalHistory ]];
        [allTracks addObjectsFromArray:externallyImportedTracks];
        for (Track *track in allTracks) [track clearAndCleanup];
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];

        [sQueueTestDefaults removePersistentDomainForName:sQueueTestDefaultsSuite];
        QueueCueRestoreDefaults();
        printf("PASS: %lu queue/drop and cue assertions\n", (unsigned long)sAssertions);
    }
    return 0;
}
