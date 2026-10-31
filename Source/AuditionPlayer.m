#import "AuditionPlayer.h"
#import "AuditionRoute.h"
#import "Preferences.h"
#import "HugAudioDevice.h"
#import "Player.h"
#import <AVFoundation/AVFoundation.h>
#include <stdatomic.h>

NSString * const AuditionPlayerDidChangeNotification = @"AuditionPlayerDidChange";
static AuditionPlayer *sSharedPlayer;
static const void *sQueueKey = &sQueueKey;
static const AudioObjectPropertySelector sSystemProperties[] = {
    kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
    kAudioHardwarePropertyDefaultSystemOutputDevice
};
static const AudioObjectPropertySelector sDeviceProperties[] = {
    kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyDeviceHasChanged, kAudioDevicePropertyHogMode
};

@interface AuditionPlayer () <AVAudioPlayerDelegate>
@end

@implementation AuditionPlayer {
    Preferences *_preferences;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    AudioObjectPropertyListenerBlock _routeListener;
    AVAudioPlayer *_player;
    AudioDeviceID _activeDeviceID;
    NSString *_activeUID;
    NSString *_preferenceUID;
    NSDictionary *_metadata;
    AuditionState _workerState;
    NSUInteger _workerGeneration;
    NSTimeInterval _workerPosition;
    NSTimeInterval _workerDuration;
    NSTimeInterval _notPlayingSince;
    NSTimeInterval _lastRouteCheck;
    atomic_uint_fast64_t _generation;
    atomic_uint _mainDeviceID;
    atomic_bool _shuttingDown;
}

+ (instancetype) sharedInstance
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sSharedPlayer = [[self alloc] initWithPreferences:[Preferences sharedInstance]]; });
    return sSharedPlayer;
}

+ (void) shutdownIfLoaded { [sSharedPlayer _shutdown]; }

- (instancetype) initWithPreferences:(Preferences *)preferences
{
    if ((self = [super init])) {
        _preferences = preferences;
        _preferenceUID = [preferences.auditionOutputDeviceUID copy] ?: @"";
        _message = @"Preview stopped";
        _title = @"";
        _artist = @"";
        _queue = dispatch_queue_create("EZ-Embrace.audition", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_queue, sQueueKey, (__bridge void *)self, NULL);
        atomic_init(&_generation, 0);
        atomic_init(&_mainDeviceID, preferences.mainOutputAudioDevice.objectID);
        atomic_init(&_shuttingDown, false);
        __weak AuditionPlayer *weakSelf = self;
        _routeListener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
            AuditionPlayer *owner = weakSelf;
            if (!owner) return;
            // Return from Core Audio's listener before teardown removes that listener.
            dispatch_async(owner->_queue, ^{ [weakSelf _checkActiveRoute]; });
        };
        for (NSUInteger i = 0; i < sizeof(sSystemProperties) / sizeof(*sSystemProperties); i++) {
            AudioObjectPropertyAddress address = {sSystemProperties[i], kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &address, _queue, _routeListener);
        }
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), 100 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(_timer, ^{ [weakSelf _tick]; });
        dispatch_resume(_timer);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_preferencesChanged:)
            name:AuditionPreferencesDidChangeNotification object:preferences];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_mainWillConfigure:)
            name:PlayerWillConfigureOutputNotification object:nil];
    }
    return self;
}

- (void) dealloc { [self _shutdown]; }

- (void) _shutdown
{
    if (atomic_exchange(&_shuttingDown, true)) return;
    atomic_fetch_add(&_generation, 1);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_timer) dispatch_source_cancel(_timer);
    for (NSUInteger i = 0; i < sizeof(sSystemProperties) / sizeof(*sSystemProperties); i++) {
        AudioObjectPropertyAddress address = {sSystemProperties[i], kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &address, _queue, _routeListener);
    }
    if (dispatch_get_specific(sQueueKey) == (__bridge void *)self) [self _stopHardware];
    else dispatch_sync(_queue, ^{ [self _stopHardware]; });
}

- (void) _stopHardware
{
    if (_activeDeviceID) {
        for (NSUInteger i = 0; i < sizeof(sDeviceProperties) / sizeof(*sDeviceProperties); i++) {
            AudioObjectPropertyAddress address = {sDeviceProperties[i], kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            AudioObjectRemovePropertyListenerBlock(_activeDeviceID, &address, _queue, _routeListener);
        }
    }
    _player.delegate = nil;
    [_player stop];
    _player = nil;
    _activeDeviceID = 0;
    _activeUID = nil;
    _notPlayingSince = 0;
}

- (void) _publish:(AuditionState)state message:(NSString *)message
{
    _workerState = state;
    NSUInteger generation = _workerGeneration;
    NSDictionary *metadata = _metadata;
    NSTimeInterval position = _workerPosition, duration = _workerDuration;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (atomic_load(&self->_generation) != generation || atomic_load(&self->_shuttingDown)) return;
        self->_state = state;
        self->_message = message ?: @"";
        self->_title = metadata[@"title"] ?: @"";
        self->_artist = metadata[@"artist"] ?: @"";
        self->_fileURL = metadata[@"url"];
        self->_position = position;
        self->_duration = duration;
        [[NSNotificationCenter defaultCenter] postNotificationName:AuditionPlayerDidChangeNotification object:self];
    });
}

- (void) _fail:(NSString *)message
{
    EmbraceLog(@"Audition", @"Stopped: %@", message);
    [self _stopHardware];
    _workerPosition = 0;
    [self _publish:AuditionStateError message:message];
}

- (AVAudioPlayer *) _makePlayerForURL:(NSURL *)url error:(NSError **)error
{
    return [[AVAudioPlayer alloc] initWithContentsOfURL:url error:error];
}

- (NSUUID *) previewURL:(NSURL *)url title:(NSString *)title artist:(NSString *)artist
{
    return [self previewURL:url title:title artist:artist startTime:0 endTime:0];
}

- (NSUUID *) previewURL:(NSURL *)url title:(NSString *)title artist:(NSString *)artist
              startTime:(NSTimeInterval)startTime endTime:(NSTimeInterval)endTime
{
    if (atomic_load(&_shuttingDown)) return nil;
    if (!isfinite(startTime) || startTime < 0) startTime = 0;
    if (!isfinite(endTime) || endTime <= startTime) endTime = 0;
    NSUUID *requestIdentifier = [NSUUID UUID];
    NSUInteger generation = atomic_fetch_add(&_generation, 1) + 1;
    atomic_store(&_mainDeviceID, _preferences.mainOutputAudioDevice.objectID);
    NSString *uid = [_preferences.auditionOutputDeviceUID copy] ?: @"";
    float volume = MIN(100, MAX(0, _preferences.auditionVolumePercent)) / 100.0f;
    _requestIdentifier = requestIdentifier;
    _state = AuditionStatePreparing;
    _message = @"Preparing headphone preview";
    [[NSNotificationCenter defaultCenter] postNotificationName:AuditionPlayerDidChangeNotification object:self];
    dispatch_async(_queue, ^{
        [self _stopHardware];
        self->_workerGeneration = generation;
        self->_workerPosition = self->_workerDuration = 0;
        self->_metadata = @{@"url":url ?: [NSURL fileURLWithPath:@"/"], @"title":title ?: url.lastPathComponent ?: @"", @"artist":artist ?: @""};
        if (atomic_load(&self->_generation) != generation) return;
        NSError *error;
        AudioDeviceID device = AuditionResolveOutput(uid, atomic_load(&self->_mainDeviceID), &error);
        if (!device) { [self _fail:error.localizedDescription]; return; }
        if (!url.isFileURL || ![[NSFileManager defaultManager] isReadableFileAtPath:url.path]) {
            [self _fail:@"This local audio file is unavailable or cannot be read."]; return;
        }
        AVAudioPlayer *player = [self _makePlayerForURL:url error:&error];
        if (!player) { [self _fail:error.localizedDescription ?: @"This audio file cannot be decoded for preview."]; return; }
        if (atomic_load(&self->_generation) != generation) { [player stop]; return; }
        player.currentDevice = uid;
        player.volume = volume;
        player.delegate = self;
        BOOL prepared = [player prepareToPlay];
        if (atomic_load(&self->_generation) != generation) { player.delegate = nil; [player stop]; return; }
        if (!prepared || ![player.currentDevice isEqualToString:uid] ||
            AuditionResolveOutput(uid, atomic_load(&self->_mainDeviceID), &error) != device) {
            player.delegate = nil; [player stop];
            [self _fail:error.localizedDescription ?: @"Could not prepare the selected audition output."]; return;
        }
        self->_player = player;
        self->_activeUID = uid;
        self->_activeDeviceID = device;
        self->_workerDuration = endTime > 0 ? MIN(player.duration, endTime) : player.duration;
        player.currentTime = MIN(MAX(0, self->_workerDuration - .01), startTime);
        self->_workerPosition = player.currentTime;
        if (![player play]) { [self _fail:@"Could not start the selected audition output."]; return; }
        if (atomic_load(&self->_generation) != generation) { [self _stopHardware]; return; }
        for (NSUInteger i = 0; i < sizeof(sDeviceProperties) / sizeof(*sDeviceProperties); i++) {
            AudioObjectPropertyAddress address = {sDeviceProperties[i], kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            AudioObjectAddPropertyListenerBlock(device, &address, self->_queue, self->_routeListener);
        }
        EmbraceLog(@"Audition", @"Start %@ at %.3f on %@ (%u)", title, self->_workerPosition, uid, (unsigned)device);
        [self _publish:AuditionStatePlaying message:@"Headphone preview playing"];
    });
    return requestIdentifier;
}

- (void) stopPreviewWithIdentifier:(NSUUID *)identifier
{
    if (identifier && [_requestIdentifier isEqual:identifier]) [self stop];
}

- (void) pause
{
    dispatch_async(_queue, ^{
        if (self->_workerState != AuditionStatePlaying || !self->_player) return;
        [self->_player pause];
        self->_workerPosition = self->_player.currentTime;
        EmbraceLog(@"Audition", @"Pause at %.3f", self->_workerPosition);
        [self _publish:AuditionStatePaused message:@"Headphone preview paused"];
    });
}

- (void) resume
{
    atomic_store(&_mainDeviceID, _preferences.mainOutputAudioDevice.objectID);
    dispatch_async(_queue, ^{
        if (self->_workerState != AuditionStatePaused || !self->_player) return;
        [self _checkActiveRoute];
        if (!self->_player) return;
        if (![self->_player play]) { [self _fail:@"Could not resume the selected audition output."]; return; }
        EmbraceLog(@"Audition", @"Resume at %.3f", self->_workerPosition);
        [self _publish:AuditionStatePlaying message:@"Headphone preview playing"];
    });
}

- (void) stop
{
    NSUInteger generation = atomic_fetch_add(&_generation, 1) + 1;
    dispatch_async(_queue, ^{
        [self _stopHardware];
        self->_workerGeneration = generation;
        self->_workerPosition = 0;
        EmbraceLog(@"Audition", @"Stop");
        [self _publish:AuditionStateStopped message:@"Preview stopped"];
    });
}

- (void) seekToTime:(NSTimeInterval)time
{
    if (!isfinite(time)) return;
    dispatch_async(_queue, ^{
        if (!self->_player || (self->_workerState != AuditionStatePlaying && self->_workerState != AuditionStatePaused)) return;
        [self _checkActiveRoute];
        if (!self->_player) return;
        // AVAudioPlayer restarts at zero when resumed at exact EOF. Keep the final seek inside the file.
        self->_player.currentTime = MIN(MAX(0, self->_workerDuration - .01), MAX(0, time));
        self->_workerPosition = self->_player.currentTime;
        self->_notPlayingSince = 0;
        EmbraceLog(@"Audition", @"Seek to %.3f", self->_workerPosition);
        [self _publish:self->_workerState message:self->_workerState == AuditionStatePaused ? @"Headphone preview paused" : @"Headphone preview playing"];
    });
}

- (void) _preferencesChanged:(NSNotification *)note
{
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self _preferencesChanged:note]; }); return; }
    NSString *uid = _preferences.auditionOutputDeviceUID ?: @"";
    if (![_preferenceUID isEqualToString:uid]) { _preferenceUID = [uid copy]; [self stop]; }
    float volume = MIN(100, MAX(0, _preferences.auditionVolumePercent)) / 100.0f;
    dispatch_async(_queue, ^{ self->_player.volume = volume; });
}

- (void) _mainWillConfigure:(NSNotification *)note
{
    atomic_store(&_mainDeviceID, [note.userInfo[@"deviceID"] unsignedIntValue]);
    if (_state == AuditionStateStopped || _state == AuditionStateError) return;
    dispatch_sync(_queue, ^{
        // Starting main playback also configures its hardware. A proven separate route can keep playing.
        if (self->_player && AuditionResolveOutput(self->_activeUID, atomic_load(&self->_mainDeviceID), NULL) == self->_activeDeviceID) return;
        NSUInteger generation = atomic_fetch_add(&self->_generation, 1) + 1;
        [self _stopHardware];
        self->_workerGeneration = generation;
        self->_workerPosition = 0;
        EmbraceLog(@"Audition", @"Stop before conflicting main output reconfiguration");
        [self _publish:AuditionStateStopped message:@"Main Output changed or shares the preview device. Press Preview to resume."];
    });
}

- (void) _checkActiveRoute
{
    if (!_player || !_activeUID.length) return;
    NSError *error;
    AudioDeviceID device = AuditionResolveOutput(_activeUID, atomic_load(&_mainDeviceID), &error);
    if (device != _activeDeviceID || ![_player.currentDevice isEqualToString:_activeUID]) {
        [self _fail:error.localizedDescription ?: @"Audition output changed. Press Preview to restart safely."];
    }
}

- (void) _finish
{
    [self _stopHardware];
    _workerPosition = _workerDuration;
    EmbraceLog(@"Audition", @"Finished %@", _metadata[@"title"]);
    [self _publish:AuditionStateStopped message:@"Preview finished"];
}

- (void) _tick
{
    if (!_player || atomic_load(&_generation) != _workerGeneration) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - _lastRouteCheck >= .5) { _lastRouteCheck = now; [self _checkActiveRoute]; }
    if (!_player) return;
    if (_workerState == AuditionStatePlaying && !_player.isPlaying) {
        if (!_notPlayingSince) _notPlayingSince = now;
        if (now - _notPlayingSince > .4) {
            if (_workerPosition >= _workerDuration - .5) [self _finish];
            else [self _fail:@"Preview playback stopped unexpectedly. Press Preview to retry."];
        }
        return;
    }
    _notPlayingSince = 0;
    _workerPosition = _player.currentTime;
    if (_workerState == AuditionStatePlaying && _workerPosition >= _workerDuration - .005) {
        [self _finish];
        return;
    }
    [self _publish:_workerState message:_workerState == AuditionStatePaused ? @"Headphone preview paused" : @"Headphone preview playing"];
}

- (void) audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    dispatch_async(_queue, ^{
        if (player != self->_player || atomic_load(&self->_generation) != self->_workerGeneration) return;
        [self _checkActiveRoute];
        if (!self->_player) return;
        if (flag) [self _finish];
        else [self _fail:@"The audio file could not finish playing."];
    });
}

- (void) audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
    dispatch_async(_queue, ^{
        if (player == self->_player) [self _fail:error.localizedDescription ?: @"Preview decoding failed."];
    });
}
@end
