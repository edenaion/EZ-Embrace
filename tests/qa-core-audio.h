#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

static inline NSString *QAStringProperty(AudioObjectID object, AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = {selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value)) return nil;
    return CFBridgingRelease(value);
}
