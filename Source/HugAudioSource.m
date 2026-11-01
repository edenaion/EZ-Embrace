// (c) 2018-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "HugAudioSource.h"

#import "HugAudioFile.h"
#import "HugProtectedBuffer.h"
#import "HugError.h"
#import "HugUtils.h"
#import "HugAudioSettings.h"
#import "HugDebugFile.h"

#include <stdatomic.h>

#define DEBUG_AUDIO_SOURCE_BUFFERS 0

typedef struct {
    NSInteger frameIndex;
    NSInteger totalFrames;
    NSInteger initialFrame;
    double sampleRate;
    atomic_uint_fast64_t seekRequest;
    atomic_uint availableFrames;
    atomic_bool decodingComplete;
    UInt32 seekGeneration;
    BOOL fadedOutForSeek;
    AudioBufferList *bufferList;

    AudioBufferList *inputScratch;
    UInt32           inputScratchFrameSize;

    AudioBufferList *converterScratch;
    UInt32           converterScratchFrameSize;
} RenderContext;


static void sFillBufferList(RenderContext *context, UInt32 rawFrameCount, AudioBufferList *ioData)
{
    NSInteger frameCount = rawFrameCount;
    NSInteger offset = 0;

    UInt32 bufferCount = ioData->mNumberBuffers;

    // Zero pad if needed
    if (context->frameIndex < 0) {
        NSInteger padCount     = -context->frameIndex;
        NSInteger framesToCopy = MIN(frameCount, padCount);
    
        for (NSInteger b = 0; b < bufferCount; b++) {
            memset(ioData->mBuffers[b].mData, 0, sizeof(float) * framesToCopy);
        }

        offset = framesToCopy;
        context->frameIndex += framesToCopy;
        if (context->frameIndex < 0) return;
        context->frameIndex = context->initialFrame;
    }

    // Copy track data
    {
        NSUInteger framesToCopy = MIN(frameCount - offset, context->totalFrames - context->frameIndex);
        NSInteger framesRemaining = (frameCount - offset) - framesToCopy;

        for (NSInteger b = 0; b < bufferCount; b++) {
            float *inSamples  = (float *)context->bufferList->mBuffers[b].mData;
            float *outSamples = (float *)ioData->mBuffers[b].mData;
            
            inSamples  += context->frameIndex;
            outSamples += offset;

            memcpy(outSamples, inSamples, sizeof(float) * framesToCopy);
            
            if (framesRemaining > 0) {
                memset(&outSamples[framesToCopy], 0, sizeof(float) * framesRemaining);
            }
        }

        context->frameIndex += framesToCopy;
    }
}


static OSStatus sConverterInputCallback(
    AudioConverterRef inAudioConverter,
    UInt32 *ioNumberDataPackets,
    AudioBufferList *ioData,
    AudioStreamPacketDescription **unused,
    void *inUserData
) {
    RenderContext *context = (RenderContext *)inUserData;

    UInt32 frameSize = *ioNumberDataPackets;
    if (frameSize > context->converterScratchFrameSize) {
        frameSize = context->converterScratchFrameSize;
    }

    AudioBufferList *scratch = context->converterScratch;

    sFillBufferList(context, frameSize, scratch);

    for (NSInteger i = 0; i < scratch->mNumberBuffers; i++) {
        ioData->mBuffers[i].mDataByteSize = frameSize * sizeof(float);
        ioData->mBuffers[i].mData = scratch->mBuffers[i].mData;
    }

    *ioNumberDataPackets = frameSize;

    return noErr;
}


@implementation HugAudioSource {
    HugAudioFile *_audioFile;
    AudioConverterRef _converter;
    RenderContext *_context;
    NSArray<HugProtectedBuffer *> *_protectedBuffers;
    
    HugAudioSourceCompletionHandler _completionHandler;
}


- (instancetype) initWithAudioFile:(HugAudioFile *)audioFile settings:(NSDictionary *)settings
{
    if ((self = [super init])) {
        _audioFile = audioFile;
        _settings = settings;
    }
    
    return self;
}


- (void) dealloc
{
    if (_converter) {
        AudioConverterDispose(_converter);
        _converter = NULL;
    }

    [_audioFile close];

    if (_context) {
        HugAudioBufferListFree(_context->bufferList, NO);
        _context->bufferList = NULL;

        HugAudioBufferListFree(_context->converterScratch, YES);
        _context->converterScratch = NULL;

        HugAudioBufferListFree(_context->inputScratch, YES);
        _context->inputScratch = NULL;
        
        free(_context);
    }
}


#pragma mark - Private Methods


- (BOOL) _makeContextWithStartTime: (NSTimeInterval) startTime
                          stopTime: (NSTimeInterval) stopTime
                           padding: (NSTimeInterval) padding
{
    if (![_audioFile open]) {
        NSError *error = [_audioFile error];
        HugLog(@"HugAudioSource", @"Could not open %@. Error %@", _audioFile, error);
        _error = [_audioFile error];
        
        return NO;
    }

    SInt64 fileFrames = [_audioFile fileLengthFrames];
    AudioStreamBasicDescription format = [_audioFile format];

    NSInteger totalFrames = fileFrames;

    // Apply startTime/stopTime
    {
        NSInteger startFrame  = startTime * format.mSampleRate;
        NSInteger stopFrame   = 0;

        if (startFrame < 0) startFrame = 0;
        if (startFrame > totalFrames) startFrame = totalFrames;

        if (stopTime) {
            stopFrame  = stopTime * format.mSampleRate;
            if (stopFrame < 0) stopFrame = 0;
            if (stopFrame > totalFrames) stopFrame = totalFrames;

            totalFrames = (stopFrame - startFrame);
        } else {
            totalFrames -= startFrame;
        }

        HugLog(@"HugAudioSource", @"%@ fileFrames: %ld, totalFrames: %ld, startFrame: %ld, stopFrame: %ld", _audioFile, (long)fileFrames, (long)totalFrames, (long)startFrame, (long)stopFrame);

        if (startFrame) {
            if (![_audioFile seekToFrame:startFrame]) {
                HugLog(@"HugAudioSource", @"seekToFrame %ld failed for %@", (long)startFrame, _audioFile);
                _error = [_audioFile error];
                return NO;
            }
        }
        
        if ((totalFrames < 0) || (totalFrames > UINT32_MAX)) {
            _error = [NSError errorWithDomain:HugErrorDomain code:HugErrorInvalidFrameCount userInfo:nil];
            return NO;
        }
    }

    // Setup _context and _protectedBuffers
    {
        UInt32 channelCount = format.mChannelsPerFrame;
        UInt32 totalBytes   = (UInt32)totalFrames * format.mBytesPerFrame;

        AudioBufferList *list = HugAudioBufferListCreate(channelCount, 0, NO);
        
        NSMutableArray *protectedBuffers = [NSMutableArray array];

        for (NSInteger i = 0; i < channelCount; i++) {
            HugProtectedBuffer *protectedBuffer = [[HugProtectedBuffer alloc] initWithCapacity:totalBytes];
        
            list->mBuffers[i].mNumberChannels = 1;
            list->mBuffers[i].mDataByteSize = (UInt32)totalBytes;
            list->mBuffers[i].mData = (void *)[protectedBuffer bytes];

            [protectedBuffers addObject:protectedBuffer];
        }

        UInt32 outputFrameSize = [[_settings objectForKey:HugAudioSettingFrameSize] unsignedIntValue];
        AudioBufferList *inputScratch = HugAudioBufferListCreate(channelCount, outputFrameSize, YES);

        _context = calloc(1, sizeof(RenderContext));
        atomic_init(&_context->seekRequest, 0);
        atomic_init(&_context->availableFrames, 0);
        atomic_init(&_context->decodingComplete, false);
        _context->sampleRate   = format.mSampleRate;
        _context->frameIndex   = format.mSampleRate * -padding;
        _context->totalFrames  = (UInt32)totalFrames;
        _context->bufferList   = list;
        _context->inputScratch = inputScratch;

        _protectedBuffers = protectedBuffers;
    }

    return YES;
}


- (void) _finishFillBufferWithError:(NSError *)readError
{
    if (!_error) {
        _error = readError ?: [_audioFile error];
    }
    
    if (!_error) {
        for (HugProtectedBuffer *protectedBuffer in _protectedBuffers) {
            [protectedBuffer lock];
        }
    }

#if DEBUG_AUDIO_SOURCE_BUFFERS
    [HugDebugFile writeWithSampleRate: _context->sampleRate
                          totalFrames: _context->totalFrames
                           bufferList: _context->bufferList];
#endif

    if (_completionHandler) {
        _completionHandler(self);
    }
}


- (BOOL) _fillBuffer
{
    RenderContext *context = _context;

    AudioStreamBasicDescription format = [_audioFile format];

    NSInteger bytesPerFrame = format.mBytesPerFrame;
    NSInteger totalFrames   = _context->totalFrames;
    NSInteger primeAmount   = context->initialFrame + (format.mSampleRate * 10);
    if (totalFrames < primeAmount) primeAmount = totalFrames;

    dispatch_semaphore_t primeSemaphore = dispatch_semaphore_create(0);

    __block atomic_bool shouldCancel;
    __block atomic_bool readFailed;
    atomic_init(&shouldCancel, false);
    atomic_init(&readFailed, false);
    __weak id weakSelf = self;

    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSInteger framesRemaining = totalFrames;
        NSInteger bytesRemaining = framesRemaining * bytesPerFrame;

        NSInteger bytesRead = 0;
        NSInteger framesAvailable = 0;

        UInt32 bufferCount = context->bufferList->mNumberBuffers;
        
        AudioBufferList *fillBufferList = HugAudioBufferListCreate(bufferCount, 0, NO);
        
        BOOL ok = YES;
        BOOL needsSignal = YES;
        NSError *readError = nil;
        
        while (ok) {
            if (atomic_load_explicit(&shouldCancel, memory_order_acquire)) break;
        
            UInt32 maxFrames  = 32768;
            UInt32 frameCount = (UInt32)framesRemaining;
            if (frameCount > maxFrames) frameCount = maxFrames;

            for (NSInteger i = 0; i < bufferCount; i++) {
                fillBufferList->mBuffers[i].mNumberChannels = 1;
                fillBufferList->mBuffers[i].mDataByteSize = (UInt32)bytesRemaining;
                
                UInt8 *data = (UInt8 *)context->bufferList->mBuffers[i].mData;
                data += bytesRead;
                fillBufferList->mBuffers[i].mData = data;
            }

            if (frameCount > 0) {
                ok = [_audioFile readFrames:&frameCount intoBufferList:fillBufferList];
                if (!ok) {
                    readError = [_audioFile error] ?: [NSError errorWithDomain:HugErrorDomain code:HugErrorReadFailed userInfo:nil];
                    atomic_store_explicit(&readFailed, true, memory_order_release);
                    break;
                }
            }

            // ExtAudioFileRead() is documented to return 0 when the end of the file is reached.
            //
            if ((frameCount == 0) || (framesRemaining == 0)) {
                break;
            }
       
            framesAvailable += frameCount;
            atomic_store_explicit(&context->availableFrames, (UInt32)framesAvailable, memory_order_release);
            
            if ((framesAvailable >= primeAmount) && needsSignal) {
                dispatch_semaphore_signal(primeSemaphore);
                needsSignal = NO;
            }

            framesRemaining -= frameCount;
        
            bytesRead       += frameCount * bytesPerFrame;
            bytesRemaining  -= frameCount * bytesPerFrame;
        }

        atomic_store_explicit(&context->decodingComplete, true, memory_order_release);
        if (needsSignal) {
            dispatch_semaphore_signal(primeSemaphore);
        }
        
        HugAudioBufferListFree(fillBufferList, NO);

        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            
            HugLog(@"HugAudioSource", @"Read finished in %ldms", (long)((now - startTime) * 1000));
        
            [weakSelf _finishFillBufferWithError:readError];
        });
    });

    // Wait for the prime semaphore, this should be very fast.  If we can't decode at least 10 seconds
    // of audio in 5 seconds, something is wrong, and flip the error to "read too slow"
    //
    int64_t fiveSecondsInNs = 5l * 1000 * 1000 * 1000;
    if (dispatch_semaphore_wait(primeSemaphore, dispatch_time(0, fiveSecondsInNs))) {
        HugLog(@"HugAudioSource", @"dispatch_semaphore_wait() timed out for %@", _audioFile);
        _error = [NSError errorWithDomain:HugErrorDomain code:HugErrorReadTooSlow userInfo:nil];
        atomic_store_explicit(&shouldCancel, true, memory_order_release);

        return NO;

    } else {
        if (atomic_load_explicit(&readFailed, memory_order_acquire)) {
            _error = [_audioFile error] ?: [NSError errorWithDomain:HugErrorDomain code:HugErrorReadFailed userInfo:nil];
            return NO;
        }
        HugLog(@"HugAudioSource", @"%@ primed!", _audioFile);
        
        return YES;
    }
}


- (BOOL) _makeConverter
{
    AudioStreamBasicDescription inputFormat = [_audioFile format];

    double outputSampleRate = [[_settings objectForKey:HugAudioSettingSampleRate] doubleValue];
    UInt32 frameSize        = [[_settings objectForKey:HugAudioSettingFrameSize] unsignedIntValue];

    UInt32 frameSizeSize = sizeof(frameSize);

    if (inputFormat.mSampleRate == outputSampleRate) return YES;

    UInt32 channelCount = inputFormat.mChannelsPerFrame;

    AudioStreamBasicDescription outputFormat = inputFormat;
    outputFormat.mSampleRate = outputSampleRate;
    
    UInt32 quality    = kAudioConverterQuality_Max;
    UInt32 complexity = kAudioConverterSampleRateConverterComplexity_Normal;
    
    BOOL ok = YES;

    ok = ok && HugCheckError(
        AudioConverterNew(&inputFormat, &outputFormat, &_converter),
        @"HugAudioSource", @"AudioConverterNew"
    );
    
    ok = ok && HugCheckError(
        AudioConverterSetProperty(_converter, kAudioConverterSampleRateConverterQuality, sizeof(quality), &quality),
        @"HugAudioSource", @"AudioConverterSetProperty[ Quality ]"
    );

    ok = ok && HugCheckError(
        AudioConverterSetProperty(_converter, kAudioConverterSampleRateConverterComplexity, sizeof(complexity), &complexity),
        @"HugAudioSource", @"AudioConverterSetProperty[ Complexity ]"
    );

    ok = ok && HugCheckError(
        AudioConverterGetProperty(_converter, kAudioConverterPropertyCalculateInputBufferSize, &frameSizeSize, &frameSize),
        @"HugAudioSource", @"AudioConverterSetProperty[ CalculateInputBufferSize ]"
    );
    
    _context->converterScratch = HugAudioBufferListCreate(channelCount, frameSize, YES);
    _context->converterScratchFrameSize = frameSize;

    return ok;
}


#pragma mark - Public Methods

- (BOOL) prepareWithStartTime: (NSTimeInterval) startTime
                     stopTime: (NSTimeInterval) stopTime
                      padding: (NSTimeInterval) padding
            completionHandler: (void (^)(HugAudioSource *)) completionHandler
{
    return [self prepareWithStartTime:startTime stopTime:stopTime padding:padding initialTime:0 completionHandler:completionHandler];
}

- (BOOL) prepareWithStartTime:(NSTimeInterval)startTime
                    stopTime:(NSTimeInterval)stopTime
                     padding:(NSTimeInterval)padding
                 initialTime:(NSTimeInterval)initialTime
           completionHandler:(HugAudioSourceCompletionHandler)completionHandler
{
    if (!isfinite(initialTime) || initialTime < 0) return NO;
    if (![self _makeContextWithStartTime:startTime stopTime:stopTime padding:padding]) {
        return NO;
    }
    _context->initialFrame = (NSInteger)MIN(initialTime * _context->sampleRate, MAX(0, _context->totalFrames - 1));
    if (_context->frameIndex == 0) _context->frameIndex = _context->initialFrame;
    
    if (![self _fillBuffer]) {
        return NO;
    }
    
    if (![self _makeConverter]) {
        return NO;
    }

    RenderContext    *context   = _context;
    AudioConverterRef converter = _converter;

    _inputBlock = [^(
        AUAudioFrameCount frameCount,
        AudioBufferList *ioData,
        HugPlaybackInfo *outInfo
    ) {
        OSStatus result = noErr;

        UInt32 sourceChannelCount = context->bufferList->mNumberBuffers;
        UInt32 outputChannelCount = ioData->mNumberBuffers;

        uint64_t request = atomic_load_explicit(&context->seekRequest, memory_order_acquire);
        UInt32 generation = (UInt32)(request >> 32);
        UInt32 targetFrame = (UInt32)request;
        UInt32 available = atomic_load_explicit(&context->availableFrames, memory_order_acquire);
        // Wait for decoding to reach the target. The render thread never waits on the decoder.
        NSUInteger needed = MIN((NSUInteger)context->totalFrames,
            (NSUInteger)targetFrame + MAX(context->converterScratchFrameSize, frameCount) * 2);
        BOOL canSeek = generation != context->seekGeneration &&
            (available >= needed || atomic_load_explicit(&context->decodingComplete, memory_order_acquire));
        BOOL fadeOut = canSeek && !context->fadedOutForSeek;
        BOOL fadeIn = canSeek && context->fadedOutForSeek;
        if (fadeIn) {
            context->frameIndex = targetFrame;
            context->seekGeneration = generation;
            if (converter) AudioConverterReset(converter);
        }

        AudioBufferList *bufferToFill = (sourceChannelCount == outputChannelCount) ? ioData : context->inputScratch;

        if (!converter) {
            sFillBufferList(context, frameCount, bufferToFill);
        } else {
            result = AudioConverterFillComplexBuffer(converter, sConverterInputCallback, context, &frameCount, bufferToFill, NULL);
        }
        
        if (sourceChannelCount != outputChannelCount) {
            for (NSInteger o = 0; o < outputChannelCount; o++) {
                NSInteger s = o % sourceChannelCount;
                memcpy(ioData->mBuffers[o].mData, bufferToFill->mBuffers[s].mData, frameCount * sizeof(float));
            }
        }

        // Fade across two render buffers to remove the discontinuity at a seek.
        // All work uses existing buffers and performs no render-thread allocation.
        if (fadeOut || fadeIn) {
            for (UInt32 b = 0; b < outputChannelCount; b++) {
                float *samples = ioData->mBuffers[b].mData;
                for (UInt32 f = 0; f < frameCount; f++) {
                    float ramp = frameCount > 1 ? (float)f / (frameCount - 1) : 1;
                    samples[f] *= fadeIn ? ramp : 1 - ramp;
                }
            }
        }
        context->fadedOutForSeek = fadeOut;

        if (outInfo) {
            outInfo->seekGeneration = context->seekGeneration;
            double sampleRate = context->sampleRate;

            if (context->frameIndex < 0) {
                outInfo->status = HugPlaybackStatusWaiting;
                outInfo->timeElapsed   = context->frameIndex  / sampleRate;
                outInfo->timeRemaining = (context->totalFrames - context->initialFrame) / sampleRate;

            } else if (context->frameIndex >= context->totalFrames) {
                outInfo->status = HugPlaybackStatusFinished;
                outInfo->timeElapsed   = context->totalFrames / sampleRate;
                outInfo->timeRemaining = 0;

            } else {
                outInfo->status = HugPlaybackStatusPlaying;
                outInfo->timeElapsed   =  context->frameIndex / sampleRate;
                outInfo->timeRemaining = (context->totalFrames - context->frameIndex) / sampleRate;
            }
        }

        return result;

    } copy];
    
    _completionHandler = completionHandler;

    return YES;
}


- (UInt32) seekToTime:(NSTimeInterval)time
{
    if (!_context || !_inputBlock || _error || !isfinite(time) || _context->totalFrames <= 0) return 0;

    UInt32 frame = (UInt32)MIN(MAX(0, time * _context->sampleRate), _context->totalFrames - 1);
    uint64_t previous = atomic_load_explicit(&_context->seekRequest, memory_order_relaxed);
    UInt32 generation = (UInt32)(previous >> 32) + 1;
    if (!generation) generation = 1;
    atomic_store_explicit(&_context->seekRequest, ((uint64_t)generation << 32) | frame, memory_order_release);
    return generation;
}


- (NSTimeInterval) duration
{
    return _context && _context->sampleRate > 0 ? _context->totalFrames / _context->sampleRate : 0;
}


@end
