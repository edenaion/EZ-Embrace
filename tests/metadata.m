#import <Foundation/Foundation.h>
#import "MetadataParser.h"
#import "TrackKeys.h"

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        Check(argc > 1, @"Pass audio fixtures");
        for (int i = 1; i < argc; i++) {
            NSString *path = @(argv[i]);
            MetadataParser *parser = [[MetadataParser alloc] initWithURL:[NSURL fileURLWithPath:path] fallbackTitle:path.lastPathComponent];
            NSDictionary *metadata = parser.metadata;
            Check([metadata[TrackKeyTitle] length] > 0, @"Metadata retains a title");
            double duration = [metadata[TrackKeyDuration] doubleValue];
            Check(isfinite(duration) && duration > 0, @"Metadata retains finite positive duration");
            if ([path.lastPathComponent isEqualToString:@"layout-check.aiff"]) {
                Check([metadata[TrackKeyTitle] isEqualToString:@"Layout Élan 東京: a deliberately long track title for three-line layout testing"],
                    @"AIFF ID3 title retains Unicode");
                Check([metadata[TrackKeyArtist] isEqualToString:@"EZ QA Artist with a deliberately long artist name"],
                    @"AIFF ID3 retains long artist");
                Check([metadata[TrackKeyComments] isEqualToString:@"Disposable quiet fixture for typography and playback checks."],
                    @"AIFF ID3 retains comments");
            }
            for (id value in metadata.allValues) {
                if (![value isKindOfClass:NSString.class]) continue;
                Check([value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound,
                    [NSString stringWithFormat:@"%@ contains no NUL or control characters", path.lastPathComponent]);
            }
            NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:metadata format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
            Check(encoded != nil, @"Metadata can be persisted as a property list");
            Check(parser.metadata == metadata, @"Repeated metadata access reuses parsed result");
            printf("PASS: %s metadata\n", path.lastPathComponent.UTF8String);
        }
        printf("PASS: %lu metadata assertions\n", (unsigned long)checks);
    }
    return 0;
}
