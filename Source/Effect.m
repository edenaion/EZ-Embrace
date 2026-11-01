// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Effect.h"
#import "EffectType.h"
#import "Player.h"
#import "EditEffectController.h"
#import "AudioUnitStateValidation.h"
#import "EffectAdditions.h"
#import "ParametricEQAudioUnit.h"

static NSString *sNameKey = @"name";
static NSString *sInfoKey = @"info";
static NSString *sUUIDKey = @"UUID";
static NSString *sBypassKey = @"bypass";

NSString * const EffectDidDeallocNotification = @"EffectDidDealloc";
NSString * const EffectBypassDidChangeNotification = @"EffectBypassDidChange";
NSString * const EffectEQPresetDidChangeNotification = @"EffectEQPresetDidChange";


@implementation Effect {
    EffectType   *_type;
    NSDictionary *_defaultFullState;
    EffectSettingsController *_settingsController;
}

@dynamic hasCustomView;

// Adapted from EmbraceNG f01944d4 and aeaf918a, under LICENSE.EmbraceNG.
- (BOOL) _applyFullState:(NSDictionary *)fullState toAudioUnit:(AUAudioUnit *)audioUnit
{
    if (!fullState || !audioUnit) return NO;
    if (!EmbraceAudioUnitFullStateIsWellFormed(fullState, [audioUnit componentDescription])) {
        EmbraceLog(@"Effect", @"Refusing malformed state for %@; keeping current values", [_type name]);
        return NO;
    }

    // Apple's N-band editor traps when a preset changes its band count.
    NSDictionary *state = EmbraceAudioUnitFullStateByPreservingBandCount(fullState, audioUnit);
    [audioUnit setFullState:state];
    return YES;
}


+ (instancetype) effectWithStateDictionary:(NSDictionary *)dictionary
{
    return [[self alloc] initWithStateDictionary:dictionary];
}


+ (instancetype) effectWithEffectType:(EffectType *)effectType
{
    return [[self alloc] _initWithEffectType:effectType UUID:nil];
}


- (id) _initWithEffectType:(EffectType *)effectType UUID:(NSUUID *)UUID
{
    if ((self = [super init])) {
        _type = effectType;
        _UUID = UUID ? UUID : [NSUUID UUID];
        
        NSError *error = nil;
        _audioUnit = [[AUAudioUnit alloc] initWithComponentDescription:[effectType AudioComponentDescription] error:&error];
        _audioUnitError = error;

        if (_audioUnit) {
            MappedEffectTypeConfigurator configurator = [effectType configurator];
            if (configurator) configurator(_audioUnit);
        }

        NSString *defaultPresetPath = [[NSBundle mainBundle] pathForResource:[[self type] name] ofType:@"aupreset"];
        if (defaultPresetPath) {
            NSDictionary *defaultPreset = [NSDictionary dictionaryWithContentsOfFile:defaultPresetPath];
            [self _applyFullState:defaultPreset toAudioUnit:_audioUnit];
        }

        _defaultFullState = [_audioUnit fullState];
    }
    
    return self;
}


- (id) initWithEffectType:(EffectType *)effectType
{
    return [self _initWithEffectType:effectType UUID:nil];
}


- (id) initWithStateDictionary:(NSDictionary *)dictionary
{
    NSString *name       = [dictionary objectForKey:sNameKey];
    NSData   *info       = [dictionary objectForKey:sInfoKey];
    NSString *UUIDString = [dictionary objectForKey:sUUIDKey];

    if (
                       ![name isKindOfClass:[NSString class]] ||
        (info       && ![info isKindOfClass:[NSData class]]) ||
        (UUIDString && ![UUIDString isKindOfClass:[NSString class]])
    ) {
        self = nil;
        return nil;
    }
    
    EffectType *typeToUse = nil;

    for (EffectType *type in [EffectType allEffectTypes]) {
        if ([[type name] isEqualToString:name]) {
            typeToUse = type;
        }
    }
    
    if (!typeToUse) {
        self = nil;
        return nil;
    }
    
    NSUUID *UUID = UUIDString ? [[NSUUID alloc] initWithUUIDString:UUIDString] : nil;
    
    self = [self _initWithEffectType:typeToUse UUID:UUID];
 
    if (info) {
        NSError *error = nil;
        
        NSDictionary *fullState = [NSPropertyListSerialization propertyListWithData:info options:NSPropertyListImmutable format:NULL error:&error];
        if (!fullState || error) {
            self = nil;
            return nil;
        }
        // Keep a known effect at defaults if its stored parameter blob is corrupt.
        [self _applyFullState:fullState toAudioUnit:_audioUnit];
    }

    id bypass = dictionary[sBypassKey];
    if ([bypass isKindOfClass:[NSNumber class]]) [self setBypass:[bypass boolValue]];
    return self;
}


- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] postNotificationName:EffectDidDeallocNotification object:nil];
}


#pragma mark - Private Methods

- (BOOL) _setFullState:(NSDictionary *)fullState
{
    if (![self _applyFullState:fullState toAudioUnit:_audioUnit]) return NO;

    // As of 10.14, -setFullState: appears to not update the AUParameter's -value, which
    // is likely a caching bug in Apple's code. To get around this, create a fake AUAudioUnit
    // of the same componentDescription, call -setFullState: on it, and then send -setValue:
    // to our real AUParameter objects
    //
    NSError *error = nil;
    AUAudioUnit *fakeUnit = [[AUAudioUnit alloc] initWithComponentDescription:[_audioUnit componentDescription] error:&error];

    if (!error && [self _applyFullState:fullState toAudioUnit:fakeUnit]) {
        for (AUParameter *fakeParameter in [[fakeUnit parameterTree] allParameters]) {
            AUParameter *realParameter = [[_audioUnit parameterTree] parameterWithAddress:[fakeParameter address]];
            [realParameter setValue:[fakeParameter value] originator:NULL];
        }
    }
    return YES;
}


#pragma mark - Public Methods

- (void) loadAudioPresetAtFileURL:(NSURL *)fileURL
{
    NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfURL:fileURL];
    if (!dictionary) return;

    [self _setFullState:dictionary];
}


- (BOOL) saveAudioPresetAtFileURL:(NSURL *)fileURL
{
    return [[_audioUnit fullState] writeToURL:fileURL atomically:YES];
}


- (void) restoreDefaultValues
{
    [self _setFullState:_defaultFullState];
}


- (BOOL) supportsEQPresetSlots
{
    return [@[EmbraceMappedEffect10BandEQ, EmbraceMappedEffect31BandEQ, EmbraceEffectParametricEQ] containsObject:[_type name] ?: @""];
}


- (NSString *) _EQPresetKeyForSlot:(EQPresetSlot)slot
{
    // Mapped graphic EQs share an AU component but need separate band layouts.
    if (![self supportsEQPresetSlots] || (slot != EQPresetSlotViolin && slot != EQPresetSlotSinger)) return nil;
    return [NSString stringWithFormat:@"EQPresetSlot.%@.%ld", [_type name], (long)slot];
}


- (NSDictionary *) _EQPresetStateForSlot:(EQPresetSlot)slot
{
    NSString *key = [self _EQPresetKeyForSlot:slot];
    if (!key) return nil;
    id data = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    id state = nil;
    if (data) {
        if (![data isKindOfClass:[NSData class]]) return nil;
        state = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    } else if ([[_type name] isEqualToString:EmbraceEffectParametricEQ]) {
        NSString *name = slot == EQPresetSlotViolin ? @"Violin" : @"Singer";
        NSString *resource = [@"EmbraceParametricEQ-" stringByAppendingString:name];
        NSURL *url = [[NSBundle mainBundle] URLForResource:resource withExtension:@"aupreset"];
        state = url ? [NSDictionary dictionaryWithContentsOfURL:url] : nil;
    }
    return EmbraceAudioUnitFullStateIsWellFormed(state, [_audioUnit componentDescription]) ? state : nil;
}


- (BOOL) hasEQPresetInSlot:(EQPresetSlot)slot
{
    return _audioUnit && [self _EQPresetStateForSlot:slot] != nil;
}


- (BOOL) saveEQPresetInSlot:(EQPresetSlot)slot
{
    NSString *key = [self _EQPresetKeyForSlot:slot];
    NSDictionary *state = [_audioUnit fullState];
    if (!key || !_audioUnit || !EmbraceAudioUnitFullStateIsWellFormed(state, [_audioUnit componentDescription])) return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!data) return NO;
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:EffectEQPresetDidChangeNotification object:self];
    return YES;
}


- (BOOL) loadEQPresetInSlot:(EQPresetSlot)slot
{
    return [self _setFullState:[self _EQPresetStateForSlot:slot]];
}


- (BOOL) matchesEQPresetInSlot:(EQPresetSlot)slot
{
    NSDictionary *preset = [self _EQPresetStateForSlot:slot];
    NSData *expected = preset[@"data"];
    NSData *current = [_audioUnit fullState][@"data"];
    // These EQs serialize parameter values in data. Preset names and bypass
    // belong to separate state and must not affect a settings match.
    if (_audioUnit && [expected isKindOfClass:[NSData class]] && [expected isEqual:current]) return YES;
    if ([[_type name] isEqualToString:EmbraceEffectParametricEQ]) {
        NSError *error = nil;
        AUAudioUnit *reference = [[AUAudioUnit alloc] initWithComponentDescription:[_audioUnit componentDescription]
                                                                           error:&error];
        if (!_audioUnit || !preset || !reference || error) return NO;
        reference.fullState = preset;
        for (AUParameter *expected in reference.parameterTree.allParameters) {
            AUParameter *current = [_audioUnit.parameterTree parameterWithAddress:expected.address];
            if (!current || fabs(current.value - expected.value) > .0001) return NO;
        }
        return YES;
    }
    return NO;
}


- (BOOL) hasFlatEQResponse
{
    if (![self supportsEQPresetSlots] || !_audioUnit) return NO;
    AUParameterTree *tree = [_audioUnit parameterTree];
    if ([[_type name] isEqualToString:EmbraceEffectParametricEQ]) {
        if (EmbraceParametricEQHasAutomaticFlatResponse(_audioUnit)) return YES;
        if ([tree parameterWithAddress:EmbraceParametricEQParameterFilterSlope].value != 0) return NO;
        for (AUParameter *parameter in tree.allParameters) {
            if (parameter.unit == kAudioUnitParameterUnit_Decibels && fabs(parameter.value) > .0001) return NO;
        }
    } else {
        NSUInteger count = [[_type name] isEqualToString:EmbraceMappedEffect31BandEQ] ? 31 : 10;
        for (NSUInteger i = 0; i < count; i++) {
            AUParameter *parameter = [tree parameterWithID:(AudioUnitParameterID)i scope:kAudioUnitScope_Global element:0];
            if (!parameter || fabs(parameter.value) > .0001) return NO;
        }
    }
    return YES;
}


- (NSDictionary *) stateDictionary
{
    NSDictionary *fullState = [_audioUnit fullState];
    if (!fullState) fullState = [NSDictionary dictionary];
    
    NSError  *error = nil;
    NSString *name  = [_type name];
    NSData   *info  = [NSPropertyListSerialization dataWithPropertyList:fullState format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    
    if (error || !info || !name) return nil;
    
    return @{
        sNameKey: name,
        sInfoKey: info,
        sUUIDKey: [_UUID UUIDString],
        sBypassKey: @([self bypass])
    };
}


#pragma mark - Accessors

- (BOOL) hasCustomView
{
    return [_audioUnit providesUserInterface];
}


- (void) setBypass:(BOOL)bypass
{
    BOOL previous = [self bypass];
    [_audioUnit setShouldBypassEffect:bypass];
    if (previous != [self bypass]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:EffectBypassDidChangeNotification object:self];
    }
}


- (BOOL) bypass
{
    return [_audioUnit shouldBypassEffect];
}

@end

