// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

extern NSString * const EffectDidDeallocNotification;
extern NSString * const EffectBypassDidChangeNotification;
extern NSString * const EffectEQPresetDidChangeNotification;

@class EffectType;
@class EffectSettingsController;

typedef NS_ENUM(NSInteger, EQPresetSlot) {
    EQPresetSlotViolin = 1,
    EQPresetSlotSinger = 2
};

@interface Effect : NSObject

+ (instancetype) effectWithStateDictionary:(NSDictionary *)dictionary;
- (id) initWithStateDictionary:(NSDictionary *)dictionary;

+ (instancetype) effectWithEffectType:(EffectType *)effectType;
- (id) initWithEffectType:(EffectType *)effectType;

- (void) loadAudioPresetAtFileURL:(NSURL *)fileURL;
- (BOOL) saveAudioPresetAtFileURL:(NSURL *)fileURL;
- (void) restoreDefaultValues;

- (BOOL) supportsEQPresetSlots;
- (BOOL) hasEQPresetInSlot:(EQPresetSlot)slot;
- (BOOL) saveEQPresetInSlot:(EQPresetSlot)slot;
- (BOOL) loadEQPresetInSlot:(EQPresetSlot)slot;
- (BOOL) matchesEQPresetInSlot:(EQPresetSlot)slot;
- (BOOL) hasFlatEQResponse;

- (NSDictionary *) stateDictionary;

@property (nonatomic) AUAudioUnit *audioUnit;
@property (nonatomic) NSError *audioUnitError;

@property (nonatomic, readonly) NSUUID *UUID;
@property (nonatomic, readonly) EffectType *type;
@property (nonatomic, readonly) BOOL hasCustomView;
@property (nonatomic) BOOL bypass;

@end
