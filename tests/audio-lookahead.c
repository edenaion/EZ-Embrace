#include "HugAudioLookahead.h"

#include <stdio.h>
#include <stdlib.h>

static unsigned checks = 0;

static void check(int condition, const char *message)
{
    ++checks;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

int main(void)
{
    HugAudioLookaheadClock clock;
    HugAudioLookaheadClockInitialize(&clock);
    check(HugAudioLookaheadClockAheadFrames(&clock) == 0,
          "Clock initializes at zero");

    check(!HugAudioLookaheadClockDidPull(&clock, 512, 0),
          "Ordinary first pull does not request a stream reset");
    check(HugAudioLookaheadClockAheadFrames(&clock) == 0,
          "One pull for the current output is not lookahead");
    HugAudioLookaheadClockDidOutput(&clock, 512);
    check(HugAudioLookaheadClockAheadFrames(&clock) == 0,
          "Ordinary output remains aligned");

    HugAudioLookaheadClockDidPull(&clock, 512, 0);
    HugAudioLookaheadClockDidPull(&clock, 512, 0);
    HugAudioLookaheadClockDidPull(&clock, 512, 0);
    check(HugAudioLookaheadClockAheadFrames(&clock) == 1024,
          "Three pulls for one output report two buffers of lookahead");
    HugAudioLookaheadClockDidOutput(&clock, 512);
    check(HugAudioLookaheadClockAheadFrames(&clock) == 1024,
          "Stable read-ahead survives output accounting");

    HugAudioLookaheadClockRequestReset(&clock);
    check(HugAudioLookaheadClockDidPull(&clock, 512, 0),
          "A source swap is consumed on the next real pull");
    check(HugAudioLookaheadClockAheadFrames(&clock) == 0,
          "Source swap discards old lookahead debt");
    HugAudioLookaheadClockDidPull(&clock, 512, 0);
    check(HugAudioLookaheadClockAheadFrames(&clock) == 512,
          "New source establishes its own independent read-ahead");

    check(HugAudioLookaheadClockDidPull(&clock, 512, 7),
          "A completed seek generation requests a stream reset");
    check(HugAudioLookaheadClockAheadFrames(&clock) == 0,
          "Completed seek discards pre-seek lookahead");
    HugAudioLookaheadClockDidOutput(&clock, 512);
    check(HugAudioLookaheadClockAheadFrames(&clock) == 0,
          "Post-seek output starts aligned");

    HugAudioLookaheadClockRequestReset(&clock);
    HugAudioLookaheadClockDidOutput(&clock, 4096);
    check(HugAudioLookaheadClockAheadFrames(&clock) == 0,
          "Output without a source cannot underflow into false lookahead");
    check(HugAudioLookaheadClockDidPull(&clock, 512, 0),
          "Deferred reset survives silent output until the next source pull");
    check(HugAudioLookaheadClockAheadFrames(&clock) == 0,
          "Deferred reset starts the new source at zero debt");

    printf("PASS: %u lookahead-clock assertions\n", checks);
    return 0;
}
