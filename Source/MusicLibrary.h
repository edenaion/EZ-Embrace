#import <Cocoa/Cocoa.h>
extern NSString * const MusicLibraryPlaylistPasteboardType;

// Immutable property-list snapshot. No artwork or live library objects cross XPC.
@interface MusicLibrarySnapshot : NSObject
@property (nonatomic, readonly) NSArray<NSDictionary *> *tracks;
@property (nonatomic, readonly) NSArray<NSDictionary *> *playlists;
@property (nonatomic, readonly, getter=isComplete) BOOL complete;
@property (nonatomic, readonly) NSDictionary *backupPayload;
- (instancetype) initWithDictionary:(NSDictionary *)dictionary;
- (NSArray<NSDictionary *> *) tracksForPlaylist:(NSString *)identifier search:(NSString *)search
                               sortDescriptors:(NSArray<NSSortDescriptor *> *)descriptors;
+ (NSArray<NSDictionary *> *) columns;
+ (NSString *) displayValueForTrack:(NSDictionary *)track column:(NSString *)column;
+ (NSURL *) importURLForTrack:(NSDictionary *)track;
+ (NSArray<NSURL *> *) importURLsForTracks:(NSArray<NSDictionary *> *)tracks;
@end
