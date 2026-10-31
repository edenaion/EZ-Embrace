// (c) 2026 EmbraceNG contributors
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

// One classifier owns both the Set List highlight and playback automation.
// Compacting punctuation lets common library labels such as "Tango-Inst",
// "Alternative Vals" and "MilongaAlt" stay in the traditional group. Cant
// remains an exact token so unrelated words such as "Cantata" stay outside it.
NS_INLINE BOOL TrackGenreUsesUpcomingHighlight(NSString *genre)
{
    if (![genre isKindOfClass:NSString.class] || genre.length == 0) return YES;
    NSCharacterSet *separators = NSCharacterSet.alphanumericCharacterSet.invertedSet;
    NSArray<NSString *> *parts = [genre componentsSeparatedByCharactersInSet:separators];
    NSString *compactGenre = [parts componentsJoinedByString:@""];
    if ([compactGenre rangeOfString:@"tango" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [compactGenre rangeOfString:@"milonga" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [compactGenre rangeOfString:@"vals" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;

    for (NSString *part in parts) {
        if ([part caseInsensitiveCompare:@"cant"] == NSOrderedSame) return NO;
    }
    return YES;
}
