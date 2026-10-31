#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="builds/v4.3.0/mac/feature-tests/track-cues"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 64 * 1024 )); then
    echo 'Insufficient free space for Track cue tests and the 10 GiB reserve.' >&2
    exit 1
fi
xcrun clang -fobjc-arc -fblocks -fno-modules -Wno-incomplete-implementation -Wno-objc-property-implementation \
    -ISource -include Source/Prefix.pch -framework Cocoa -framework AVFoundation \
    tests/track-cues.m Source/Track.m Source/TrackKeys.m Source/HugError.m \
    -o "$output/ez-embrace-track-cue-tests"
"$output/ez-embrace-track-cue-tests"
