#import "MusicLibrary.h"
NSString * const MusicLibraryPlaylistPasteboardType = @"com.ezscape.ez-embrace.music-playlist";

@implementation MusicLibrarySnapshot {
    NSDictionary<NSString *, NSArray<NSDictionary *> *> *_playlistTracks;
}

+ (NSArray<NSDictionary *> *) columns
{
    static NSArray *columns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *definitions = @[
            @[@"title", @"Title", @220, @YES], @[@"comments", @"Comments", @220, @YES],
            @[@"duration", @"Time", @70, @YES], @[@"bitrate", @"Bit rate (kbps)", @100, @YES],
            @[@"artist", @"Artist", @160, @YES], @[@"genre", @"Genre", @110, @YES],
            @[@"rating", @"Rating", @70, @YES],
            @[@"album", @"Album", @180, @NO], @[@"bpm", @"BPM", @65, @NO],
            @[@"year", @"Year", @65, @NO], @[@"availability", @"Availability", @170, @NO],
            @[@"albumArtist", @"Album artist", @160, @NO],
            @[@"composer", @"Composer", @160, @NO], @[@"grouping", @"Grouping", @130, @NO],
            @[@"trackNumber", @"Track number", @90, @NO],
            @[@"discNumber", @"Disc number", @85, @NO],
            @[@"playCount", @"Plays", @70, @NO], @[@"skipCount", @"Skips", @70, @NO],
            @[@"addedDate", @"Date added", @150, @NO], @[@"modifiedDate", @"Date modified", @150, @NO],
            @[@"lastPlayedDate", @"Last played", @150, @NO], @[@"releaseDate", @"Release date", @150, @NO],
            @[@"kind", @"Kind", @170, @NO],
            @[@"sampleRate", @"Sample rate (Hz)", @115, @NO], @[@"fileSize", @"Size (bytes)", @120, @NO],
            @[@"sortTitle", @"Sort title", @160, @NO], @[@"sortArtist", @"Sort artist", @160, @NO],
            @[@"sortAlbum", @"Sort album", @160, @NO], @[@"sortAlbumArtist", @"Sort album artist", @160, @NO],
            @[@"sortComposer", @"Sort composer", @160, @NO],
            @[@"startTime", @"Start time", @80, @NO], @[@"stopTime", @"Stop time", @80, @NO],
            @[@"location", @"File location", @300, @NO]
        ];
        NSMutableArray *result = [NSMutableArray array];
        for (NSArray *row in definitions) {
            [result addObject:@{@"key":row[0], @"title":row[1], @"width":row[2], @"visible":row[3]}];
        }
        columns = [result copy];
    });
    return columns;
}

- (instancetype) initWithDictionary:(NSDictionary *)dictionary
{
    if ((self = [super init])) {
        _complete = [dictionary isKindOfClass:[NSDictionary class]] && [dictionary[@"tracks"] isKindOfClass:[NSArray class]]
            && [dictionary[@"playlists"] isKindOfClass:[NSArray class]];
        NSMutableArray *tracks = [NSMutableArray array];
        NSMutableArray *backupTracks = [NSMutableArray array];
        NSMutableDictionary *byID = [NSMutableDictionary dictionary];
        id rows = dictionary[@"tracks"];
        if (![rows isKindOfClass:[NSArray class]]) rows = @[];
        NSMutableSet *keys = [NSMutableSet setWithObjects:@"id", @"drmProtected", nil];
        for (NSDictionary *column in [self.class columns]) [keys addObject:column[@"key"]];
        NSSet *numericKeys = [NSSet setWithArray:@[@"duration", @"bpm", @"year", @"trackNumber", @"discNumber", @"rating", @"playCount", @"skipCount", @"bitrate", @"sampleRate", @"fileSize", @"startTime", @"stopTime", @"drmProtected"]];
        NSSet *dateKeys = [NSSet setWithArray:@[@"addedDate", @"modifiedDate", @"lastPlayedDate", @"releaseDate"]];
        for (id row in rows) {
            if (![row isKindOfClass:[NSDictionary class]] || ![row[@"id"] isKindOfClass:[NSString class]] || ![row[@"id"] length] || byID[row[@"id"]]) continue;
            NSMutableDictionary *track = [NSMutableDictionary dictionary];
            for (NSString *key in keys) {
                id value = row[key];
                if ([numericKeys containsObject:key]) {
                    track[key] = [value isKindOfClass:[NSNumber class]] && isfinite([value doubleValue]) ? value : @0;
                } else if ([dateKeys containsObject:key]) {
                    if ([value isKindOfClass:[NSDate class]]) track[key] = value;
                } else if ([value isKindOfClass:[NSString class]]) {
                    track[key] = value;
                }
            }
            if (![track[@"title"] length]) track[@"title"] = @"Untitled track";
            if (![track[@"availability"] length]) track[@"availability"] = @"Unavailable";
            NSMutableArray *searchValues = [NSMutableArray array];
            for (NSDictionary *column in [self.class columns]) {
                id value = track[column[@"key"]];
                // Avoid creating date formatters for every field in a large library scan.
                NSString *text = [value isKindOfClass:[NSDate class]] ? @"" : [self.class displayValueForTrack:track column:column[@"key"]];
                if (text.length) [searchValues addObject:text];
            }
            track[@"searchText"] = [searchValues componentsJoinedByString:@" "];
            NSDictionary *immutable = [track copy];
            byID[track[@"id"]] = immutable;
            [tracks addObject:immutable];
            NSMutableDictionary *backupTrack = [track mutableCopy];
            [backupTrack removeObjectForKey:@"searchText"];
            [backupTracks addObject:[backupTrack copy]];
        }
        _tracks = [tracks copy];
        NSMutableArray *playlists = [NSMutableArray arrayWithObject:@{@"id":@"all", @"name":@"All music", @"path":@"All music"}];
        NSMutableArray *backupPlaylists = [NSMutableArray array];
        NSMutableDictionary *playlistTracks = [NSMutableDictionary dictionaryWithObject:_tracks forKey:@"all"];
        NSMutableDictionary *playlistByID = [NSMutableDictionary dictionary];
        rows = dictionary[@"playlists"];
        if (![rows isKindOfClass:[NSArray class]]) rows = @[];
        for (id row in rows) {
            if (![row isKindOfClass:[NSDictionary class]] || ![row[@"id"] isKindOfClass:[NSString class]] || ![row[@"id"] length] || [row[@"id"] isEqual:@"all"] || playlistByID[row[@"id"]]) continue;
            NSMutableDictionary *playlist = [NSMutableDictionary dictionary];
            playlist[@"id"] = row[@"id"];
            playlist[@"name"] = [row[@"name"] isKindOfClass:[NSString class]] && [row[@"name"] length] ? row[@"name"] : @"Untitled playlist";
            if ([row[@"parentID"] isKindOfClass:[NSString class]]) playlist[@"parentID"] = row[@"parentID"];
            NSMutableArray *items = [NSMutableArray array];
            NSMutableArray *trackIDs = [NSMutableArray array];
            if ([row[@"trackIDs"] isKindOfClass:[NSArray class]]) {
                for (id trackID in row[@"trackIDs"]) {
                    if ([trackID isKindOfClass:[NSString class]] && byID[trackID]) {
                        [items addObject:byID[trackID]];
                        [trackIDs addObject:trackID];
                    }
                }
            }
            playlist[@"trackIDs"] = [trackIDs copy];
            for (NSString *key in @[@"kind", @"distinguishedKind", @"sourceOrder"]) {
                if ([row[key] isKindOfClass:[NSNumber class]]) playlist[key] = row[key];
            }
            playlistTracks[row[@"id"]] = [items copy];
            playlistByID[row[@"id"]] = playlist;
            [playlists addObject:playlist];
            [backupPlaylists addObject:playlist];
        }
        for (NSMutableDictionary *playlist in [playlists subarrayWithRange:NSMakeRange(1, playlists.count - 1)]) {
            NSMutableArray *path = [NSMutableArray arrayWithObject:playlist[@"name"]];
            NSMutableSet *visited = [NSMutableSet setWithObject:playlist[@"id"]];
            NSDictionary *parent = playlistByID[playlist[@"parentID"] ?: @""];
            while (parent && ![visited containsObject:parent[@"id"]]) {
                [visited addObject:parent[@"id"]];
                [path insertObject:parent[@"name"] atIndex:0];
                parent = playlistByID[parent[@"parentID"] ?: @""];
            }
            playlist[@"path"] = [path componentsJoinedByString:@" / "];
        }
        NSMutableArray *immutablePlaylists = [NSMutableArray arrayWithObject:playlists[0]];
        for (NSDictionary *playlist in [playlists subarrayWithRange:NSMakeRange(1, playlists.count - 1)]) [immutablePlaylists addObject:[playlist copy]];
        _playlists = [immutablePlaylists copy];
        _playlistTracks = [playlistTracks copy];
        NSMutableArray *immutableBackupPlaylists = [NSMutableArray array];
        for (NSDictionary *playlist in backupPlaylists) [immutableBackupPlaylists addObject:[playlist copy]];
        _backupPayload = @{@"schemaVersion":@1, @"tracks":[backupTracks copy], @"playlists":[immutableBackupPlaylists copy]};
    }
    return self;
}

- (NSArray<NSDictionary *> *) tracksForPlaylist:(NSString *)identifier search:(NSString *)search sortDescriptors:(NSArray<NSSortDescriptor *> *)descriptors
{
    NSArray *tracks = _playlistTracks[identifier ?: @"all"] ?: @[];
    NSArray *words = [[search stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (search.length) {
        tracks = [tracks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *track, NSDictionary *bindings) {
            for (NSString *word in words) {
                if (word.length && [track[@"searchText"] rangeOfString:word options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) return NO;
            }
            return YES;
        }]];
    }
    if (!descriptors.count) return tracks;
    NSMutableSet *keys = [NSMutableSet set];
    for (NSDictionary *column in [self.class columns]) [keys addObject:column[@"key"]];
    NSMutableArray *safeDescriptors = [NSMutableArray array];
    for (NSSortDescriptor *descriptor in descriptors) {
        if ([keys containsObject:descriptor.key]) [safeDescriptors addObject:descriptor];
    }
    return [tracks sortedArrayUsingDescriptors:safeDescriptors];
}

+ (NSString *) displayValueForTrack:(NSDictionary *)track column:(NSString *)column
{
    id value = track[column];
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSDate class]]) {
        return [NSDateFormatter localizedStringFromDate:value dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        double number = [value doubleValue];
        if (!isfinite(number)) return @"";
        if ([@[@"duration", @"startTime", @"stopTime"] containsObject:column]) {
            if (number < 0 || number > 1e9) return @"";
            NSUInteger seconds = (NSUInteger)round(number);
            return [NSString stringWithFormat:@"%lu:%02lu", (unsigned long)(seconds / 60), (unsigned long)(seconds % 60)];
        }
        return [value stringValue];
    }
    return @"";
}

+ (NSURL *) importURLForTrack:(NSDictionary *)track
{
    if ([track[@"drmProtected"] boolValue]) return nil;
    NSString *location = track[@"location"];
    if (![location isKindOfClass:[NSString class]]) return nil;
    NSURL *url = [NSURL URLWithString:location];
    if (!url.isFileURL || ![NSFileManager.defaultManager isReadableFileAtPath:url.path]) return nil;
    BOOL directory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&directory] || directory) return nil;
    return url;
}

+ (NSArray<NSURL *> *) importURLsForTracks:(NSArray<NSDictionary *> *)tracks
{
    NSMutableArray *urls = [NSMutableArray array];
    for (NSDictionary *track in tracks) {
        NSURL *url = [self importURLForTrack:track];
        if (url) [urls addObject:url];
    }
    return urls;
}
@end
