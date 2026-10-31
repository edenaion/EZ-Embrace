#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import "qa-core-audio.h"

static void Print(NSDictionary *value)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
    fwrite(data.bytes, 1, data.length, stdout);
    putchar('\n');
    fflush(stdout);
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        if (argc == 2 && !strcmp(argv[1], "list")) {
            AudioObjectPropertyAddress address = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            UInt32 size = 0;
            if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size)) return 1;
            NSMutableData *data = [NSMutableData dataWithLength:size];
            if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, data.mutableBytes)) return 1;
            AudioDeviceID *ids = data.mutableBytes;
            for (NSUInteger i = 0; i < size / sizeof(AudioDeviceID); i++) {
                Print(@{@"id": @(ids[i]), @"uid": QAStringProperty(ids[i], kAudioDevicePropertyDeviceUID) ?: @"", @"name": QAStringProperty(ids[i], kAudioObjectPropertyName) ?: @""});
            }
            return 0;
        }
        if (argc != 3) { fprintf(stderr, "Usage: probe FILE DEVICE_UID (or probe list)\n"); return 64; }
        NSError *error;
        AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@(argv[1])] error:&error];
        if (!player) { Print(@{@"error": error.localizedDescription ?: @"Open failed"}); return 1; }
        player.currentDevice = @(argv[2]);
        player.numberOfLoops = -1;
        player.volume = 1;
        Print(@{@"status": @"ready", @"pid": @(getpid()), @"device": player.currentDevice ?: @"", @"prepared": @([player prepareToPlay])});
        __block BOOL quit = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            char buffer[1024];
            while (fgets(buffer, sizeof(buffer), stdin)) {
                NSString *command = [@(buffer) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([command hasPrefix:@"device "]) { [player stop]; player.currentDevice = [command substringFromIndex:7]; }
                    else if ([command isEqual:@"play"]) { BOOL prepared = [player prepareToPlay]; BOOL played = [player play]; Print(@{@"prepared": @(prepared), @"play_return": @(played)}); }
                    else if ([command isEqual:@"pause"]) [player pause];
                    else if ([command isEqual:@"stop"]) [player stop];
                    else if ([command isEqual:@"quit"]) { [player stop]; quit = YES; }
                    Print(@{@"command": command, @"device": player.currentDevice ?: @"", @"playing": @(player.isPlaying), @"position": @(player.currentTime), @"unix_seconds": @(NSDate.date.timeIntervalSince1970)});
                });
            }
            dispatch_async(dispatch_get_main_queue(), ^{ [player stop]; quit = YES; });
        });
        while (!quit) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    }
    return 0;
}
