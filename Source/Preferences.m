// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Preferences.h"
#import "HugAudioDevice.h"

NSString * const PreferencesDidChangeNotification = @"PreferencesDidChange";
NSString * const TextContrastDidChangeNotification = @"TextContrastDidChange";
NSString * const WindowBorderColorsDidChangeNotification = @"WindowBorderColorsDidChange";
NSString * const AuditionPreferencesDidChangeNotification = @"AuditionPreferencesDidChange";
NSString * const WindowBorderSetList = @"SetList";
NSString * const WindowBorderCurrentTrack = @"CurrentTrack";
NSString * const WindowBorderMusicLibrary = @"MusicLibrary";

static NSString * const sDeviceDictionaryUIDKey  = @"DeviceUID";
static NSString * const sDeviceDictionaryNameKey = @"Name";
static NSString * const sUpcomingOtherGenreColorKey = @"upcomingOtherGenreColor";


static NSColor *sColorFromComponents(id components)
{
    if (![components isKindOfClass:[NSArray class]] || [components count] != 3) return nil;
    for (id value in components) {
        if (![value isKindOfClass:[NSNumber class]] || !isfinite([value doubleValue]) ||
            [value doubleValue] < 0 || [value doubleValue] > 1) return nil;
    }
    return [NSColor colorWithSRGBRed:[components[0] doubleValue] green:[components[1] doubleValue]
                              blue:[components[2] doubleValue] alpha:1];
}


static NSArray *sComponentsFromColor(NSColor *color)
{
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb || !isfinite(rgb.redComponent) || !isfinite(rgb.greenComponent) ||
        !isfinite(rgb.blueComponent)) return nil;
    return @[@(rgb.redComponent), @(rgb.greenComponent), @(rgb.blueComponent)];
}

static NSDictionary *sGetDefaultValues()
{
    static NSDictionary *sDefaultValues = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{

    sDefaultValues = @{
        @"numberOfLayoutLines":  @2,
        @"textSizePercent":      @100,
        @"textContrastPercent":  @0,
        @"usesBoldText":         @NO,
        @"scalesInterfaceWithWindow": @NO,
        @"automaticallyArrangesWindows": @NO,
        @"shortensPlayedTracks": @NO,
    
        @"floatsOnTop":          @NO,
        
        @"themeType": @( ThemeTypeSystem ),

        @"showsAlbumArtist":     @NO,
        @"showsArtist":          @YES,
        @"showsBPM":             @YES,
        @"showsComments":        @NO,
        @"showsGrouping":        @NO,
        @"showsKeySignature":    @NO,
        @"showsEnergyLevel":     @NO,
        @"showsGenre":           @NO,
        @"showsDuplicateStatus": @YES,
        @"showsPlayingStatus":   @YES,
        @"showsStatusShape":     @NO,
        @"showsLabelDots":       @NO,
        @"showsLabelStripes":    @YES,
        @"showsYear":            @NO,

        @"scriptHandlerName":       @"",
        @"allowsAllEffects":        @NO,
        @"allowsPlaybackShortcuts": @NO,
        @"equalizerType":          @(EqualizerTypeParametric),

        @"keySignatureDisplayMode": @( KeySignatureDisplayModeRaw ),
        @"duplicateStatusMode":     @( DuplicateStatusModeSameFile ),
        
        @"mainOutputAudioDevice":  [HugAudioDevice placeholderDevice],
        @"mainOutputSampleRate":   @(44100),
        @"mainOutputFrames":       @(2048),
        @"mainOutputUsesHogMode":  @(NO),
        @"mainOutputResetsVolume": @(YES),
        @"auditionOutputDeviceUID": @"",
        @"auditionVolumePercent": @25,
        @"musicLibraryDailySnapshotsEnabled": @YES
    };
    
    });
    
    return sDefaultValues;
}


static void sSetDefaultObject(id dictionary, NSString *key, id valueToSave, id defaultValue)
{
    void (^saveObject)(NSObject *, NSString *) = ^(NSObject *o, NSString *k) {
        if (o) {
            [dictionary setObject:o forKey:k];
        } else {
            [dictionary removeObjectForKey:k];
        }
    };

    if ([defaultValue isKindOfClass:[NSNumber class]]) {
        saveObject(valueToSave, key);

    } else if ([defaultValue isKindOfClass:[HugAudioDevice class]]) {
        NSString *deviceUID = [valueToSave deviceUID];
        NSString *name      = [valueToSave name];
        
        if (deviceUID && name) {
            saveObject(@{
                sDeviceDictionaryUIDKey:deviceUID, 
                sDeviceDictionaryNameKey: name
            }, key);
        }

    } else if ([defaultValue isKindOfClass:[NSData class]]) {
        saveObject(valueToSave, key);

    } else if ([defaultValue isKindOfClass:[NSString class]]) {
        saveObject(valueToSave, key);
    }
}


static void sRegisterDefaults()
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if (![userDefaults objectForKey:@"textSizePercent"]) {
        [userDefaults setInteger:([userDefaults boolForKey:@"usesLargerText"] ? 125 : 100) forKey:@"textSizePercent"];
    }
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];

    NSDictionary *defaultValuesDictionary = sGetDefaultValues();

    for (NSString *key in defaultValuesDictionary) {
        id value = [defaultValuesDictionary objectForKey:key];
        sSetDefaultObject(defaults, key, value, value);
    }

    // Fresh installs start with one enabled, flat parametric EQ.
    [defaults setObject:@[ @{ @"name": @"EmbraceParametricEQ", @"bypass": @NO } ] forKey:@"effects"];

    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}


@implementation Preferences

- (NSColor *) upcomingOtherGenreColor
{
    NSColor *saved = sColorFromComponents([[NSUserDefaults standardUserDefaults]
        objectForKey:sUpcomingOtherGenreColorKey]);
    return saved ?: [NSColor colorWithSRGBRed:0.78 green:0.95 blue:0.85 alpha:1];
}

- (void) setUpcomingOtherGenreColor:(NSColor *)color
{
    NSArray *components = sComponentsFromColor(color);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (components) [defaults setObject:components forKey:sUpcomingOtherGenreColorKey];
    else [defaults removeObjectForKey:sUpcomingOtherGenreColorKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PreferencesDidChangeNotification object:self];
}

- (void) resetUpcomingOtherGenreColor
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:sUpcomingOtherGenreColorKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PreferencesDidChangeNotification object:self];
}

- (NSColor *) windowBorderColorForIdentifier:(NSString *)identifier
{
    id colors = [[NSUserDefaults standardUserDefaults] objectForKey:@"windowBorderColors"];
    if (![colors isKindOfClass:[NSDictionary class]]) return nil;
    return sColorFromComponents(colors[identifier]);
}

- (void) setWindowBorderColor:(NSColor *)color forIdentifier:(NSString *)identifier
{
    if (![@[WindowBorderSetList, WindowBorderCurrentTrack, WindowBorderMusicLibrary] containsObject:identifier]) return;
    id saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"windowBorderColors"];
    NSMutableDictionary *colors = [saved isKindOfClass:[NSDictionary class]] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    NSArray *components = sComponentsFromColor(color);
    if (components) colors[identifier] = components;
    else [colors removeObjectForKey:identifier];
    [[NSUserDefaults standardUserDefaults] setObject:colors forKey:@"windowBorderColors"];
    [[NSNotificationCenter defaultCenter] postNotificationName:WindowBorderColorsDidChangeNotification object:self];
}

- (void) resetWindowBorderColors
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"windowBorderColors"];
    [[NSNotificationCenter defaultCenter] postNotificationName:WindowBorderColorsDidChangeNotification object:self];
}


+ (instancetype) sharedInstance
{
    static Preferences *sSharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sRegisterDefaults();
        sSharedInstance = [[Preferences alloc] init];
    });
    
    return sSharedInstance;
}


- (id) init
{
    if ((self = [super init])) {
        [self _load];
        
        for (NSString *key in sGetDefaultValues()) {
            [self addObserver:self forKeyPath:key options:0 context:NULL];
        }
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *currentBuildString = GetAppBuildString();
        NSString *latestBuildString  = [defaults objectForKey:@"latest-build"];
        
        if (GetCombinedBuildNumber(currentBuildString) > GetCombinedBuildNumber(latestBuildString)) {
            [defaults setObject:currentBuildString forKey:@"latest-build"];
            latestBuildString = currentBuildString;
        }

        [defaults setObject:currentBuildString forKey:@"last-build"];

        _latestBuildString = latestBuildString;
    }

    return self;
}


- (void) _load
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if ([defaults integerForKey:@"mainOutputSampleRate"] == 0) {
        [defaults setInteger:44100 forKey:@"mainOutputSampleRate"];
    }
    
    if ([defaults integerForKey:@"mainOutputFrames"] == 0) {
        [defaults setInteger:2048 forKey:@"mainOutputFrames"];
    }

    NSDictionary *defaultValuesDictionary = sGetDefaultValues();
    for (NSString *key in defaultValuesDictionary) {
        id defaultValue = [defaultValuesDictionary objectForKey:key];

        if ([defaultValue isKindOfClass:[NSNumber class]]) {
            [self setValue:@([defaults integerForKey:key]) forKey:key];

        } else if ([defaultValue isKindOfClass:[NSData class]]) {
            [self setValue:[defaults objectForKey:key] forKey:key];

        } else if ([defaultValue isKindOfClass:[NSString class]]) {
            [self setValue:[defaults objectForKey:key] forKey:key];

        } else if ([defaultValue isKindOfClass:[HugAudioDevice class]]) {
            NSDictionary *dictionary = [defaults objectForKey:key];

            if ([dictionary isKindOfClass:[NSDictionary class]]) {
                NSString *name      = [dictionary objectForKey:sDeviceDictionaryNameKey];
                NSString *deviceUID = [dictionary objectForKey:sDeviceDictionaryUIDKey];
                
                if (name && deviceUID) {
                    HugAudioDevice *device = [HugAudioDevice archivedDeviceWithDeviceUID:deviceUID name:name];
                    if (device) [self setValue:device forKey:key];
                }

            } else {
                HugAudioDevice *device = [HugAudioDevice bestDefaultDevice];
                if (device) [self setValue:device forKey:key];
            }
        }
    }
}


+ (NSSet *) keyPathsForValuesAffectingUsesLargerText
{
    return [NSSet setWithObject:@"textSizePercent"];
}

- (BOOL) usesLargerText { return _textSizePercent > 100; }
- (void) setUsesLargerText:(BOOL)larger { [self setTextSizePercent:larger ? 125 : 100]; }

- (void) setTextSizePercent:(NSInteger)percent
{
    _textSizePercent = MIN(MAX(percent, 100), 200);
}

- (void) setTextContrastPercent:(NSInteger)percent
{
    _textContrastPercent = MIN(MAX(percent, 0), 100);
}


- (NSString *) _keyForTrackViewAttribute:(TrackViewAttribute)attribute
{
    if (attribute == TrackViewAttributeAlbumArtist) {
        return @"showsAlbumArtist";

    } else if (attribute == TrackViewAttributeArtist) {
        return @"showsArtist";

    } else if (attribute == TrackViewAttributeBeatsPerMinute) {
        return @"showsBPM";
        
    } else if (attribute == TrackViewAttributeComments) {
        return @"showsComments";

    } else if (attribute == TrackViewAttributeGrouping) {
        return @"showsGrouping";

    } else if (attribute == TrackViewAttributeKeySignature) {
        return @"showsKeySignature";
    
    } else if (attribute == TrackViewAttributeEnergyLevel) {
        return @"showsEnergyLevel";

    } else if (attribute == TrackViewAttributeGenre) {
        return @"showsGenre";

    } else if (attribute == TrackViewAttributeDuplicateStatus) {
        return @"showsDuplicateStatus";

    } else if (attribute == TrackViewAttributePlayingStatus) {
        return @"showsPlayingStatus";

    } else if (attribute == TrackViewAttributeStatusShape) {
        return @"showsStatusShape";

    } else if (attribute == TrackViewAttributeLabelDots) {
        return @"showsLabelDots";

    } else if (attribute == TrackViewAttributeLabelStripes) {
        return @"showsLabelStripes";

    } else if (attribute == TrackViewAttributeYear) {
        return @"showsYear";
    }

    return nil;
}


- (void) _save
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:[self usesLargerText] forKey:@"usesLargerText"];
    
    NSDictionary *defaultValuesDictionary = sGetDefaultValues();
    for (NSString *key in defaultValuesDictionary) {
        id defaultValue = [defaultValuesDictionary objectForKey:key];
        id selfValue    = [self valueForKey:key];
        
        sSetDefaultObject(defaults, key, selfValue, defaultValue);
    }
}


- (void) restoreDefaultColors
{
    NSDictionary *defaultValuesDictionary = sGetDefaultValues();

    for (NSString *key in defaultValuesDictionary) {
        id defaultValue = [defaultValuesDictionary objectForKey:key];

        if ([defaultValue isKindOfClass:[NSColor class]]) {
            [self setValue:defaultValue forKey:key];
        }
    }
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == self) {
        NSString *notification = [keyPath isEqualToString:@"textContrastPercent"]
            ? TextContrastDidChangeNotification : ([keyPath hasPrefix:@"audition"]
            ? AuditionPreferencesDidChangeNotification : PreferencesDidChangeNotification);
        [[NSNotificationCenter defaultCenter] postNotificationName:notification object:self];
        [self _save];
    }
}


- (void) setTrackViewAttribute:(TrackViewAttribute)attribute selected:(BOOL)selected
{
    NSString *key = [self _keyForTrackViewAttribute:attribute];
    if (!key) return;
    
    [self setValue:@(selected) forKey:key];
}


- (BOOL) isTrackViewAttributeSelected:(TrackViewAttribute)attribute
{
    NSString *key = [self _keyForTrackViewAttribute:attribute];
    if (!key) return NO;

    return [[self valueForKey:key] boolValue];
}


@end
