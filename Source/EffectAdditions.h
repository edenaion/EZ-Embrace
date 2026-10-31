// (c) 2015-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "EffectType.h"
#import "Preferences.h"

extern NSString * const EmbraceMappedEffect10BandEQ;
extern NSString * const EmbraceMappedEffect31BandEQ;
extern NSString * const EmbraceEffectDeclick;
extern NSString * const EmbraceEffectDehum;
extern NSString * const EmbraceEffectParametricEQ;

@class Effect;

BOOL EmbraceParametricEQIsEnabled(NSArray<Effect *> *effects);
// Returns the original array when bypassing existing units; nil if creation fails.
NSArray<Effect *> *EmbraceEffectsBySettingParametricEQEnabled(NSArray<Effect *> *effects, BOOL enabled);
BOOL EmbraceEffectNameIsManagedEqualizer(NSString *name);
// Removes legacy and duplicate managed EQs while preserving the first parametric EQ.
// When ensurePresent is true, a flat parametric EQ is created if needed.
NSArray<Effect *> *EmbraceEffectsWithSingleParametricEQ(NSArray<Effect *> *effects, BOOL ensurePresent);
NSString *EmbraceEqualizerEffectName(EqualizerType type);
BOOL EmbraceEqualizerIsEnabled(NSArray<Effect *> *effects, EqualizerType type);
NSArray<Effect *> *EmbraceEffectsBySettingEqualizerEnabled(NSArray<Effect *> *effects, EqualizerType type, BOOL enabled);
Effect *EmbraceEqualizerEffectWithState(NSDictionary *state, EqualizerType type);
// Call after built-in Audio Units are registered.
void EmbraceMigrateDefaultEqualizer(Preferences *preferences);


@interface EffectType (EmbraceAdditions)

+ (void) embrace_registerMappedEffects;

- (NSString *) friendlyName;

@end
