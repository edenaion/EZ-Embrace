// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "MusicAppManager.h"

#import "Utils.h"
#import "AppDelegate.h"
#import "TrackKeys.h"
#import "WorkerService.h"
#import "MusicLibrary.h"
#import "MusicLibraryBackupStore.h"
#import "Preferences.h"
#import <iTunesLibrary/iTunesLibrary.h>


NSString * const MusicAppManagerDidUpdateLibraryMetadataNotification = @"MusicAppManagerDidUpdateLibraryMetadata";
NSString * const MusicAppManagerDidUpdateBrowserNotification = @"MusicAppManagerDidUpdateBrowser";


static NSString *sGetExpandedPath(NSString *inPath)
{
    inPath = [inPath stringByStandardizingPath];
    inPath = [inPath stringByResolvingSymlinksInPath];
    
    return inPath;
}


@implementation MusicAppManager {
    NSTimer             *_libraryCheckTimer;
    NSTimeInterval       _lastLibraryParseTime;
    NSMutableDictionary *_pathToLibraryMetadataMap;

    NSMutableDictionary *_pathToTrackIDMap;
    NSMutableDictionary *_trackIDToPasteboardMetadataMap;
    BOOL _browserRequested;
    NSUInteger _browserRequestGeneration;
    MusicLibraryBackupStore *_backupStore;
    dispatch_queue_t _backupQueue;
    BOOL _backupRequestedWhenReady;
    NSDate *_lastAutomaticBackupAttemptDate;
}


+ (id) sharedInstance
{
    static MusicAppManager *sSharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sSharedInstance = [[MusicAppManager alloc] init];
    });

    return sSharedInstance;
}


- (id) init
{
    if ((self = [super init])) {
        _libraryCheckTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(_checkLibrary:) userInfo:nil repeats:YES];
        [_libraryCheckTimer setTolerance:5.0];
        _backupStore = [MusicLibraryBackupStore defaultStore];
        _backupQueue = dispatch_queue_create("com.ezscape.EZEmbrace.music-library-backup", DISPATCH_QUEUE_SERIAL);
        dispatch_async(_backupQueue, ^{
            NSDate *latest = [self->_backupStore latestSnapshotDate];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_lastMusicLibraryBackupDate = latest;
                [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateBrowserNotification object:self];
            });
        });
        
        [self _checkLibrary:nil];
        if (@available(macOS 13.0, *)) {
            [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(_libraryChanged:)
                name:ITLibraryDidChangeNotification object:nil];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_preferencesChanged:)
            name:PreferencesDidChangeNotification object:[Preferences sharedInstance]];
        // Keep the read-only Music mirror current regardless of the optional backup setting.
        // Once requested, change notifications and the existing bounded poll refresh it.
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshBrowser]; });
    }

    return self;
}

- (NSURL *) musicLibraryBackupDirectoryURL { return _backupStore.directoryURL; }

- (void) _preferencesChanged:(NSNotification *)note
{
    [self _backupCurrentMirrorIfNeeded];
}

- (void) _backupCurrentMirrorIfNeeded
{
    Preferences *preferences = [Preferences sharedInstance];
    if (!preferences.musicLibraryDailySnapshotsEnabled || !_browserSnapshot || _musicLibraryBackupInProgress) return;
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if (_lastMusicLibraryBackupDate && [calendar isDate:_lastMusicLibraryBackupDate inSameDayAsDate:now]) return;
    // A persistent disk failure should remain visible without retrying every 30-second library poll.
    if (_lastAutomaticBackupAttemptDate && [now timeIntervalSinceDate:_lastAutomaticBackupAttemptDate] < 30 * 60) return;
    _lastAutomaticBackupAttemptDate = now;
    [self _backupSnapshot:_browserSnapshot force:NO];
}

- (void) _backupSnapshot:(MusicLibrarySnapshot *)snapshot force:(BOOL)force
{
    if (!snapshot.isComplete || _musicLibraryBackupInProgress) return;
    _musicLibraryBackupInProgress = YES;
    _musicLibraryBackupError = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateBrowserNotification object:self];
    dispatch_async(_backupQueue, ^{
        BOOL wrote = NO;
        NSError *error = nil;
        NSURL *url = [self->_backupStore saveSnapshot:snapshot atDate:[NSDate date] force:force didWrite:&wrote error:&error];
        NSDictionary *envelope = url ? [MusicLibraryBackupStore verifiedEnvelopeAtURL:url error:&error] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_musicLibraryBackupInProgress = NO;
            if (envelope) {
                self->_lastMusicLibraryBackupDate = envelope[@"createdAt"];
                self->_musicLibraryBackupError = nil;
                EmbraceLog(@"MusicLibrary", @"%@ snapshot %@", wrote ? @"Saved" : @"Retained daily", url.lastPathComponent);
            } else {
                self->_musicLibraryBackupError = error.localizedDescription ?: @"Music library snapshot failed.";
                EmbraceLog(@"MusicLibrary", @"Snapshot failed: %@", self->_musicLibraryBackupError);
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateBrowserNotification object:self];
        });
    });
}

- (void) backupMusicLibraryNow
{
    NSAssert(NSThread.isMainThread, @"Music library backup requests run on the main thread");
    if (_browserSnapshot) [self _backupSnapshot:_browserSnapshot force:YES];
    else {
        _backupRequestedWhenReady = YES;
        [self refreshBrowser];
    }
}

- (void) _libraryChanged:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_browserRequested) [self refreshBrowser];
    });
}

- (void) refreshBrowser
{
    NSAssert([NSThread isMainThread], @"Library UI requests run on the main thread");
    _browserRequested = YES;
    if (_browserLoading) return;
    _browserLoading = YES;
    _browserError = nil;
    NSUInteger generation = ++_browserRequestGeneration;
    [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateBrowserNotification object:self];
    void (^finish)(NSDictionary *, NSString *) = ^(NSDictionary *dictionary, NSString *message) {
        // Snapshot validation and search indexing stay off the playback/UI thread.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            MusicLibrarySnapshot *snapshot = dictionary ? [[MusicLibrarySnapshot alloc] initWithDictionary:dictionary] : nil;
            NSString *validationMessage = message;
            if (snapshot && !snapshot.isComplete) {
                snapshot = nil;
                validationMessage = @"Music returned an incomplete library scan. The last known good mirror was preserved.";
            }
            NSMutableDictionary *libraryMetadata = [NSMutableDictionary dictionary];
            for (NSDictionary *track in snapshot.tracks) {
                NSTimeInterval start = [track[@"startTime"] doubleValue];
                NSTimeInterval stop = [track[@"stopTime"] doubleValue];
                NSURL *url = [NSURL URLWithString:track[@"location"]];
                if (!url.isFileURL) continue;
                MusicAppLibraryMetadata *metadata = [[MusicAppLibraryMetadata alloc] init];
                metadata.startTime = start;
                metadata.stopTime = stop;
                metadata.genre = [track[@"genre"] isKindOfClass:NSString.class] ? track[@"genre"] : @"";
                libraryMetadata[sGetExpandedPath(url.path)] = metadata;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != _browserRequestGeneration || !_browserLoading) return;
                _browserLoading = NO;
                _browserError = validationMessage;
                if (snapshot) {
                    _browserSnapshot = snapshot;
                    _lastLibraryRefreshDate = [NSDate date];
                    [self _applyLibraryMetadata:libraryMetadata];
                    BOOL forceBackup = _backupRequestedWhenReady;
                    _backupRequestedWhenReady = NO;
                    if (forceBackup || ((Preferences *)[Preferences sharedInstance]).musicLibraryDailySnapshotsEnabled) {
                        [self _backupSnapshot:snapshot force:forceBackup];
                    }
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateBrowserNotification object:self];
            });
        });
    };
    id<WorkerProtocol> worker = [GetAppDelegate() workerProxyWithErrorHandler:^(NSError *error) {
        finish(nil, @"The library reader disconnected. Refresh to try again.");
    }];
    [worker performMusicLibraryFetchWithReply:finish];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation == _browserRequestGeneration && _browserLoading) {
            finish(nil, @"The library scan timed out. Check library access, then refresh.");
        }
    });
}

- (void) _applyLibraryMetadata:(NSMutableDictionary *)metadata
{
    _didParseLibrary = YES;
    if (![_pathToLibraryMetadataMap isEqualToDictionary:metadata]) {
        _pathToLibraryMetadataMap = metadata;
        [[NSNotificationCenter defaultCenter] postNotificationName:MusicAppManagerDidUpdateLibraryMetadataNotification object:self];
    }
}


#pragma mark - Library Metadata

- (void) _checkLibrary:(NSTimer *)timer
{
    // The app can stay open across midnight during a set. This makes "daily" independent
    // of launches and Music library edits while reusing the existing bounded poll timer.
    [self _backupCurrentMirrorIfNeeded];

    NSURL *libraryURL = nil;
    
    // Get URL for "iTunes Library.itl"
    {
        NSArray  *musicPaths = NSSearchPathForDirectoriesInDomains(NSMusicDirectory, NSUserDomainMask, YES);
        NSString *musicPath  = [musicPaths firstObject];
        
        NSString *itlPath = musicPath;
        itlPath = [itlPath stringByAppendingPathComponent:@"iTunes"];
        itlPath = [itlPath stringByAppendingPathComponent:@"iTunes Library.itl"];

        NSString *musicdbPath = musicPath;
        musicdbPath = [musicdbPath stringByAppendingPathComponent:@"Music"];
        musicdbPath = [musicdbPath stringByAppendingPathComponent:@"Music Library.musiclibrary"];
        musicdbPath = [musicdbPath stringByAppendingPathComponent:@"Library.musicdb"];

        if ([[NSFileManager defaultManager] fileExistsAtPath:musicdbPath]) {
            libraryURL = [NSURL fileURLWithPath:musicdbPath];

        } else if ([[NSFileManager defaultManager] fileExistsAtPath:itlPath]) {
            libraryURL = [NSURL fileURLWithPath:itlPath];
        }
    }

    EmbraceLog(@"MusicAppManager", @"libraryURL is: %@", libraryURL);
    
    NSDate *modificationDate = nil;
    NSError *error = nil;

    [libraryURL getResourceValue:&modificationDate forKey:NSURLContentModificationDateKey error:&error];
    if (error) {
        EmbraceLog(@"MusicAppManager", @"Could not get modification date for %@: error: %@", libraryURL, error);
    }

    if (!error && [modificationDate isKindOfClass:[NSDate class]]) {
        NSTimeInterval timeInterval = [modificationDate timeIntervalSinceReferenceDate];
        
        if (timeInterval > _lastLibraryParseTime) {
            if (_browserRequested) [self refreshBrowser];
            if (_lastLibraryParseTime) {
                EmbraceLog(@"MusicAppManager", @"Music.app Library modified!");
            }

            id<WorkerProtocol> worker = [GetAppDelegate() workerProxyWithErrorHandler:^(NSError *proxyError) {
                EmbraceLog(@"MusicAppManager", @"Received error for worker fetch: %@", proxyError);
            }];

            _lastLibraryParseTime = timeInterval;

            [worker performLibraryParseWithReply:^(NSDictionary *dictionary) {
                NSMutableDictionary *pathToLibraryMetadataMap = [NSMutableDictionary dictionaryWithCapacity:[dictionary count]];

                for (NSString *path in dictionary) {
                    MusicAppLibraryMetadata *metadata = [[MusicAppLibraryMetadata alloc] init];
                    
                    NSDictionary *trackData = [dictionary objectForKey:path];
                    [metadata setStartTime:[[trackData objectForKey:TrackKeyStartTime] doubleValue]];
                    [metadata setStopTime: [[trackData objectForKey:TrackKeyStopTime]  doubleValue]];
                    id genre = [trackData objectForKey:TrackKeyGenre];
                    [metadata setGenre:[genre isKindOfClass:NSString.class] ? genre : @""];

                    [pathToLibraryMetadataMap setObject:metadata forKey:sGetExpandedPath(path)];
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self _applyLibraryMetadata:pathToLibraryMetadataMap];
                });
            }];
        }
    }
}


- (MusicAppLibraryMetadata *) libraryMetadataForFileURL:(NSURL *)url
{
    NSString *path = sGetExpandedPath([url path]);
    return [_pathToLibraryMetadataMap objectForKey:path];
}


#pragma mark - Pasteboard Parsing

- (MusicAppPasteboardParseResult *) parsePasteboard:(NSPasteboard *)pasteboard
{
    NSMutableDictionary *trackIDToMetadataMap = [NSMutableDictionary dictionary];
    NSMutableArray *orderedTrackIDs  = [NSMutableArray array];

    NSMutableArray *metadataFileURLs = [NSMutableArray array];
    NSMutableArray *otherFileURLs    = [NSMutableArray array];
    
    auto parsePlaylist = ^(NSDictionary *playlist) {
        if (![playlist isKindOfClass:[NSDictionary class]]) {
            return;
        }

        NSArray *items = [playlist objectForKey:@"Playlist Items"];
        if (![items isKindOfClass:[NSArray class]]) {
            return;
        }
        
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                continue;
            }
        
            id trackIDObject = [item objectForKey:@"Track ID"];
            if (![trackIDObject respondsToSelector:@selector(integerValue)]) {
                trackIDObject = nil;
            }

            NSInteger trackID = [trackIDObject integerValue];
            if (trackID) [orderedTrackIDs addObject:@(trackID)];
        }
    };

    auto parsePlaylists = ^(NSArray *playlists) {
        if (![playlists isKindOfClass:[NSArray class]]) {
            return;
        }
        
        for (NSDictionary *playlist in playlists) {
            parsePlaylist(playlist);
        }
    };

    auto parseTrack = ^(NSString *key, NSDictionary *track) {
        if (![key isKindOfClass:[NSString class]]) {
            return;
        }

        if (![track isKindOfClass:[NSDictionary class]]) {
            return;
        }

        NSString *artist = [track objectForKey:@"Artist"];
        if (![artist isKindOfClass:[NSString class]]) artist = nil;

        NSString *name = [track objectForKey:@"Name"];
        if (![name isKindOfClass:[NSString class]]) name = nil;

        NSString *genre = [track objectForKey:@"Genre"];
        if (![genre isKindOfClass:[NSString class]]) genre = nil;

        NSString *location = [track objectForKey:@"Location"];
        if (![location isKindOfClass:[NSString class]]) location = nil;
        
        if ([location hasPrefix:@"file:"]) {
            location = [[NSURL URLWithString:location] path];
        }

        id totalTimeObject = [track objectForKey:@"Total Time"];
        if (![totalTimeObject respondsToSelector:@selector(doubleValue)]) {
            totalTimeObject = nil;
        }

        id trackIDObject = [track objectForKey:@"Track ID"];
        if (![trackIDObject respondsToSelector:@selector(integerValue)]) {
            trackIDObject = nil;
        }
        
        NSTimeInterval totalTime = [totalTimeObject doubleValue] / 1000.0;
        NSInteger trackID   = [trackIDObject integerValue];
        
        if (!trackID) return;

        MusicAppPasteboardMetadata *metadata = [[MusicAppPasteboardMetadata alloc] init];
        [metadata setDuration:totalTime];
        [metadata setTitle:name];
        [metadata setArtist:artist];
        [metadata setGenre:genre];
        [metadata setLocation:sGetExpandedPath(location)];
        [metadata setTrackID:trackID];
        [metadata setDatabaseID:[key integerValue]];
        
        [trackIDToMetadataMap setObject:metadata forKey:@(trackID)];
    };

    auto parseTracks = ^(NSDictionary *tracks) {
        if (![tracks isKindOfClass:[NSDictionary class]]) {
            return;
        }
        
        for (NSString *key in tracks) {
            NSDictionary *track = [tracks objectForKey:key];
            parseTrack(key, track);
        }
    };

    auto parseMetadataRoot = ^(NSDictionary *root) {
        if (![root isKindOfClass:[NSDictionary class]]) {
            return;
        }

        parsePlaylists( [root objectForKey:@"Playlists"] );
        parseTracks(    [root objectForKey:@"Tracks"]    );
    };
    
    auto parsePasteboardItem = ^(NSPasteboardItem *item) {
        for (NSString *type in [item types]) {
            if ([type hasPrefix:@"com.apple."] && [type hasSuffix:@".metadata"]) {
                parseMetadataRoot([item propertyListForType:type]);
            }
        }
    };

    // Step 1, Fill metadataFileURLs from com.apple.*.metadata 
    {
        for (NSPasteboardItem *item in [pasteboard pasteboardItems]) {
            parsePasteboardItem(item);
        }

        for (NSNumber *trackID in orderedTrackIDs) {
            MusicAppPasteboardMetadata *metadata = [trackIDToMetadataMap objectForKey:trackID];
            
            NSString *location = [metadata location];
            NSURL    *fileURL  = location ? [NSURL fileURLWithPath:location] : nil;

            if (fileURL) [metadataFileURLs addObject:fileURL];
        }
    }

    // Step 2, Fill otherFileURLs with NSPasteboardTypeFileURL/kPasteboardTypeFileURLPromise
    {
        for (NSPasteboardItem *item in [pasteboard pasteboardItems]) {
            id playlistLocations = [item propertyListForType:MusicLibraryPlaylistPasteboardType];
            if ([playlistLocations isKindOfClass:[NSArray class]]) {
                for (id location in playlistLocations) {
                    if (![location isKindOfClass:[NSString class]]) continue;
                    NSURL *url = [NSURL URLWithString:location];
                    if (url.isFileURL) [otherFileURLs addObject:url];
                }
                continue;
            }
            NSArray *types = [item types];

            BOOL hasPromise        = [types containsObject:(id)kPasteboardTypeFileURLPromise];
            BOOL hasPromiseContent = [types containsObject:(id)kPasteboardTypeFilePromiseContent];
              
            NSString *fileURLString = [item propertyListForType:NSPasteboardTypeFileURL];

            // In macOS Catalina 10.15.0, the new Music app likes to write a real URL
            // as a kPasteboardTypeFileURLPromise without kPasteboardTypeFilePromiseContent
            //
            if (!fileURLString && hasPromise && !hasPromiseContent) {
                fileURLString = [item propertyListForType:NSPasteboardTypeFileURL];
            }

            NSURL *fileURL = fileURLString ? [NSURL URLWithString:fileURLString] : nil;
            
            fileURL = [fileURL URLByStandardizingPath];
            fileURL = [fileURL URLByResolvingSymlinksInPath];
            
            if (fileURL) [otherFileURLs addObject:fileURL];
        }
    }

    // Step 3, Fill otherFileURLs with legacy NSFilenamesPboardType
    if ([otherFileURLs count] == 0) {
        NSArray *filenames = [pasteboard propertyListForType:@"NSFilenamesPboardType"];

        if (filenames) {
            for (NSString *filename in filenames) {
                NSURL *url = [NSURL fileURLWithPath:sGetExpandedPath(filename)];
                if (url) [otherFileURLs addObject:url];
            }
        }
    }
    
    NSArray *fileURLs = [metadataFileURLs count] > [otherFileURLs count] ? metadataFileURLs : otherFileURLs;
    NSArray *metadataArray = [trackIDToMetadataMap allValues];

    if ([fileURLs count] > 0 || [metadataArray count] > 0) {
        MusicAppPasteboardParseResult *result = [[MusicAppPasteboardParseResult alloc] init];

        [result setMetadataArray:metadataArray];
        [result setFileURLs:fileURLs];
        
        return result;
    }

    return nil;
}


#pragma mark - Pasteboard Metadata

- (void) clearPasteboardMetadata
{
    [_trackIDToPasteboardMetadataMap removeAllObjects];
}


- (void) addPasteboardMetadataArray:(NSArray *)array
{
    for (MusicAppPasteboardMetadata *metadata in array) {
        NSInteger trackID  = [metadata trackID];
        NSString *location = [metadata location];

        if (!_trackIDToPasteboardMetadataMap) _trackIDToPasteboardMetadataMap = [NSMutableDictionary dictionary];
        [_trackIDToPasteboardMetadataMap setObject:metadata forKey:@(trackID)];
        
        if (location) {
            if (!_pathToTrackIDMap) _pathToTrackIDMap = [NSMutableDictionary dictionary];
            [_pathToTrackIDMap setObject:@(trackID) forKey:sGetExpandedPath(location)];
        }
    }
}


- (MusicAppPasteboardMetadata *) pasteboardMetadataForFileURL:(NSURL *)url
{
    NSString *path = sGetExpandedPath([url path]);
    NSInteger trackID = [[_pathToTrackIDMap objectForKey:path] integerValue];
    return [_trackIDToPasteboardMetadataMap objectForKey:@(trackID)];
}


@end


#pragma mark - Other Classes

@implementation MusicAppLibraryMetadata

- (BOOL) isEqual:(id)otherObject
{
    if (![otherObject isKindOfClass:[MusicAppLibraryMetadata class]]) {
        return NO;
    }

    MusicAppLibraryMetadata *otherMetadata = (MusicAppLibraryMetadata *)otherObject;

    return _startTime == otherMetadata->_startTime &&
           _stopTime  == otherMetadata->_stopTime &&
           ((_genre == otherMetadata->_genre) || [_genre isEqualToString:otherMetadata->_genre]);
}


- (NSUInteger) hash
{
    NSUInteger startTime = *(NSUInteger *)&_startTime;
    NSUInteger stopTime  = *(NSUInteger *)&_stopTime;

    return startTime ^ stopTime ^ _genre.hash;
}


@end


@implementation MusicAppPasteboardParseResult
@end


@implementation MusicAppPasteboardMetadata
@end

