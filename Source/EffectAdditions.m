// (c) 2015-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "EffectAdditions.h"
#import "Effect.h"

NSString * const EmbraceMappedEffect10BandEQ = @"EmbraceGraphicEQ10";
NSString * const EmbraceMappedEffect31BandEQ = @"EmbraceGraphicEQ31";
NSString * const EmbraceEffectDeclick = @"EmbraceDeclick";
NSString * const EmbraceEffectDehum = @"EmbraceDehum";
NSString * const EmbraceEffectParametricEQ = @"EmbraceParametricEQ";

static NSString *sSavedEqualizerStateKey(NSString *name)
{
    return [@"EqualizerSavedState." stringByAppendingString:name];
}

BOOL EmbraceEffectNameIsManagedEqualizer(NSString *name)
{
    return [name isEqualToString:EmbraceEffectParametricEQ] ||
           [name isEqualToString:EmbraceMappedEffect10BandEQ] ||
           [name isEqualToString:EmbraceMappedEffect31BandEQ] ||
           [name isEqualToString:@"AUGraphicEQ"] ||
           [name isEqualToString:@"AUNBandEQ"];
}

void EmbraceMigrateDefaultEqualizer(Preferences *preferences)
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *domainName = NSBundle.mainBundle.bundleIdentifier;
    NSDictionary *domain = domainName.length ? [defaults persistentDomainForName:domainName] : nil;
    preferences.equalizerType = EqualizerTypeParametric;
    if (![domain isKindOfClass:NSDictionary.class]) return;

    NSArray *states = domain[@"effects"];
    if (![states isKindOfClass:NSArray.class]) return;

    NSDictionary *parametricState = nil;
    NSDictionary *firstManagedState = nil;
    NSUInteger firstManagedIndex = NSNotFound;
    NSUInteger managedCount = 0;
    NSMutableArray *otherStates = [NSMutableArray array];
    for (id value in states) {
        if (![value isKindOfClass:NSDictionary.class]) {
            [otherStates addObject:value];
            continue;
        }
        NSString *name = value[@"name"];
        if (!EmbraceEffectNameIsManagedEqualizer(name)) {
            [otherStates addObject:value];
            continue;
        }

        if (firstManagedIndex == NSNotFound) {
            firstManagedIndex = otherStates.count;
            firstManagedState = value;
        }
        managedCount++;
        if (!parametricState && [name isEqualToString:EmbraceEffectParametricEQ]) {
            parametricState = value;
        } else if (![name isEqualToString:EmbraceEffectParametricEQ] && name.length) {
            NSString *backupKey = sSavedEqualizerStateKey(name);
            if (![defaults objectForKey:backupKey]) [defaults setObject:value forKey:backupKey];
        }
    }

    if (managedCount == 1 && parametricState) return;

    if (!parametricState) {
        id saved = [defaults objectForKey:sSavedEqualizerStateKey(EmbraceEffectParametricEQ)];
        if ([saved isKindOfClass:NSDictionary.class] &&
            [saved[@"name"] isEqualToString:EmbraceEffectParametricEQ]) {
            parametricState = saved;
        } else {
            id bypass = [firstManagedState[@"bypass"] isKindOfClass:NSNumber.class]
                ? firstManagedState[@"bypass"] : @NO;
            parametricState = @{ @"name": EmbraceEffectParametricEQ, @"bypass": bypass };
        }
    }

    NSUInteger insertionIndex = firstManagedIndex == NSNotFound ? otherStates.count : firstManagedIndex;
    [otherStates insertObject:parametricState atIndex:insertionIndex];
    [defaults setObject:otherStates forKey:@"effects"];
}

BOOL EmbraceParametricEQIsEnabled(NSArray<Effect *> *effects)
{
    return EmbraceEqualizerIsEnabled(effects, EqualizerTypeParametric);
}

NSArray<Effect *> *EmbraceEffectsBySettingParametricEQEnabled(NSArray<Effect *> *effects, BOOL enabled)
{
    return EmbraceEffectsBySettingEqualizerEnabled(effects, EqualizerTypeParametric, enabled);
}

NSArray<Effect *> *EmbraceEffectsWithSingleParametricEQ(NSArray<Effect *> *effects, BOOL ensurePresent)
{
    NSArray<Effect *> *source = effects ?: @[];
    NSMutableArray<Effect *> *result = [NSMutableArray arrayWithCapacity:source.count + 1];
    Effect *parametric = nil;
    Effect *firstManaged = nil;
    NSUInteger insertionIndex = NSNotFound;

    for (Effect *effect in source) {
        NSString *name = effect.type.name;
        if (!EmbraceEffectNameIsManagedEqualizer(name)) {
            [result addObject:effect];
            continue;
        }
        if (insertionIndex == NSNotFound) {
            insertionIndex = result.count;
            firstManaged = effect;
        }
        if (!parametric && [name isEqualToString:EmbraceEffectParametricEQ]) parametric = effect;
    }

    if (!parametric && ensurePresent) {
        parametric = EmbraceEqualizerEffectWithState(nil, EqualizerTypeParametric);
        if (!parametric || !parametric.audioUnit) return nil;
        if (firstManaged) parametric.bypass = firstManaged.bypass;
    }
    if (parametric) {
        NSUInteger index = insertionIndex == NSNotFound ? result.count : insertionIndex;
        [result insertObject:parametric atIndex:index];
    }

    if (result.count == source.count) {
        BOOL unchanged = YES;
        for (NSUInteger index = 0; index < result.count; index++) {
            if (result[index] != source[index]) { unchanged = NO; break; }
        }
        if (unchanged) return source;
    }
    return [result copy];
}

NSString *EmbraceEqualizerEffectName(EqualizerType type)
{
    (void)type;
    return EmbraceEffectParametricEQ;
}

BOOL EmbraceEqualizerIsEnabled(NSArray<Effect *> *effects, EqualizerType type)
{
    (void)type;
    for (Effect *effect in effects) {
        if ([effect.type.name isEqualToString:EmbraceEffectParametricEQ] && effect.audioUnit && !effect.bypass) return YES;
    }
    return NO;
}

NSArray<Effect *> *EmbraceEffectsBySettingEqualizerEnabled(NSArray<Effect *> *effects, EqualizerType type, BOOL enabled)
{
    (void)type;
    NSArray<Effect *> *normalized = EmbraceEffectsWithSingleParametricEQ(effects, YES);
    if (!normalized) return nil;
    for (Effect *effect in normalized) {
        if (![effect.type.name isEqualToString:EmbraceEffectParametricEQ]) continue;
        if (enabled && !effect.audioUnit) return nil;
        effect.bypass = !enabled;
        return normalized;
    }
    return nil;
}

Effect *EmbraceEqualizerEffectWithState(NSDictionary *state, EqualizerType type)
{
    NSString *name = EmbraceEqualizerEffectName(type);
    if ([state isKindOfClass:NSDictionary.class]) {
        Effect *savedEffect = [Effect effectWithStateDictionary:state];
        if ([savedEffect.type.name isEqualToString:name]) return savedEffect;
    }
    for (EffectType *effectType in EffectType.allEffectTypes) {
        if ([effectType.name isEqualToString:name]) return [Effect effectWithEffectType:effectType];
    }
    return nil;
}


@implementation EffectType (EmbraceAdditions)

+ (void) embrace_registerMappedEffects
{
    AudioComponentDescription acd = {0};
    
    acd.componentType = kAudioUnitType_Effect;
    acd.componentSubType = kAudioUnitSubType_GraphicEQ;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;

    [self registerMappedTypeWithName:EmbraceMappedEffect10BandEQ audioComponentDescription:&acd configurator:^(AUAudioUnit *unit) {
        AUParameter *parameter = [[unit parameterTree] parameterWithID:kGraphicEQParam_NumberOfBands scope:kAudioUnitScope_Global element:0];
        [parameter setValue:0];
    }];

    [self registerMappedTypeWithName:EmbraceMappedEffect31BandEQ audioComponentDescription:&acd configurator:^(AUAudioUnit *unit) {
        AUParameter *parameter = [[unit parameterTree] parameterWithID:kGraphicEQParam_NumberOfBands scope:kAudioUnitScope_Global element:0];
        [parameter setValue:1.0];
    }];
}


- (NSString *) friendlyName
{
    NSString *name = [self name];

    NSDictionary *map = @{
        EmbraceMappedEffect10BandEQ: NSLocalizedString(@"10-band Graphic Equalizer", nil),
        EmbraceMappedEffect31BandEQ: NSLocalizedString(@"31-band Graphic Equalizer", nil),
        EmbraceEffectDeclick: NSLocalizedString(@"Declick", nil),
        EmbraceEffectDehum: NSLocalizedString(@"Dehum", nil),
        EmbraceEffectParametricEQ: NSLocalizedString(@"Parametric Equalizer", nil),

        @"AUDynamicsProcessor":   NSLocalizedString(@"Dynamics Processor", nil),
        @"AUHipass":              NSLocalizedString(@"Highpass Filter", nil),
        @"AUBandpass":            NSLocalizedString(@"Bandpass Filter", nil),
        @"AUHighShelfFilter":     NSLocalizedString(@"Highshelf Filter", nil),
        @"AUPeakLimiter":         NSLocalizedString(@"Peak Limiter", nil),
        @"AULowpass":             NSLocalizedString(@"Lowpass Filter", nil),
        @"AULowShelfFilter":      NSLocalizedString(@"Lowshelf Filter", nil),
        @"AUMultibandCompressor": NSLocalizedString(@"Multiband Compressor", nil),
        @"AUParametricEQ":        NSLocalizedString(@"1-Band Parametric Filter", nil),
        @"AUFilter":              NSLocalizedString(@"5-Band Parametric Filter", nil),
    };
    
    NSString *friendlyName = [map objectForKey:name];
    
    if (!friendlyName) {
        friendlyName = name;
    }
    
    return friendlyName;
}


@end
