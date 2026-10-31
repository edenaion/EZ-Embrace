#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

output="builds/v4.3.0/mac/feature-tests/queue-cues"
log="logs/261021_track-cues_queue-contract.log"
mkdir -p "$output" "$(dirname "$log")"

# The native harness and linked test executable are budgeted at 64 MiB.
available_kib=$(df -k "$output" | awk 'END {print $4}')
required_kib=$((10 * 1024 * 1024 + 64 * 1024))
if (( available_kib < required_kib )); then
    printf 'Insufficient free space: %s KiB available; need %s KiB to preserve the 10 GiB reserve.\n' \
        "$available_kib" "$required_kib" | tee "$log" >&2
    exit 1
fi

if ! xcrun clang -fobjc-arc -fblocks -fno-modules -Wno-incomplete-implementation -Wno-objc-property-implementation \
    -Wno-objc-protocol-method-implementation -Wno-property-attribute-mismatch -Wno-deprecated-declarations \
    -ISource -include Source/Prefix.pch -include CoreServices/CoreServices.h \
    -framework Cocoa -framework AVFoundation -framework CoreServices \
    tests/queue-cues.m Source/TracksController.m Source/Track.m Source/TrackKeys.m Source/HugError.m \
    -o "$output/ez-embrace-queue-cue-tests" >"$log" 2>&1; then
    cat "$log" >&2
    exit 1
fi

if ! "$output/ez-embrace-queue-cue-tests" >>"$log" 2>&1; then
    cat "$log" >&2
    exit 1
fi

cat "$log"
