#import "Effect.h"
#import "EffectType.h"
#import "EffectAdditions.h"
#import "AudioUnitStateValidation.h"
#import "ParametricEQAudioUnit.h"

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

static EffectType *Type(OSType subtype, OSType manufacturer)
{
    for (EffectType *type in [EffectType allEffectTypes]) {
        AudioComponentDescription description = type.AudioComponentDescription;
        if (description.componentSubType == subtype && description.componentManufacturer == manufacturer) return type;
    }
    return nil;
}

static EffectType *NamedType(NSString *name)
{
    for (EffectType *type in [EffectType allEffectTypes]) if ([type.name isEqualToString:name]) return type;
    return nil;
}

static void CheckFactoryPreset(Effect *effect, EQPresetSlot slot, NSString *name)
{
    NSURL *url = [NSBundle.mainBundle URLForResource:[@"EmbraceParametricEQ-" stringByAppendingString:name] withExtension:@"aupreset"];
    NSDictionary *state = url ? [NSDictionary dictionaryWithContentsOfURL:url] : nil;
    Check(state != nil, [name stringByAppendingString:@" factory resource is bundled"]);
    NSError *error = nil;
    AUAudioUnit *reference = [[AUAudioUnit alloc] initWithComponentDescription:effect.audioUnit.componentDescription error:&error];
    Check(reference != nil && error == nil, @"Independent factory reference unit instantiates");
    reference.fullState = state;
    Check([effect loadEQPresetInSlot:slot], [name stringByAppendingString:@" factory preset loads through production code"]);
    Check([effect matchesEQPresetInSlot:slot], [name stringByAppendingString:@" matches its factory values after recall"]);
    for (AUParameter *parameter in reference.parameterTree.allParameters) {
        AUParameter *actual = [effect.audioUnit.parameterTree parameterWithAddress:parameter.address];
        Check(actual != nil && fabs(actual.value - parameter.value) < .001, [NSString stringWithFormat:@"%@ factory parameter %@ matches bundled state", name, parameter.identifier]);
    }
    NSString *key = [NSString stringWithFormat:@"EQPresetSlot.%@.%ld", EmbraceEffectParametricEQ, (long)slot];
    Check([NSUserDefaults.standardUserDefaults objectForKey:key] == nil, @"Factory recall does not create a user override");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        NSString *domain = NSProcessInfo.processInfo.processName;
        Check([domain isEqualToString:@"state-tests"], @"Preset checks use an isolated preferences domain");
        Check([NSBundle.mainBundle.bundleIdentifier isEqualToString:domain], @"Test bundle resources use the isolated preferences domain");
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        EmbraceRegisterParametricEQAudioUnit();
        [EffectType embrace_registerMappedEffects];
        if (argc > 1 && strcmp(argv[1], "--verify-slots") == 0) {
            Effect *reopened = [Effect effectWithEffectType:NamedType(EmbraceEffectParametricEQ)];
            AUParameter *gain = [reopened.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain];
            Check([reopened loadEQPresetInSlot:EQPresetSlotViolin] && fabs(gain.value + 3.5) < .001, @"A new process recalls the replaced Violin preset");
            Check([reopened loadEQPresetInSlot:EQPresetSlotSinger] && fabs(gain.value + 6) < .001, @"A new process recalls the separate Singer preset");
            [defaults removePersistentDomainForName:domain];
            printf("PASS: %lu preset restart assertions\n", (unsigned long)checks);
            return 0;
        }
        [defaults removePersistentDomainForName:domain];
        OSType appleTypes[] = {kAudioUnitSubType_NBandEQ, kAudioUnitSubType_GraphicEQ,
            kAudioUnitSubType_ParametricEQ, kAudioUnitSubType_DynamicsProcessor,
            kAudioUnitSubType_MultiBandCompressor, kAudioUnitSubType_PeakLimiter,
            kAudioUnitSubType_LowPassFilter, kAudioUnitSubType_HighShelfFilter,
            kAudioUnitSubType_Delay, kAudioUnitSubType_MatrixReverb};
        for (NSUInteger i = 0; i < sizeof(appleTypes) / sizeof(*appleTypes); i++) {
            Effect *effect = [Effect effectWithEffectType:Type(appleTypes[i], kAudioUnitManufacturer_Apple)];
            Check(effect.audioUnit != nil, @"Apple reference unit instantiates");
            Check(EmbraceAudioUnitFullStateIsWellFormed(effect.audioUnit.fullState, effect.audioUnit.componentDescription), @"Apple unit's valid state passes screening");
        }

        Effect *effect = [Effect effectWithEffectType:Type(kAudioUnitSubType_NBandEQ, kAudioUnitManufacturer_Apple)];
        AUAudioUnit *unit = effect.audioUnit;
        NSDictionary *valid = unit.fullState;
        NSMutableDictionary *malformed = [valid mutableCopy];
        NSMutableData *blob = [valid[@"data"] mutableCopy];
        Check(blob.length >= 12, @"Reference state contains its complete header");
        uint8_t *bytes = blob.mutableBytes;
        bytes[8] = 0; bytes[9] = 0x10; bytes[10] = bytes[11] = 0;
        malformed[@"data"] = blob;
        Check(!EmbraceAudioUnitFullStateIsWellFormed(malformed, unit.componentDescription), @"Oversized record count is rejected before Apple's parser");
        for (NSUInteger length = 0; length < 12; length++) {
            malformed[@"data"] = [NSMutableData dataWithLength:length];
            Check(!EmbraceAudioUnitFullStateIsWellFormed(malformed, unit.componentDescription), @"Truncated header is rejected");
        }
        malformed[@"data"] = @"Invalid type";
        Check(!EmbraceAudioUnitFullStateIsWellFormed(malformed, unit.componentDescription), @"Wrong blob type is rejected");
        Check(!EmbraceAudioUnitFullStateIsWellFormed((id)@[], unit.componentDescription), @"Wrong root type is rejected");
        malformed[@"data"] = blob;
        NSURL *preset = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"aupreset"]]];
        Check([malformed writeToURL:preset atomically:YES], @"Corrupt preset fixture writes");
        [effect loadAudioPresetAtFileURL:preset];
        Check([unit.fullState isEqual:valid], @"Production preset loader leaves current state unchanged on rejection");
        NSDictionary *stored = @{ @"name": effect.type.name, @"info": [NSPropertyListSerialization dataWithPropertyList:malformed format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL] };
        Effect *restored = [Effect effectWithStateDictionary:stored];
        Check(restored.audioUnit != nil, @"Saved chain retains a known effect when its blob is corrupt");
        Check([restored.audioUnit.fullState isEqual:valid], @"Corrupt saved effect uses defaults");
        NSMutableDictionary *differentBands = [valid mutableCopy];
        differentBands[@"numberOfBands"] = @2;
        Check([differentBands writeToURL:preset atomically:YES], @"Band-count fixture writes");
        for (int i = 0; i < 8; i++) [effect loadAudioPresetAtFileURL:preset];
        Check([unit.fullState[@"numberOfBands"] isEqual:valid[@"numberOfBands"]], @"Production loader preserves Apple's band count");
        [effect restoreDefaultValues];
        Check([unit.fullState isEqual:valid], @"Restore defaults remains valid");

        Effect *custom = [Effect effectWithEffectType:Type(EmbraceParametricEQSubType, EmbraceParametricEQManufacturer)];
        Check(custom.audioUnit != nil, @"Custom EQ instantiates through production Effect");
        AUParameter *gain = [custom.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain];
        gain.value = 7;
        Check([custom saveAudioPresetAtFileURL:preset], @"Production loader saves custom EQ preset");
        gain.value = -5;
        [custom loadAudioPresetAtFileURL:preset];
        Check(fabs(gain.value - 7) < .001, @"Custom EQ preset restores gain through production code");
        Effect *roundTrip = [Effect effectWithStateDictionary:custom.stateDictionary];
        Check(fabs([roundTrip.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain].value - 7) < .001, @"Saved set list restores custom EQ gain");
        [custom restoreDefaultValues];
        Check(fabs(gain.value) < .001, @"Custom EQ defaults restore flat gain");
        Check(EmbraceAudioUnitFullStateIsWellFormed(@{ @"data": @"Opaque vendor data" }, custom.audioUnit.componentDescription), @"Non-Apple state remains opaque");
        Check([custom supportsEQPresetSlots], @"Custom EQ exposes preset slots");
        Check([custom hasEQPresetInSlot:EQPresetSlotViolin] && [custom hasEQPresetInSlot:EQPresetSlotSinger], @"Both custom slots have shipping factory presets");
        CheckFactoryPreset(custom, EQPresetSlotViolin, @"Violin");
        CheckFactoryPreset(custom, EQPresetSlotSinger, @"Singer");
        Check(![custom saveEQPresetInSlot:0] && ![custom loadEQPresetInSlot:3], @"Invalid slot numbers are rejected");
        AUParameter *frequency = [custom.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFFrequency];
        AUParameter *output = [custom.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterOutputGain];
        gain.value = 3; frequency.value = 175; output.value = -2;
        Check([custom saveEQPresetInSlot:EQPresetSlotViolin], @"Violin stores the current EQ");
        gain.value = -6; frequency.value = 250; output.value = 1;
        Check([custom saveEQPresetInSlot:EQPresetSlotSinger], @"Singer stores different current values");
        Check([custom loadEQPresetInSlot:EQPresetSlotViolin] && fabs(gain.value - 3) < .001 && fabs(frequency.value - 175) < .001 && fabs(output.value + 2) < .001, @"Violin restores gains, frequency and output trim");
        Check([custom matchesEQPresetInSlot:EQPresetSlotViolin] && ![custom matchesEQPresetInSlot:EQPresetSlotSinger], @"Only the matching saved preset is active");
        frequency.value = 176;
        Check(![custom matchesEQPresetInSlot:EQPresetSlotViolin], @"Changing a frequency clears the preset match");
        frequency.value = 175;
        custom.bypass = YES;
        Check([custom matchesEQPresetInSlot:EQPresetSlotViolin], @"Bypass does not erase the selected preset match");
        custom.bypass = NO;
        Check([custom loadEQPresetInSlot:EQPresetSlotSinger] && fabs(gain.value + 6) < .001 && fabs(frequency.value - 250) < .001 && fabs(output.value - 1) < .001, @"Singer restores its own complete EQ");
        gain.value = -3.5; frequency.value = 220; output.value = -1;
        Check([custom saveEQPresetInSlot:EQPresetSlotViolin] && fabs(gain.value + 3.5) < .001, @"Replacing Violin saves without changing the current EQ");
        [custom restoreDefaultValues];
        Check([custom hasEQPresetInSlot:EQPresetSlotViolin] && [custom hasEQPresetInSlot:EQPresetSlotSinger], @"Flat defaults do not erase user slots");
        Check([custom loadEQPresetInSlot:EQPresetSlotViolin] && fabs(gain.value + 3.5) < .001, @"Violin recalls its replacement");
        Effect *second = [Effect effectWithEffectType:NamedType(EmbraceEffectParametricEQ)];
        Check([second loadEQPresetInSlot:EQPresetSlotSinger] && fabs([second.audioUnit.parameterTree parameterWithAddress:EmbraceParametricEQParameterLFGain].value + 6) < .001, @"Another EQ instance recalls shared user slots");
        Effect *ten = [Effect effectWithEffectType:NamedType(EmbraceMappedEffect10BandEQ)];
        Effect *thirtyOne = [Effect effectWithEffectType:NamedType(EmbraceMappedEffect31BandEQ)];
        Check([ten supportsEQPresetSlots] && [thirtyOne supportsEQPresetSlots], @"Both graphic EQ editors support slots");
        Check(![ten hasEQPresetInSlot:EQPresetSlotViolin] && ![thirtyOne hasEQPresetInSlot:EQPresetSlotViolin], @"Different EQ types do not inherit custom EQ values");
        NSDictionary *emptySlotBefore = ten.audioUnit.fullState;
        Check(![ten loadEQPresetInSlot:EQPresetSlotViolin] && [ten.audioUnit.fullState isEqual:emptySlotBefore], @"An empty graphic EQ slot leaves current values unchanged");
        Check([ten saveEQPresetInSlot:EQPresetSlotViolin] && [ten loadEQPresetInSlot:EQPresetSlotViolin], @"Graphic EQ presets save and recall through production state validation");
        Check([ten matchesEQPresetInSlot:EQPresetSlotViolin] && ten.hasFlatEQResponse, @"Graphic EQ matches its saved flat preset");
        AUParameter *band = [ten.audioUnit.parameterTree parameterWithID:0 scope:kAudioUnitScope_Global element:0];
        band.value = -4;
        Check(![ten matchesEQPresetInSlot:EQPresetSlotViolin] && !ten.hasFlatEQResponse, @"Graphic band edits clear flat and preset matches");
        [ten loadEQPresetInSlot:EQPresetSlotViolin];
        Check(![thirtyOne hasEQPresetInSlot:EQPresetSlotViolin], @"10-band and 31-band slots stay separate");
        Effect *dynamics = [Effect effectWithEffectType:Type(kAudioUnitSubType_DynamicsProcessor, kAudioUnitManufacturer_Apple)];
        Check(![dynamics supportsEQPresetSlots] && ![dynamics saveEQPresetInSlot:EQPresetSlotViolin], @"Unrelated effects do not expose EQ slots");
        NSString *key = [NSString stringWithFormat:@"EQPresetSlot.%@.1", EmbraceEffectParametricEQ];
        NSData *saved = [defaults dataForKey:key];
        [defaults setObject:@"Corrupt slot" forKey:key];
        Check(![custom hasEQPresetInSlot:EQPresetSlotViolin] && ![custom loadEQPresetInSlot:EQPresetSlotViolin] && fabs(gain.value + 3.5) < .001, @"A malformed stored slot leaves the current EQ unchanged");
        [defaults setObject:saved forKey:key];
        NSString *appleKey = [NSString stringWithFormat:@"EQPresetSlot.%@.2", EmbraceMappedEffect10BandEQ];
        [defaults setObject:[NSPropertyListSerialization dataWithPropertyList:@{@"data":[NSMutableData dataWithLength:2]} format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL] forKey:appleKey];
        NSDictionary *appleBefore = ten.audioUnit.fullState;
        Check(![ten loadEQPresetInSlot:EQPresetSlotSinger] && [ten.audioUnit.fullState isEqual:appleBefore], @"Malformed Apple preset data is rejected before the AU parser");
        Check([defaults synchronize], @"Isolated presets are flushed before the restart check");
        [[NSFileManager defaultManager] removeItemAtURL:preset error:NULL];
        printf("PASS: %lu Audio Unit state assertions\n", (unsigned long)checks);
    }
    return 0;
}
