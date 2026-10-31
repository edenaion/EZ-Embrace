// (c) 2026 EmbraceNG contributors
// MIT License (or) 1-clause BSD License
//
// Parameter construction and render-buffer checks for the in-process EQ.

#ifndef EMBRACE_AUDIO_UNIT_UTILS_H
#define EMBRACE_AUDIO_UNIT_UTILS_H

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>


// Embrace's graph always hands us real buffers.  A host that does not is asking
// the unit to supply its own, which we do not, so say so rather than carrying a
// scratch buffer whose lifetime the render thread would have to reason about.
//
static inline AUAudioUnitStatus EmbraceAUPrepareBufferList(
    AudioBufferList *bufferList,
    AUAudioFrameCount frameCount
) {
    if (!bufferList || !bufferList->mNumberBuffers) return kAudioUnitErr_InvalidParameter;
    for (UInt32 i = 0; i < bufferList->mNumberBuffers; i++) {
        if (!bufferList->mBuffers[i].mData) return kAudioUnitErr_InvalidParameter;
        if (bufferList->mBuffers[i].mDataByteSize < frameCount * sizeof(float)) return kAudioUnitErr_InvalidParameter;
        bufferList->mBuffers[i].mDataByteSize = frameCount * sizeof(float);
    }

    return noErr;
}


static inline AUParameter *EmbraceAUMakeParameter(
    NSString *identifier, NSString *name, AUParameterAddress address,
    AUValue min, AUValue max, AUValue value, AudioUnitParameterUnit unit,
    NSArray<NSString *> *valueStrings)
{
    AUParameter *parameter = [AUParameterTree
        createParameterWithIdentifier: identifier
                                 name: name
                              address: address
                                  min: min
                                  max: max
                                 unit: unit
                             unitName: nil
                                flags: kAudioUnitParameterFlag_IsReadable |
                                       kAudioUnitParameterFlag_IsWritable
                         valueStrings: valueStrings
                  dependentParameters: nil];

    [parameter setValue:value];

    return parameter;
}


static inline AUParameter *EmbraceAUMakeParameter(
    NSString *identifier, NSString *name, AUParameterAddress address,
    AUValue min, AUValue max, AUValue value, AudioUnitParameterUnit unit)
{
    return EmbraceAUMakeParameter(identifier, name, address,
                                  min, max, value, unit, nil);
}


#endif
