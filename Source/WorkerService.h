// (c) 2016-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, WorkerTrackCommand) {
    WorkerTrackCommandReadMetadata,         // Reads the file metadating using AVAsset
    WorkerTrackCommandReadLoudness,         // Reads loudness via LoudnessAnalyzer
    WorkerTrackCommandReadLoudnessImmediate // Reads loudness via LoudnessAnalyzer immediately
};


@protocol WorkerProtocol

- (void) cancelUUID:(NSUUID *)uuid;

- (void) performTrackCommand: (WorkerTrackCommand) command
                        UUID: (NSUUID *) uuid
                bookmarkData: (NSData *) bookmarkData
            originalFilename: (NSString *) originalFilename
                       reply: (void (^)(NSDictionary *))reply;

- (void) performLibraryParseWithReply: (void (^)(NSDictionary *))reply;
- (void) performMusicLibraryFetchWithReply:(void (^)(NSDictionary *snapshot, NSString *errorMessage))reply;

@end

NS_INLINE NSXPCInterface *EmbraceWorkerXPCInterface(void)
{
    NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(WorkerProtocol)];
    NSSet *classes = [NSSet setWithObjects:NSDictionary.class, NSArray.class, NSString.class, NSNumber.class, NSDate.class, nil];
    [interface setClasses:classes forSelector:@selector(performMusicLibraryFetchWithReply:) argumentIndex:0 ofReply:YES];
    return interface;
}
