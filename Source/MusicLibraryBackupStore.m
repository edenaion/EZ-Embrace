#import "MusicLibraryBackupStore.h"
#import "MusicLibrary.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const MusicLibraryBackupErrorDomain = @"com.ezscape.EZEmbrace.MusicLibraryBackup";

static NSString *sSHA256(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [result appendFormat:@"%02x", digest[index]];
    return result;
}

static NSError *sBackupError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:MusicLibraryBackupErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey:message ?: @"Music library snapshot failed."}];
}

@implementation MusicLibraryBackupStore

+ (instancetype) defaultStore
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSURL *directory = [NSURL fileURLWithPath:[[base stringByAppendingPathComponent:@"EZ-Embrace"]
        stringByAppendingPathComponent:@"Music Library Snapshots"] isDirectory:YES];
    return [[self alloc] initWithDirectoryURL:directory];
}

- (instancetype) initWithDirectoryURL:(NSURL *)directoryURL
{
    if ((self = [super init])) _directoryURL = [directoryURL copy];
    return self;
}

- (NSDateFormatter *) _formatter:(NSString *)format
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = format;
    return formatter;
}

- (NSURL *) _automaticURLForDate:(NSDate *)date
{
    NSString *day = [[self _formatter:@"yyyy-MM-dd"] stringFromDate:date];
    return [_directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"Music Library %@.ezmusiclibrary", day]];
}

- (NSURL *) _manualURLForDate:(NSDate *)date
{
    NSString *stamp = [[self _formatter:@"yyyy-MM-dd HHmmss"] stringFromDate:date];
    NSURL *url = [_directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"Music Library %@.ezmusiclibrary", stamp]];
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) return url;
    return [_directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"Music Library %@ %@.ezmusiclibrary", stamp, NSUUID.UUID.UUIDString]];
}

+ (NSDictionary *) verifiedEnvelopeAtURL:(NSURL *)url error:(NSError **)error
{
    NSData *archive = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!archive) return nil;
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    NSDictionary *envelope = [NSPropertyListSerialization propertyListWithData:archive options:NSPropertyListImmutable format:&format error:error];
    if (![envelope isKindOfClass:[NSDictionary class]] || ![envelope[@"format"] isEqual:@"EZEmbraceMusicLibrarySnapshot"] ||
        ![envelope[@"payload"] isKindOfClass:[NSData class]] || ![envelope[@"contentSHA256"] isKindOfClass:[NSString class]] ||
        ![envelope[@"createdAt"] isKindOfClass:[NSDate class]]) {
        if (error) *error = sBackupError(2, @"Snapshot envelope is invalid.");
        return nil;
    }
    NSData *payloadData = envelope[@"payload"];
    if (![sSHA256(payloadData) isEqual:envelope[@"contentSHA256"]]) {
        if (error) *error = sBackupError(3, @"Snapshot checksum does not match.");
        return nil;
    }
    NSDictionary *payload = [NSPropertyListSerialization propertyListWithData:payloadData options:NSPropertyListImmutable format:&format error:error];
    if (![payload isKindOfClass:[NSDictionary class]] || ![payload[@"schemaVersion"] isKindOfClass:[NSNumber class]] ||
        ![payload[@"tracks"] isKindOfClass:[NSArray class]] || ![payload[@"playlists"] isKindOfClass:[NSArray class]]) {
        if (error && !*error) *error = sBackupError(4, @"Snapshot payload is invalid.");
        return nil;
    }
    NSMutableDictionary *verified = [envelope mutableCopy];
    verified[@"decodedPayload"] = payload;
    return [verified copy];
}

- (NSArray<NSURL *> *) snapshotURLs
{
    NSArray *keys = @[NSURLIsRegularFileKey, NSURLNameKey];
    NSArray *urls = [NSFileManager.defaultManager contentsOfDirectoryAtURL:_directoryURL includingPropertiesForKeys:keys
        options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
    return [urls filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
        return [url.pathExtension isEqual:@"ezmusiclibrary"];
    }]];
}

- (NSDate *) latestSnapshotDate
{
    NSDate *latest;
    for (NSURL *url in [self snapshotURLs]) {
        NSDictionary *envelope = [self.class verifiedEnvelopeAtURL:url error:nil];
        NSDate *date = envelope[@"createdAt"];
        if (date && (!latest || [date compare:latest] == NSOrderedDescending)) latest = date;
    }
    return latest;
}

- (void) _applyRetention
{
    NSMutableArray *automaticRecords = [NSMutableArray array];
    NSMutableArray *manualRecords = [NSMutableArray array];
    for (NSURL *url in [self snapshotURLs]) {
        NSDictionary *envelope = [self.class verifiedEnvelopeAtURL:url error:nil];
        if (!envelope) continue;
        NSMutableArray *records = [envelope[@"automatic"] boolValue] ? automaticRecords : manualRecords;
        [records addObject:@{@"url":url, @"date":envelope[@"createdAt"]}];
    }
    NSComparator newestFirst = ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    };
    [automaticRecords sortUsingComparator:newestFirst];
    [manualRecords sortUsingComparator:newestFirst];
    NSMutableSet *keep = [NSMutableSet set];
    NSUInteger daily = MIN((NSUInteger)30, automaticRecords.count);
    for (NSUInteger index = 0; index < daily; index++) [keep addObject:automaticRecords[index][@"url"]];
    NSMutableSet *months = [NSMutableSet set];
    NSDateFormatter *monthFormatter = [self _formatter:@"yyyy-MM"];
    for (NSUInteger index = daily; index < automaticRecords.count && months.count < 12; index++) {
        NSString *month = [monthFormatter stringFromDate:automaticRecords[index][@"date"]];
        if ([months containsObject:month]) continue;
        [months addObject:month];
        [keep addObject:automaticRecords[index][@"url"]];
    }
    // Keep manual recovery points distinct, but bound them so repeated clicks cannot consume the disk indefinitely.
    NSUInteger manual = MIN((NSUInteger)20, manualRecords.count);
    for (NSUInteger index = 0; index < manual; index++) [keep addObject:manualRecords[index][@"url"]];
    for (NSDictionary *record in [automaticRecords arrayByAddingObjectsFromArray:manualRecords]) {
        if (![keep containsObject:record[@"url"]]) [NSFileManager.defaultManager removeItemAtURL:record[@"url"] error:nil];
    }
}

- (NSURL *) saveSnapshot:(MusicLibrarySnapshot *)snapshot atDate:(NSDate *)date force:(BOOL)force didWrite:(BOOL *)didWrite error:(NSError **)error
{
    if (didWrite) *didWrite = NO;
    if (!snapshot.isComplete || ![snapshot.backupPayload isKindOfClass:[NSDictionary class]]) {
        if (error) *error = sBackupError(1, @"Music library scan is incomplete.");
        return nil;
    }
    date = date ?: [NSDate date];
    if (![NSFileManager.defaultManager createDirectoryAtURL:_directoryURL withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSURL *url = force ? [self _manualURLForDate:date] : [self _automaticURLForDate:date];
    if (!force && [NSFileManager.defaultManager fileExistsAtPath:url.path] && [self.class verifiedEnvelopeAtURL:url error:nil]) return url;

    NSError *serializationError;
    NSData *payloadData = [NSPropertyListSerialization dataWithPropertyList:snapshot.backupPayload
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:&serializationError];
    if (!payloadData) { if (error) *error = serializationError; return nil; }
    NSDictionary *envelope = @{
        @"format":@"EZEmbraceMusicLibrarySnapshot", @"schemaVersion":@1, @"createdAt":date,
        @"automatic":@(!force), @"contentSHA256":sSHA256(payloadData), @"payload":payloadData,
        @"trackCount":@(snapshot.tracks.count), @"playlistCount":@(snapshot.playlists.count - (snapshot.playlists.count ? 1 : 0))
    };
    NSData *archive = [NSPropertyListSerialization dataWithPropertyList:envelope format:NSPropertyListBinaryFormat_v1_0 options:0 error:&serializationError];
    if (!archive) { if (error) *error = serializationError; return nil; }
    if (![archive writeToURL:url options:NSDataWritingAtomic error:error]) return nil;
    NSError *verifyError;
    if (![self.class verifiedEnvelopeAtURL:url error:&verifyError]) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        if (error) *error = verifyError;
        return nil;
    }
    if (didWrite) *didWrite = YES;
    [self _applyRetention];
    return url;
}

@end
