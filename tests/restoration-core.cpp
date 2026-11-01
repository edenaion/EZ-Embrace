// Portable restoration DSP checks. These exercise the EmbraceNG declick and
// dehum cores without Apple frameworks or an audio device.

#include "declick_core.h"
#include "dehum_core.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <vector>

static int sFailures = 0;

static void check(const char *label, bool condition)
{
    if (!condition) ++sFailures;
    std::printf("   %-4s %s\n", condition ? "ok" : "FAIL", label);
}

static bool allFinite(const std::vector<float> &samples)
{
    for (float sample : samples) {
        if (!std::isfinite(sample)) return false;
    }
    return true;
}

static std::vector<float> runDeclick(const std::vector<float> &input,
                                     declick::Params params,
                                     bool wide,
                                     uint64_t *repaired,
                                     size_t *heapBefore,
                                     size_t *heapAfter)
{
    declick::allowWideKernels(wide);
    declick::Config config;
    config.maxBlock = 2048;
    config.compute(params, 44100.0);

    declick::Channel channel;
    channel.configure(config);
    if (heapBefore) *heapBefore = channel.heapBytes();

    declick::Params retuned = params;
    retuned.sensitivity = std::max(0.0f, params.sensitivity - 0.05f);
    declick::Config retunedConfig;
    retunedConfig.maxBlock = config.maxBlock;
    retunedConfig.compute(retuned, 44100.0);
    check("declick live sensitivity retune succeeds", channel.retune(retunedConfig));
    check("declick retune keeps the allocated envelope",
          !heapAfter || (*heapAfter = channel.heapBytes()) == *heapBefore);

    for (size_t offset = 0; offset < input.size(); offset += 257) {
        const size_t count = std::min<size_t>(257, input.size() - offset);
        channel.push(input.data() + offset, count, 1);
    }
    channel.drain();

    check("declick drain exposes the full input", channel.available() >= input.size());
    std::vector<float> output(input.size(), 0.0f);
    channel.pull(output.data(), output.size(), 1);
    if (repaired) *repaired = channel.repairedSamples();
    return output;
}

static double rms(const std::vector<float> &samples, size_t first)
{
    double energy = 0.0;
    for (size_t i = first; i < samples.size(); ++i) {
        energy += (double)samples[i] * samples[i];
    }
    return std::sqrt(energy / (double)(samples.size() - first));
}

int main()
{
    std::printf("restoration core checks\n\n");

    std::printf("== parameter sanitizing and configuration\n");
    {
        declick::Params p = declick::Params::defaults();
        p.sensitivity = -4.0f;
        p.extent = 8.0f;
        p.maxLengthMs = 100.0f;
        p.depth = -1.0f;
        p.passes = 12;
        p.order = 511;
        p.dryWet = 3.0f;
        p.sanitize();
        check("declick parameters clamp to documented limits",
              p.sensitivity == 0.0f && p.extent == 1.0f &&
              p.maxLengthMs == 20.0f && p.depth == 0.0f &&
              p.passes == 3 && p.order == declick::kMaxOrder &&
              p.dryWet == 1.0f);

        declick::Config c;
        c.compute(p, 48000.0);
        check("declick 48 kHz configuration has bounded latency",
              c.latency > declick::kBlock && c.bufPad >= c.pad);

        dehum::Params h = dehum::Params::defaults();
        h.sensitivity = std::numeric_limits<float>::quiet_NaN();
        h.bandwidth = -1.0f;
        h.searchTo = 999.0f;
        h.harmonics = 99;
        h.frequency = 2.0f;
        h.rumbleHz = 999.0f;
        h.dryWet = -3.0f;
        h.sanitize();
        check("dehum parameters clamp and reject nonfinite input",
              h.sensitivity == 0.0f && h.bandwidth == 0.1f &&
              h.searchTo == dehum::kSearchCeil &&
              h.harmonics == dehum::kMaxHarmonics &&
              h.frequency == 10.0f && h.rumbleHz == 200.0f &&
              h.dryWet == 0.0f);

        dehum::Config hc;
        hc.compute(h, 48000.0);
        check("dehum 48 kHz configuration is internally bounded",
              hc.sampleRate == 48000.0 && hc.winSize > 0 &&
              hc.binHi > hc.binLo && hc.bufBins >= hc.binHi - hc.binLo + 1);
    }

    std::printf("\n== declick streaming, bypass and repair\n");
    {
        const size_t count = 65536;
        std::vector<float> clean(count);
        std::vector<float> damaged(count);
        for (size_t i = 0; i < count; ++i) {
            clean[i] = (float)(0.08 * std::sin(2.0 * M_PI * 440.0 * (double)i / 44100.0));
            damaged[i] = clean[i];
        }
        const size_t clicks[] = {16384, 24576, 32768, 40960, 49152};
        for (size_t index : clicks) damaged[index] += (index & 1) ? -0.95f : 0.95f;

        declick::Params bypass = declick::Params::defaults();
        bypass.order = 16;
        bypass.passes = 1;
        bypass.dryWet = 0.0f;
        uint64_t bypassRepairs = 0;
        size_t heapBefore = 0, heapAfter = 0;
        std::vector<float> dry = runDeclick(damaged, bypass, false,
                                             &bypassRepairs, &heapBefore, &heapAfter);
        check("declick bypass is sample-exact", dry == damaged);
        check("declick bypass output is finite", allFinite(dry));

        declick::Params wet = bypass;
        wet.sensitivity = 1.0f;
        wet.extent = 0.5f;
        wet.maxLengthMs = 2.0f;
        wet.depth = 1.0f;
        wet.dryWet = 1.0f;
        uint64_t repaired = 0;
        std::vector<float> restored = runDeclick(damaged, wet, true,
                                                  &repaired, nullptr, nullptr);
        double damagedError = 0.0, restoredError = 0.0;
        for (size_t index : clicks) {
            damagedError += std::fabs((double)damaged[index] - clean[index]);
            restoredError += std::fabs((double)restored[index] - clean[index]);
        }
        check("declick detects and repairs injected impulses", repaired > 0);
        check("declick reduces error at injected impulses", restoredError < damagedError);
        check("declick repaired output is finite", allFinite(restored));
    }

    std::printf("\n== dehum bypass, manual notch, flush and adopt\n");
    {
        const double rate = 44100.0;
        const size_t count = (size_t)(rate * 4.0);
        std::vector<float> tone(count);
        for (size_t i = 0; i < count; ++i) {
            tone[i] = (float)(0.35 * std::sin(2.0 * M_PI * 60.0 * (double)i / rate));
        }

        dehum::Params bypass = dehum::Params::defaults();
        bypass.frequency = 60.0f;
        bypass.rumbleHz = 0.0f;
        bypass.dryWet = 0.0f;
        dehum::Config bypassConfig;
        bypassConfig.compute(bypass, rate);
        dehum::Channel bypassChannel;
        bypassChannel.configure(bypassConfig);
        const size_t bypassHeap = bypassChannel.heapBytes();
        std::vector<float> dry = tone;
        bypassChannel.process(dry.data(), dry.size(), 1);
        check("dehum bypass is sample-exact", dry == tone);

        dehum::Params retuned = bypass;
        retuned.bandwidth = 2.0f;
        dehum::Config retunedConfig;
        retunedConfig.compute(retuned, rate);
        check("dehum live bandwidth retune succeeds", bypassChannel.retune(retunedConfig));
        check("dehum retune keeps the allocated envelope",
              bypassChannel.heapBytes() == bypassHeap);

        dehum::Params wet = retuned;
        wet.dryWet = 1.0f;
        dehum::Config wetConfig;
        wetConfig.compute(wet, rate);
        dehum::Channel channel;
        channel.configure(wetConfig);
        std::vector<float> cleaned = tone;
        for (size_t offset = 0; offset < cleaned.size(); offset += 191) {
            const size_t n = std::min<size_t>(191, cleaned.size() - offset);
            channel.process(cleaned.data() + offset, n, 1);
            if (offset > count / 3 && offset < count / 3 + 191) channel.flush();
        }
        check("dehum manual notch output is finite", allFinite(cleaned));
        check("dehum manual notch removes a steady 60 Hz line",
              rms(cleaned, count / 2) < rms(tone, count / 2) * 0.20);
        check("dehum manual frequency remains active across a seek flush",
              channel.lineCount() == 1);

        dehum::Params automatic = dehum::Params::defaults();
        automatic.rumbleHz = 0.0f;
        dehum::Config automaticConfig;
        automaticConfig.compute(automatic, rate);
        dehum::Channel adopted;
        adopted.configure(automaticConfig);
        dehum::LineReport line;
        line.frequency = 60.0;
        line.viaCoherence = true;
        adopted.adopt(&line, 1);
        check("dehum accepts a scouted line in automatic mode", adopted.lineCount() == 1);
        adopted.flush();
        check("dehum keeps a scouted line across a seek flush", adopted.lineCount() == 1);
    }

    std::printf("\n%d failure(s)\n", sFailures);
    return sFailures ? 1 : 0;
}
