#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="builds/v4.3.0/mac/feature-tests/track-appearance"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 64 * 1024 )); then
    echo 'Insufficient space for track appearance tests and 10 GiB reserve.' >&2
    exit 1
fi
xcrun clang -fobjc-arc -fblocks -fno-modules -Wno-incomplete-implementation -Wno-objc-property-implementation \
    -ISource -include Source/Prefix.pch -framework Cocoa -framework AudioToolbox -framework QuartzCore -framework Accelerate \
    tests/track-appearance.m Source/TrackTableCellView.m Source/TrackTableView.m Source/TrackTableRowView.m \
    Source/InterfaceAppearance.m Source/Preferences.m \
    Source/TrackCueController.m Source/WaveformView.m Source/PlaybackSeekView.m \
    -o "$output/ez-embrace-track-appearance-tests"
"$output/ez-embrace-track-appearance-tests"
