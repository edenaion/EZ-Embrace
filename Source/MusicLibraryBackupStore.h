#import <Foundation/Foundation.h>

@class MusicLibrarySnapshot;

extern NSString * const MusicLibraryBackupErrorDomain;

@interface MusicLibraryBackupStore : NSObject

@property (nonatomic, readonly) NSURL *directoryURL;

+ (instancetype) defaultStore;
- (instancetype) initWithDirectoryURL:(NSURL *)directoryURL;

- (NSURL *) saveSnapshot:(MusicLibrarySnapshot *)snapshot
                   atDate:(NSDate *)date
                    force:(BOOL)force
                 didWrite:(BOOL *)didWrite
                    error:(NSError **)error;

- (NSArray<NSURL *> *) snapshotURLs;
- (NSDate *) latestSnapshotDate;
+ (NSDictionary *) verifiedEnvelopeAtURL:(NSURL *)url error:(NSError **)error;

@end
