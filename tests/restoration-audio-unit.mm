// Native checks for the in-process Declick and Dehum Audio Units and their
// parameter-tree editor. No output device is opened.

#undef auto

#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#import "RestorationAudioUnit.h"
#import "ParameterFormView.h"
#import "EffectParameterDescribing.h"

#include <cmath>
#include <vector>

static int sFailures = 0;
static const double kSampleRate = 44100.0;

static void check(const char *label, BOOL condition)
{
    if (!condition) ++sFailures;
    std::printf("   %-4s %s\n", condition ? "ok" : "FAIL", label);
}

static void checkClose(const char *label, double got, double want, double tolerance)
{
    BOOL condition = std::isfinite(got) && std::fabs(got - want) <= tolerance;
    if (!condition) ++sFailures;
    std::printf("   %-4s %-52s %10.5f (want %.5f +-%.5f)\n",
                condition ? "ok" : "FAIL", label, got, want, tolerance);
}

static AudioComponentDescription description(OSType subtype)
{
    AudioComponentDescription value = {0};
    value.componentType = kAudioUnitType_Effect;
    value.componentSubType = subtype;
    value.componentManufacturer = EmbraceRestorationManufacturer;
    return value;
}

static float sourceSample(int sourceKind, UInt64 frame, double rate)
{
    float base = (float)(0.08 * std::sin(2.0 * M_PI * 440.0 * (double)frame / rate));
    if (sourceKind == 1 && frame >= 16384 && frame <= 49152 && (frame % 8192) == 0) {
        return base + 0.95f;
    }
    if (sourceKind == 2) {
        return (float)(0.35 * std::sin(2.0 * M_PI * 60.0 * (double)frame / rate));
    }
    return base;
}

static std::vector<float> render(AUAudioUnit *unit, size_t outputFrames,
                                 AUAudioFrameCount slice, int sourceKind,
                                 AUAudioUnitStatus *finalStatus)
{
    UInt32 channels = [[[unit outputBusses] objectAtIndexedSubscript:0] format].channelCount;
    std::vector<float> left(slice, 0.0f), right(slice, 0.0f);
    std::vector<float> result;
    result.reserve(outputFrames);

    UInt32 listSize = (UInt32)(sizeof(AudioBufferList) +
                               (channels > 0 ? channels - 1 : 0) * sizeof(AudioBuffer));
    AudioBufferList *list = (AudioBufferList *)std::calloc(1, listSize);
    list->mNumberBuffers = channels;
    for (UInt32 channel = 0; channel < channels; ++channel) {
        list->mBuffers[channel].mNumberChannels = 1;
    }

    __block UInt64 sourceFrame = 0;
    const double rate = [[[unit outputBusses] objectAtIndexedSubscript:0] format].sampleRate;
    AURenderPullInputBlock pull = ^AUAudioUnitStatus(
        AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp,
        AUAudioFrameCount frames, NSInteger bus, AudioBufferList *data)
    {
        for (UInt32 channel = 0; channel < data->mNumberBuffers; ++channel) {
            float *samples = (float *)data->mBuffers[channel].mData;
            if (!samples) return kAudioUnitErr_InvalidParameter;
            for (AUAudioFrameCount i = 0; i < frames; ++i) {
                samples[i] = sourceSample(sourceKind, sourceFrame + i, rate);
            }
        }
        sourceFrame += frames;
        return noErr;
    };

    AUInternalRenderBlock block = [unit internalRenderBlock];
    AUAudioUnitStatus status = noErr;
    AudioTimeStamp timestamp = {0};
    timestamp.mFlags = kAudioTimeStampSampleTimeValid;

    while (result.size() < outputFrames && status == noErr) {
        AUAudioFrameCount frames = (AUAudioFrameCount)std::min<size_t>(slice,
            outputFrames - result.size());
        list->mBuffers[0].mData = left.data();
        list->mBuffers[0].mDataByteSize = frames * sizeof(float);
        if (channels > 1) {
            list->mBuffers[1].mData = right.data();
            list->mBuffers[1].mDataByteSize = frames * sizeof(float);
        }
        AudioUnitRenderActionFlags flags = 0;
        status = block(&flags, &timestamp, frames, 0, list, NULL, pull);
        if (status == noErr) result.insert(result.end(), left.begin(), left.begin() + frames);
        timestamp.mSampleTime += frames;
    }

    std::free(list);
    if (finalStatus) *finalStatus = status;
    return result;
}

static double rms(const std::vector<float> &samples, size_t start)
{
    double energy = 0.0;
    for (size_t i = start; i < samples.size(); ++i) {
        energy += (double)samples[i] * samples[i];
    }
    return std::sqrt(energy / (double)(samples.size() - start));
}

static AUAudioUnit *makeUnit(OSType subtype)
{
    NSError *error = nil;
    AUAudioUnit *unit = [[AUAudioUnit alloc]
        initWithComponentDescription:description(subtype) error:&error];
    check("unit instantiates without an error", unit != nil && error == nil);
    return unit;
}

static BOOL configure(AUAudioUnit *unit, double rate, AVAudioChannelCount channels)
{
    AVAudioFormat *format = [[AVAudioFormat alloc]
        initStandardFormatWithSampleRate:rate channels:channels];
    if (![[unit.inputBusses objectAtIndexedSubscript:0] setFormat:format error:nil]) return NO;
    if (![[unit.outputBusses objectAtIndexedSubscript:0] setFormat:format error:nil]) return NO;
    unit.maximumFramesToRender = 512;
    return [unit allocateRenderResourcesAndReturnError:nil];
}

static void testParameterTree(AUAudioUnit *unit, OSType subtype)
{
    NSArray<AUParameter *> *parameters = unit.parameterTree.allParameters;
    check("unit exposes eight parameters", parameters.count == 8);
    for (NSUInteger index = 0; index < parameters.count; ++index) {
        AUParameter *parameter = parameters[index];
        check("parameter addresses are contiguous", parameter.address == index);
        check("parameter defaults are finite and in range",
              std::isfinite(parameter.value) &&
              parameter.value >= parameter.minValue && parameter.value <= parameter.maxValue);
        check("parameter has contextual help",
              [[(id<ParameterDescribing>)unit
                  embrace_helpTextForParameterAddress:parameter.address] length] > 20);
    }

    AUParameter *last = parameters.lastObject;
    check("last parameter is the Delta switch",
          last.address == 7 && last.unit == kAudioUnitParameterUnit_Boolean);
    AUParameter *fifth = [unit.parameterTree parameterWithAddress:4];
    check("the fifth control differs by module",
          subtype == EmbraceDeclickSubType
            ? [fifth.displayName isEqualToString:@"Passes"]
            : [fifth.displayName isEqualToString:@"Frequency"]);

    AUParameter *first = parameters.firstObject;
    AUValue defaultValue = [(id<ParameterDescribing>)unit
        embrace_defaultValueForParameterAddress:first.address];
    first.value = NAN;
    checkClose("nonfinite writes restore the default", first.value, defaultValue, 0.0001);
    first.value = first.maxValue + 100;
    checkClose("out-of-range writes clamp at the maximum", first.value, first.maxValue, 0.0001);
    first.value = defaultValue;
}

static void testForm(AUAudioUnit *unit)
{
    ParameterFormView *form = [[ParameterFormView alloc] initWithAudioUnit:unit];
    check("generic parameter form has a usable fitting size",
          form.fittingSize.width > 350 && form.fittingSize.height > 200);

    NSInteger sliders = 0, checkboxes = 0;
    NSSlider *firstSlider = nil;
    for (NSView *view in form.subviews) {
        if ([view isKindOfClass:NSClassFromString(@"ParameterSlider")]) {
            ++sliders;
            if ([view tag] == 0) firstSlider = (NSSlider *)view;
        } else if ([view isKindOfClass:[NSButton class]]) {
            ++checkboxes;
        }
    }
    check("form creates seven sliders and one checkbox", sliders == 7 && checkboxes == 1);
    check("controls carry contextual tooltips", firstSlider.toolTip.length > 20);

    AUParameter *first = [unit.parameterTree parameterWithAddress:0];
    AUValue defaultValue = [(id<ParameterDescribing>)unit
        embrace_defaultValueForParameterAddress:0];
    first.value = first.minValue;
    [form reloadData];
    checkClose("reload reflects external parameter changes",
               firstSlider.doubleValue, first.minValue, 0.0001);
    [NSApp sendAction:NSSelectorFromString(@"_handleSliderDoubleClick:")
                   to:form from:firstSlider];
    checkClose("double-click action restores one default",
               first.value, defaultValue, 0.0001);
}

static void testRenderContract(AUAudioUnit *unit)
{
    AUInternalRenderBlock block = unit.internalRenderBlock;
    std::vector<float> samples(513, 0.0f);
    AudioBufferList list = {0};
    list.mNumberBuffers = 1;
    list.mBuffers[0].mNumberChannels = 1;
    list.mBuffers[0].mData = samples.data();
    list.mBuffers[0].mDataByteSize = (UInt32)(samples.size() * sizeof(float));
    AudioTimeStamp timestamp = {0};
    AudioUnitRenderActionFlags flags = 0;
    AURenderPullInputBlock pull = ^AUAudioUnitStatus(
        AudioUnitRenderActionFlags *pullFlags, const AudioTimeStamp *time,
        AUAudioFrameCount frames, NSInteger bus, AudioBufferList *data)
    {
        return noErr;
    };

    check("oversized render is rejected",
          block(&flags, &timestamp, 513, 0, &list, NULL, pull) ==
              kAudioUnitErr_TooManyFramesToProcess);
    check("missing pull input is rejected",
          block(&flags, &timestamp, 16, 0, &list, NULL, nil) ==
              kAudioUnitErr_NoConnection);
    list.mBuffers[0].mData = NULL;
    check("missing output storage is rejected",
          block(&flags, &timestamp, 16, 0, &list, NULL, pull) ==
              kAudioUnitErr_InvalidParameter);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        std::printf("restoration Audio Unit checks\n\n");

        std::printf("== registration and parameter trees\n");
        EmbraceRegisterRestorationAudioUnits();
        for (OSType subtype : {EmbraceDeclickSubType, EmbraceDehumSubType}) {
            AudioComponentDescription componentDescription = description(subtype);
            AudioComponent component = AudioComponentFindNext(NULL, &componentDescription);
            check("registered component is discoverable", component != NULL);
            AUAudioUnit *unit = makeUnit(subtype);
            if (!unit) continue;
            testParameterTree(unit, subtype);
            testForm(unit);

            NSDictionary *state = unit.fullState;
            AUAudioUnit *restored = makeUnit(subtype);
            restored.fullState = state;
            BOOL matched = YES;
            for (AUParameter *parameter in unit.parameterTree.allParameters) {
                AUParameter *copy = [restored.parameterTree parameterWithAddress:parameter.address];
                if (std::fabs(parameter.value - copy.value) > 0.0001) matched = NO;
            }
            check("all parameters survive a full-state round trip", matched);
        }

        std::printf("\n== format matrix and render guards\n");
        for (OSType subtype : {EmbraceDeclickSubType, EmbraceDehumSubType}) {
            for (double rate : {44100.0, 48000.0}) {
                for (AVAudioChannelCount channels : {1u, 2u}) {
                    AUAudioUnit *unit = makeUnit(subtype);
                    check("mono/stereo render resources allocate at 44.1/48 kHz",
                          configure(unit, rate, channels));
                    AUAudioUnitStatus status = noErr;
                    std::vector<float> output = render(unit, 4096, 512, 0, &status);
                    BOOL finite = status == noErr && output.size() == 4096;
                    for (float value : output) finite = finite && std::isfinite(value);
                    check("matrix render completes with finite output", finite);
                    testRenderContract(unit);
                    [unit deallocateRenderResources];
                }
            }
        }

        std::printf("\n== mismatched formats are refused\n");
        {
            AUAudioUnit *unit = makeUnit(EmbraceDehumSubType);
            AVAudioFormat *mono = [[AVAudioFormat alloc]
                initStandardFormatWithSampleRate:44100 channels:1];
            AVAudioFormat *stereo = [[AVAudioFormat alloc]
                initStandardFormatWithSampleRate:44100 channels:2];
            [unit.inputBusses[0] setFormat:mono error:nil];
            [unit.outputBusses[0] setFormat:stereo error:nil];
            NSError *error = nil;
            check("allocation rejects mismatched channel counts",
                  ![unit allocateRenderResourcesAndReturnError:&error] &&
                  error.code == kAudioUnitErr_FormatNotSupported);
        }

        std::printf("\n== Declick read-ahead, bypass, reset and repair\n");
        {
            AUAudioUnit *unit = makeUnit(EmbraceDeclickSubType);
            check("Declick configures", configure(unit, kSampleRate, 2));
            unit.shouldBypassEffect = YES;
            AUAudioUnitStatus status = noErr;
            std::vector<float> bypass = render(unit, 32768, 512, 1, &status);
            double worst = 0.0;
            for (size_t i = 0; i < bypass.size(); ++i) {
                worst = std::max(worst,
                    std::fabs((double)bypass[i] - sourceSample(1, i, kSampleRate)));
            }
            check("Declick bypass render succeeds", status == noErr);
            checkClose("Declick read-ahead stays sample aligned", worst, 0.0, 0.000001);

            [unit reset];
            std::vector<float> afterReset = render(unit, 4096, 512, 0, &status);
            checkClose("Declick reset empties and correctly refills its pipeline",
                       afterReset[0], sourceSample(0, 0, kSampleRate), 0.000001);

            unit.shouldBypassEffect = NO;
            [unit.parameterTree parameterWithAddress:0].value = 1.0f;
            [unit.parameterTree parameterWithAddress:2].value = 2.0f;
            [unit.parameterTree parameterWithAddress:4].value = 1.0f;
            [unit.parameterTree parameterWithAddress:5].value = 16.0f;
            [unit.parameterTree parameterWithAddress:6].value = 1.0f;
            [unit reset];
            std::vector<float> repaired = render(unit, 65536, 512, 1, &status);
            double damagedError = 0.0, repairedError = 0.0;
            for (size_t frame = 16384; frame <= 49152; frame += 8192) {
                double clean = sourceSample(0, frame, kSampleRate);
                damagedError += std::fabs(sourceSample(1, frame, kSampleRate) - clean);
                repairedError += std::fabs(repaired[frame] - clean);
            }
            check("Declick wet render remains finite", status == noErr && std::isfinite(rms(repaired, 0)));
            check("Declick Audio Unit reduces injected-click error", repairedError < damagedError);
        }

        std::printf("\n== Dehum manual removal, bypass and seek reset\n");
        {
            AUAudioUnit *unit = makeUnit(EmbraceDehumSubType);
            check("Dehum configures", configure(unit, kSampleRate, 2));
            [unit.parameterTree parameterWithAddress:4].value = 60.0f;
            [unit.parameterTree parameterWithAddress:5].value = 0.0f;
            [unit.parameterTree parameterWithAddress:6].value = 1.0f;
            AUAudioUnitStatus status = noErr;
            std::vector<float> cleaned = render(unit, (size_t)(kSampleRate * 4), 512, 2, &status);
            std::vector<float> input(cleaned.size());
            for (size_t i = 0; i < input.size(); ++i) input[i] = sourceSample(2, i, kSampleRate);
            check("Dehum wet render succeeds", status == noErr);
            check("Dehum Audio Unit removes a manual 60 Hz line",
                  rms(cleaned, cleaned.size() / 2) < rms(input, input.size() / 2) * 0.20);

            [unit reset];
            std::vector<float> afterReset = render(unit, (size_t)kSampleRate, 512, 2, &status);
            check("Dehum seek reset keeps the manual line active",
                  rms(afterReset, afterReset.size() / 2) < rms(input, input.size() / 2) * 0.25);

            unit.shouldBypassEffect = YES;
            [unit reset];
            std::vector<float> bypass = render(unit, 8192, 512, 2, &status);
            double worst = 0.0;
            for (size_t i = 0; i < bypass.size(); ++i) {
                worst = std::max(worst,
                    std::fabs((double)bypass[i] - sourceSample(2, i, kSampleRate)));
            }
            checkClose("Dehum bypass is sample exact", worst, 0.0, 0.000001);
            check("Dehum exposes the track-scouting contract",
                  [unit conformsToProtocol:@protocol(EmbraceTrackScouting)]);
            [(id<EmbraceTrackScouting>)unit embrace_scoutFileURL:nil];
        }

        std::printf("\n%s (%d failures)\n",
                    sFailures ? "FAILED" : "all checks passed", sFailures);
    }
    return sFailures ? 1 : 0;
}
