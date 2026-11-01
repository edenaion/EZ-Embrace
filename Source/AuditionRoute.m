#import "AuditionRoute.h"

static AudioObjectPropertyAddress Address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope)
{
    return (AudioObjectPropertyAddress){selector, scope, kAudioObjectPropertyElementMain};
}

static NSString *DeviceString(AudioDeviceID device, AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = Address(selector, kAudioObjectPropertyScopeGlobal);
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &value)) return nil;
    return CFBridgingRelease(value);
}

static NSArray<NSNumber *> *DeviceIDs(void)
{
    AudioObjectPropertyAddress address = Address(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size)) return @[];
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, data.mutableBytes)) return @[];
    NSMutableArray *result = [NSMutableArray array];
    const AudioDeviceID *ids = data.bytes;
    for (NSUInteger i = 0; i < size / sizeof(AudioDeviceID); i++) [result addObject:@(ids[i])];
    return result;
}

static AudioDeviceID DeviceForUID(NSString *uid)
{
    if (!uid.length) return kAudioObjectUnknown;
    for (NSNumber *number in DeviceIDs()) {
        if ([DeviceString(number.unsignedIntValue, kAudioDevicePropertyDeviceUID) isEqualToString:uid]) return number.unsignedIntValue;
    }
    return kAudioObjectUnknown;
}

static BOOL IsLiveOutput(AudioDeviceID device)
{
    if (!device) return NO;
    AudioObjectPropertyAddress alive = Address(kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal);
    UInt32 value = 0, size = sizeof(value);
    if (AudioObjectGetPropertyData(device, &alive, 0, NULL, &size, &value) || !value) return NO;
    AudioObjectPropertyAddress streams = Address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput);
    size = 0;
    return AudioObjectGetPropertyDataSize(device, &streams, 0, NULL, &size) == noErr && size >= sizeof(AudioStreamID);
}

static NSSet<NSString *> *EndpointUIDs(AudioDeviceID device, NSMutableSet<NSNumber *> *visited)
{
    if (!device || visited.count >= 32 || [visited containsObject:@(device)]) return nil;
    [visited addObject:@(device)];
    AudioObjectPropertyAddress address = Address(kAudioObjectPropertyClass, kAudioObjectPropertyScopeGlobal);
    AudioClassID classID = 0;
    UInt32 size = sizeof(classID);
    if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &classID)) return nil;
    NSString *uid = DeviceString(device, kAudioDevicePropertyDeviceUID);
    if (!uid.length) return nil;
    if (classID != kAudioAggregateDeviceClassID) return [NSSet setWithObject:uid];
    address.mSelector = kAudioAggregateDevicePropertyFullSubDeviceList;
    CFArrayRef members = NULL;
    size = sizeof(members);
    if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &members)) return nil;
    NSArray *uids = CFBridgingRelease(members);
    if (![uids isKindOfClass:NSArray.class] || !uids.count) return nil;
    NSMutableSet *result = [NSMutableSet set];
    for (id member in uids) {
        if (![member isKindOfClass:NSString.class]) return nil;
        NSSet *endpoints = EndpointUIDs(DeviceForUID(member), [visited mutableCopy]);
        if (!endpoints.count) return nil;
        [result unionSet:endpoints];
    }
    return result;
}

BOOL AuditionOutputsOverlap(AudioDeviceID first, AudioDeviceID second)
{
    if (!first || !second || first == second) return YES;
    NSSet *left = EndpointUIDs(first, [NSMutableSet set]);
    NSSet *right = EndpointUIDs(second, [NSMutableSet set]);
    return !left.count || !right.count || [left intersectsSet:right];
}

NSArray<NSDictionary<NSString *, id> *> *AuditionOutputDevices(void)
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSNumber *number in DeviceIDs()) {
        AudioDeviceID device = number.unsignedIntValue;
        if (!IsLiveOutput(device)) continue;
        NSString *uid = DeviceString(device, kAudioDevicePropertyDeviceUID);
        NSString *name = DeviceString(device, kAudioObjectPropertyName);
        if (uid.length && name.length) [result addObject:@{@"uid":uid, @"name":name, @"deviceID":number}];
    }
    return [result sortedArrayUsingDescriptors:@[
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)],
        [NSSortDescriptor sortDescriptorWithKey:@"uid" ascending:YES]
    ]];
}

AudioDeviceID AuditionResolveOutput(NSString *uid, AudioDeviceID mainDeviceID, NSError **error)
{
    NSString *message = nil;
    AudioDeviceID device = DeviceForUID(uid);
    if (!uid.length) message = @"Choose an Audition Output in Settings > General.";
    else if (!IsLiveOutput(device)) message = @"The selected audition output is unavailable. Reconnect it, then press Preview.";
    else if (!IsLiveOutput(mainDeviceID)) message = @"Configure an available Main Output before using headphone preview.";
    else if (AuditionOutputsOverlap(device, mainDeviceID)) message = @"Audition Output must be separate from Main Output, including aggregate subdevices.";
    if (!message) {
        AudioObjectPropertyAddress address = Address(kAudioDevicePropertyHogMode, kAudioObjectPropertyScopeGlobal);
        pid_t owner = -1;
        UInt32 size = sizeof(owner);
        if (!AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &owner) && owner != -1 && owner != getpid()) {
            message = @"Another application has exclusive access to the audition output.";
        }
    }
    if (message) {
        if (error) *error = [NSError errorWithDomain:@"EZEmbrace.AuditionRoute" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
        return kAudioObjectUnknown;
    }
    return device;
}
