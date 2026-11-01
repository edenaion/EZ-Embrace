// Render-clock accounting for effects that pull audio ahead of the buffer the
// output device is currently consuming. Header-only so the arithmetic can be
// tested without constructing an audio device.

#ifndef HUG_AUDIO_LOOKAHEAD_H
#define HUG_AUDIO_LOOKAHEAD_H

#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>

typedef struct {
    atomic_uint_fast64_t sourceFrames;
    atomic_uint_fast64_t outputFrames;
    atomic_uint_fast64_t aheadFrames;
    atomic_uint seekGeneration;
    atomic_bool resetRequested;
} HugAudioLookaheadClock;

static inline void HugAudioLookaheadClockInitialize(HugAudioLookaheadClock *clock)
{
    atomic_init(&clock->sourceFrames, 0);
    atomic_init(&clock->outputFrames, 0);
    atomic_init(&clock->aheadFrames, 0);
    atomic_init(&clock->seekGeneration, 0);
    atomic_init(&clock->resetRequested, false);
}

static inline void HugAudioLookaheadClockRequestReset(HugAudioLookaheadClock *clock)
{
    atomic_store_explicit(&clock->resetRequested, true, memory_order_release);
}

// Called after an input pull. Returns true when the effect pipeline must discard
// its old stream before accepting the just-pulled samples.
static inline bool HugAudioLookaheadClockDidPull(HugAudioLookaheadClock *clock,
                                                uint64_t frames,
                                                unsigned seekGeneration)
{
    bool reset = atomic_exchange_explicit(
        &clock->resetRequested, false, memory_order_acquire);
    unsigned previousSeek = atomic_load_explicit(
        &clock->seekGeneration, memory_order_relaxed);
    bool didSeek = seekGeneration != previousSeek;

    if (reset || didSeek) {
        atomic_store_explicit(&clock->sourceFrames, frames, memory_order_relaxed);
        atomic_store_explicit(&clock->outputFrames, 0, memory_order_relaxed);
        atomic_store_explicit(&clock->aheadFrames, 0, memory_order_relaxed);
        atomic_store_explicit(&clock->seekGeneration, seekGeneration, memory_order_relaxed);
    } else {
        atomic_fetch_add_explicit(&clock->sourceFrames, frames, memory_order_relaxed);
    }

    uint64_t source = atomic_load_explicit(&clock->sourceFrames, memory_order_relaxed);
    uint64_t output = atomic_load_explicit(&clock->outputFrames, memory_order_relaxed);
    uint64_t currentOutputEnd = output + frames;
    uint64_t ahead = source > currentOutputEnd ? source - currentOutputEnd : 0;
    atomic_store_explicit(&clock->aheadFrames, ahead, memory_order_relaxed);

    return reset || didSeek;
}

static inline void HugAudioLookaheadClockDidOutput(HugAudioLookaheadClock *clock,
                                                   uint64_t frames)
{
    uint64_t output = atomic_fetch_add_explicit(
        &clock->outputFrames, frames, memory_order_relaxed) + frames;
    uint64_t source = atomic_load_explicit(&clock->sourceFrames, memory_order_relaxed);
    uint64_t ahead = source > output ? source - output : 0;
    atomic_store_explicit(&clock->aheadFrames, ahead, memory_order_relaxed);
}

static inline uint64_t HugAudioLookaheadClockAheadFrames(
    const HugAudioLookaheadClock *clock)
{
    return atomic_load_explicit(&clock->aheadFrames, memory_order_relaxed);
}

#endif
