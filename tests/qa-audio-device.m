#import <Foundation/Foundation.h>
#import "qa-core-audio.h"

int main(int argc, const char **argv)
{
    @autoreleasepool {
        AudioObjectPropertyAddress address = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size)) return 1;
        NSMutableData *storage = [NSMutableData dataWithLength:size];
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, storage.mutableBytes)) return 1;
        AudioDeviceID *devices = storage.mutableBytes;
        NSString *speakerUID = nil;
        NSString *requestedUID = argc > 1 ? @(argv[1]) : nil;
        for (NSUInteger i = 0; i < size / sizeof(AudioDeviceID); i++) {
            BOOL matches = requestedUID ? [QAStringProperty(devices[i], kAudioDevicePropertyDeviceUID) isEqualToString:requestedUID]
                : [QAStringProperty(devices[i], kAudioObjectPropertyName) isEqualToString:@"MacBook Pro Speakers"];
            if (matches) {
                speakerUID = QAStringProperty(devices[i], kAudioDevicePropertyDeviceUID);
            }
        }
        if (!speakerUID) { fprintf(stderr, "QA reference device missing\n"); return 1; }
        NSString *uid = [NSString stringWithFormat:@"com.ezscape.ezembrace.qa-output.%d", getpid()];
        NSDictionary *composition = @{
            @kAudioAggregateDeviceNameKey: @"EZ-Embrace QA Output",
            @kAudioAggregateDeviceUIDKey: uid,
            @kAudioAggregateDeviceIsPrivateKey: @NO,
            @kAudioAggregateDeviceMasterSubDeviceKey: speakerUID,
            @kAudioAggregateDeviceSubDeviceListKey: @[@{@kAudioSubDeviceUIDKey: speakerUID}]
        };
        AudioDeviceID aggregate = kAudioObjectUnknown;
        char command[128] = "connect";
        int result = 0;
        do {
            if (!strncmp(command, "connect", 7) && !aggregate) {
                OSStatus status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition, &aggregate);
                printf("Created QA output %u, status %d, UID %s\n", aggregate, status, uid.UTF8String);
                if (status) { result = 1; break; }
            } else if (!strncmp(command, "disconnect", 10) && aggregate) {
                OSStatus status = AudioHardwareDestroyAggregateDevice(aggregate);
                printf("Removed QA output %u, status %d\n", aggregate, status);
                if (status) { result = 1; break; }
                aggregate = kAudioObjectUnknown;
            } else if (!strncmp(command, "quit", 4)) {
                break;
            }
            fflush(stdout);
        } while (fgets(command, sizeof(command), stdin));
        if (aggregate) {
            OSStatus status = AudioHardwareDestroyAggregateDevice(aggregate);
            printf("Cleaned QA output %u, status %d\n", aggregate, status);
            if (status) result = 1;
        }
        return result;
    }
}
