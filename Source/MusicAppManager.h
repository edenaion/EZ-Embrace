// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

extern NSString * const MusicAppManagerDidUpdateLibraryMetadataNotification;
extern NSString * const MusicAppManagerDidUpdateBrowserNotification;

@class MusicAppLibraryMetadata, MusicAppPasteboardMetadata, MusicAppPasteboardParseResult;
@class MusicLibrarySnapshot;


@interface MusicAppManager : NSObject

+ (id) sharedInstance;

- (MusicAppLibraryMetadata *) libraryMetadataForFileURL:(NSURL *)url;
@property (nonatomic, readonly) BOOL didParseLibrary;
@property (nonatomic, readonly) MusicLibrarySnapshot *browserSnapshot;
@property (nonatomic, readonly) NSString *browserError;
@property (nonatomic, readonly) BOOL browserLoading;
@property (nonatomic, readonly) NSDate *lastLibraryRefreshDate;
@property (nonatomic, readonly) NSDate *lastMusicLibraryBackupDate;
@property (nonatomic, readonly) NSString *musicLibraryBackupError;
@property (nonatomic, readonly) BOOL musicLibraryBackupInProgress;
@property (nonatomic, readonly) NSURL *musicLibraryBackupDirectoryURL;
- (void) refreshBrowser;
- (void) backupMusicLibraryNow;

- (MusicAppPasteboardParseResult *) parsePasteboard:(NSPasteboard *)pasteboard;

- (void) clearPasteboardMetadata;
- (void) addPasteboardMetadataArray:(NSArray *)array;
- (MusicAppPasteboardMetadata *) pasteboardMetadataForFileURL:(NSURL *)url;

@end


@interface MusicAppPasteboardParseResult : NSObject

@property (nonatomic) NSArray<MusicAppPasteboardMetadata *> *metadataArray;
@property (nonatomic) NSArray<NSURL *> *fileURLs;

@end


@interface MusicAppLibraryMetadata : NSObject
@property (nonatomic) NSTimeInterval startTime;
@property (nonatomic) NSTimeInterval stopTime;
@property (nonatomic, copy) NSString *genre;
@property (nonatomic, copy) NSString *persistentIdentifier;
@end


@interface MusicAppPasteboardMetadata : NSObject

@property (nonatomic) NSInteger trackID;
@property (nonatomic) NSInteger databaseID;
@property (nonatomic, copy) NSString *location;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *genre;
@property (nonatomic) NSTimeInterval duration;
@end
