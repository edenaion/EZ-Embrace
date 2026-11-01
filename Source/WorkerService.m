// (c) 2016-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "WorkerService.h"

#import "HugAudioFile.h"
#import "HugUtils.h"
#import "TrackKeys.h"
#import "LoudnessMeasurer.h"
#import "MetadataParser.h"

#import <iTunesLibrary/iTunesLibrary.h>

static dispatch_queue_t sMetadataQueue           = nil;
static dispatch_queue_t sLibraryQueue            = nil;
static dispatch_queue_t sLoudnessImmediateQueue  = nil;
static dispatch_queue_t sLoudnessBackgroundQueue = nil;

static NSMutableSet *sCancelledUUIDs = nil;
static NSMutableSet *sLoudnessUUIDs  = nil;


@interface Worker : NSObject <WorkerProtocol>

@end


@implementation Worker {
    ITLibrary *_library;
}

+ (void) initialize
{
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sMetadataQueue           = dispatch_queue_create("metadata",            DISPATCH_QUEUE_SERIAL);
        sLibraryQueue            = dispatch_queue_create("library",             DISPATCH_QUEUE_SERIAL);
        sLoudnessImmediateQueue  = dispatch_queue_create("loudness-immediate",  DISPATCH_QUEUE_SERIAL);
        sLoudnessBackgroundQueue = dispatch_queue_create("loudness-background", DISPATCH_QUEUE_SERIAL);

        sCancelledUUIDs = [NSMutableSet set];
        sLoudnessUUIDs  = [NSMutableSet set];
    });
}


static NSDictionary *sReadMetadata(NSURL *internalURL, NSString *originalFilename)
{
    NSString *fallbackTitle = [originalFilename stringByDeletingPathExtension];

    MetadataParser *parser = [[MetadataParser alloc] initWithURL:internalURL fallbackTitle:fallbackTitle];
    
    return [parser metadata];
}


static NSDictionary *sReadLoudness(NSURL *internalURL)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    HugAudioFile *audioFile = [[HugAudioFile alloc] initWithFileURL:internalURL];
  
    if ([audioFile open]) {
        NSInteger fileLengthFrames = [audioFile fileLengthFrames];
        AudioStreamBasicDescription format = [audioFile format];

        NSInteger framesRemaining = fileLengthFrames;
        NSInteger bytesRemaining  = framesRemaining * format.mBytesPerFrame;
        NSInteger bytesRead = 0;

        LoudnessMeasurer *measurer = LoudnessMeasurerCreate(format.mChannelsPerFrame, format.mSampleRate, framesRemaining);

        AudioBufferList *fillBufferList = HugAudioBufferListCreate(format.mChannelsPerFrame, 4096 * 16, YES);

        BOOL ok = YES;
        while (ok) {
            UInt32 frameCount = (UInt32)framesRemaining;
            ok = [audioFile readFrames:&frameCount intoBufferList:fillBufferList];

            if (frameCount) {
                LoudnessMeasurerScanAudioBuffer(measurer, fillBufferList, frameCount);
            } else {
                break;
            }
            
            framesRemaining -= frameCount;
        
            bytesRead      += frameCount * format.mBytesPerFrame;
            bytesRemaining -= frameCount * format.mBytesPerFrame;

            if (framesRemaining == 0) {
                break;
            }
        }
       
        NSTimeInterval decodedDuration = fileLengthFrames / format.mSampleRate;
        
        [result setObject:@(decodedDuration)                       forKey:TrackKeyDecodedDuration];
        [result setObject:LoudnessMeasurerGetOverview(measurer)    forKey:TrackKeyOverviewData];
        [result setObject:@(100)                                   forKey:TrackKeyOverviewRate];
        [result setObject:@(LoudnessMeasurerGetLoudness(measurer)) forKey:TrackKeyTrackLoudness];
        [result setObject:@(LoudnessMeasurerGetPeak(measurer))     forKey:TrackKeyTrackPeak];

        HugAudioBufferListFree(fillBufferList, YES);
        LoudnessMeasurerFree(measurer);

    } else {
        if ([audioFile error]) {
            NSData *errorData = [NSKeyedArchiver archivedDataWithRootObject:[audioFile error] requiringSecureCoding:NO error:nil];
            [result setObject:errorData forKey:TrackKeyError];
        }
    }

    return result;
}


- (void) cancelUUID:(NSUUID *)UUID
{
    [sCancelledUUIDs addObject:UUID];
}


- (void) performTrackCommand: (WorkerTrackCommand) command
                        UUID: (NSUUID *) UUID
                bookmarkData: (NSData *) bookmarkData
            originalFilename: (NSString *) originalFilename
                       reply: (void (^)(NSDictionary *))reply
{
    NSError *error = nil;
    NSURL *internalURL = [NSURL URLByResolvingBookmarkData: bookmarkData
                                                   options: NSURLBookmarkResolutionWithoutUI
                                             relativeToURL: nil
                                       bookmarkDataIsStale: NULL
                                                     error: &error];

    if (error) NSLog(@"%@", error);

    if (command == WorkerTrackCommandReadMetadata) {
        dispatch_async(sMetadataQueue, ^{ @autoreleasepool {
            if (![sCancelledUUIDs containsObject:UUID]) {
                reply(sReadMetadata(internalURL, originalFilename));
            }
        } });

    } else if (command == WorkerTrackCommandReadLoudness || command == WorkerTrackCommandReadLoudnessImmediate) {
        BOOL             isImmediate = (command == WorkerTrackCommandReadLoudnessImmediate);
        dispatch_queue_t queue       = isImmediate ? sLoudnessImmediateQueue : sLoudnessBackgroundQueue;

        dispatch_async(queue, ^{ @autoreleasepool {
            if (![sCancelledUUIDs containsObject:UUID] && ![sLoudnessUUIDs containsObject:UUID]) {
                [sLoudnessUUIDs addObject:UUID];

                NSDictionary *dictionary = sReadLoudness(internalURL);

                dispatch_async(dispatch_get_main_queue(), ^{
                    reply(dictionary);
                });
            }
        } });
    }
}


- (void) performLibraryParseWithReply:(void (^)(NSDictionary *))reply
{
    dispatch_async(sLibraryQueue, ^{
        if (!_library) {
            NSError *error = nil;
            _library = [ITLibrary libraryWithAPIVersion:@"1.0" error:&error];
            NSLog(@"%@", error);
        } else {
            [_library reloadData];
        }
        
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        
        for (ITLibMediaItem *mediaItem in [_library allMediaItems]) {
            NSUInteger startTime = [mediaItem startTime];
            NSUInteger stopTime  = [mediaItem stopTime];

            NSMutableDictionary *trackData = [NSMutableDictionary dictionaryWithCapacity:3];
            if (startTime) [trackData setObject:@(startTime / 1000.0) forKey:TrackKeyStartTime];
            if (stopTime)  [trackData setObject:@(stopTime  / 1000.0) forKey:TrackKeyStopTime];
            [trackData setObject:[mediaItem genre] ?: @"" forKey:TrackKeyGenre];

            NSString *location = [[mediaItem location] path];
            if (location) [result setObject:trackData forKey:location];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            reply(result);
        });
    });
}

static NSDictionary *sLibraryTrack(ITLibMediaItem *item)
{
    NSURL *url = item.location;
    BOOL directory = NO;
    BOOL readable = url.isFileURL && [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&directory]
        && !directory && [[NSFileManager defaultManager] isReadableFileAtPath:url.path];
    NSString *availability = item.isDRMProtected ? @"Protected audio" : readable ? @"Local file"
        : url.isFileURL ? @"File unavailable" : item.isCloud ? @"Cloud only" : @"No local file";
    NSMutableDictionary *track = [@{
        @"id":item.persistentID.stringValue, @"title":item.title ?: @"", @"artist":item.artist.name ?: @"",
        @"album":item.album.title ?: @"", @"albumArtist":item.album.albumArtist ?: @"",
        @"genre":item.genre ?: @"", @"composer":item.composer ?: @"", @"grouping":item.grouping ?: @"",
        @"comments":item.comments ?: @"", @"kind":item.kind ?: @"",
        @"sortTitle":item.sortTitle ?: @"", @"sortArtist":item.artist.sortName ?: @"",
        @"sortAlbum":item.album.sortTitle ?: @"", @"sortAlbumArtist":item.album.sortAlbumArtist ?: @"",
        @"sortComposer":item.sortComposer ?: @"", @"duration":@(item.totalTime / 1000.0),
        @"bpm":@(item.beatsPerMinute), @"year":@(item.year), @"trackNumber":@(item.trackNumber),
        @"discNumber":@(item.album.discNumber), @"rating":@(item.rating), @"playCount":@(item.playCount),
        @"skipCount":@(item.skipCount), @"bitrate":@(item.bitrate), @"sampleRate":@(item.sampleRate),
        @"fileSize":@(item.fileSize), @"startTime":@(item.startTime / 1000.0), @"stopTime":@(item.stopTime / 1000.0),
        @"drmProtected":@(item.isDRMProtected), @"availability":availability,
        @"location":url.absoluteString ?: @""
    } mutableCopy];
    if (item.addedDate) track[@"addedDate"] = item.addedDate;
    if (item.modifiedDate) track[@"modifiedDate"] = item.modifiedDate;
    if (item.lastPlayedDate) track[@"lastPlayedDate"] = item.lastPlayedDate;
    if (item.releaseDate) track[@"releaseDate"] = item.releaseDate;
    return track;
}

- (void) performMusicLibraryFetchWithReply:(void (^)(NSDictionary *, NSString *))reply
{
    dispatch_async(sLibraryQueue, ^{ @autoreleasepool {
        NSError *error = nil;
        if (!_library) _library = [ITLibrary libraryWithAPIVersion:@"1.0" error:&error];
        else if (![_library reloadData]) error = [NSError errorWithDomain:@"MusicLibrary" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"The Music library could not be refreshed. Try again after checking library access."}];
        if (!_library || error) {
            reply(nil, error.localizedDescription ?: @"The Music library is unavailable. Check Music library access in System Settings > Privacy & Security > Media & Apple Music, then refresh.");
            return;
        }
        NSMutableArray *tracks = [NSMutableArray array];
        NSMutableSet *trackIDs = [NSMutableSet set];
        for (ITLibMediaItem *item in _library.allMediaItems) {
            if (item.isVideo || !item.persistentID || item.mediaKind == ITLibMediaItemMediaKindPDFBooklet ||
                item.mediaKind == ITLibMediaItemMediaKindDigitalBooklet || item.mediaKind == ITLibMediaItemMediaKindInteractiveBooklet ||
                item.mediaKind == ITLibMediaItemMediaKindBook || item.mediaKind == ITLibMediaItemMediaKindPDFBook ||
                item.mediaKind == ITLibMediaItemMediaKindIOSApplication) continue;
            [tracks addObject:sLibraryTrack(item)];
            [trackIDs addObject:item.persistentID.stringValue];
        }
        NSMutableArray *playlists = [NSMutableArray array];
        for (ITLibPlaylist *playlist in _library.allPlaylists) {
            if (!playlist.isVisible || !playlist.persistentID) continue;
            if (@available(macOS 12.0, *)) { if (playlist.primary) continue; }
            ITLibDistinguishedPlaylistKind kind = playlist.distinguishedKind;
            if (kind == ITLibDistinguishedPlaylistKindMovies || kind == ITLibDistinguishedPlaylistKindTVShows ||
                kind == ITLibDistinguishedPlaylistKindMusicVideos || kind == ITLibDistinguishedPlaylistKindLibraryMusicVideos ||
                kind == ITLibDistinguishedPlaylistKindHomeVideos || kind == ITLibDistinguishedPlaylistKindApplications ||
                kind == ITLibDistinguishedPlaylistKindMusicShowsAndMovies) continue;
            NSMutableArray *items = [NSMutableArray array];
            for (ITLibMediaItem *item in playlist.items) {
                NSString *identifier = item.persistentID.stringValue;
                if (identifier && [trackIDs containsObject:identifier]) [items addObject:identifier];
            }
            NSMutableDictionary *row = [@{@"id":playlist.persistentID.stringValue, @"name":playlist.name ?: @"",
                @"trackIDs":items, @"kind":@(playlist.kind), @"distinguishedKind":@(kind),
                @"sourceOrder":@(playlists.count)} mutableCopy];
            if (playlist.parentID) row[@"parentID"] = playlist.parentID.stringValue;
            [playlists addObject:row];
        }
        reply(@{@"tracks":tracks, @"playlists":playlists}, nil);
    } });
}

@end


#pragma mark - WorkerDelegate

@interface WorkerDelegate : NSObject <NSXPCListenerDelegate>
@end


@implementation WorkerDelegate

- (BOOL) listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection
{
    NSXPCInterface *exportedInterface = EmbraceWorkerXPCInterface();
    [connection setExportedInterface:exportedInterface];
    
    Worker *exportedObject = [[Worker alloc] init];
    [connection setExportedObject:exportedObject];
    
    [connection resume];
    
    return YES;
}

@end


static WorkerDelegate *sWorkerDelegate = nil;

int main(int argc, const char *argv[])
{
    sWorkerDelegate = [[WorkerDelegate alloc] init];
    
    NSXPCListener *listener = [NSXPCListener serviceListener];
    [listener setDelegate:sWorkerDelegate];
    
    [listener resume];

    return 0;
}
