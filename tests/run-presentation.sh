#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="builds/v4.3.0/mac/feature-tests/presentation"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 128 * 1024 )); then
    echo 'Insufficient space for presentation tests and 10 GiB reserve.' >&2
    exit 1
fi
bundle="$output/Presentation Tests.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun ibtool --compile "$bundle/Contents/Resources/CurrentTrackWindow.nib" Resources/CurrentTrackWindow.xib
xcrun clang -fobjc-arc -fblocks -fmodules -fmodules-cache-path="$output/ModuleCache.noindex" -ISource -include Source/Prefix.pch \
    -framework Cocoa -framework AudioToolbox -framework AVFoundation -framework Accelerate \
    tests/presentation.m Source/CurrentTrackController.m Source/CenteredTextField.m \
    Source/WaveformView.m Source/PlaybackSeekView.m Source/InterfaceAppearance.m Source/Preferences.m \
    Source/SetlistMeterView.m Source/SetlistSlider.m Source/TrackTableRowView.m Source/HugMeterData.m \
    Source/SetlistPlayBar.m Source/SetlistProgressBar.m Source/HairlineView.m \
    -o "$bundle/Contents/MacOS/ez-embrace-presentation-tests"
"$bundle/Contents/MacOS/ez-embrace-presentation-tests" "$@"
