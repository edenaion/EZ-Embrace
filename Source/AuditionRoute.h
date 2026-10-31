#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

NSArray<NSDictionary<NSString *, id> *> *AuditionOutputDevices(void);
AudioDeviceID AuditionResolveOutput(NSString *uid, AudioDeviceID mainDeviceID, NSError * _Nullable * _Nullable error);
BOOL AuditionOutputsOverlap(AudioDeviceID first, AudioDeviceID second);

NS_ASSUME_NONNULL_END
