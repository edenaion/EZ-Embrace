#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="builds/v4.3.0/mac/feature-tests"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
module_cache_kib=0
if [[ -d "$output/ModuleCache.noindex" ]]; then
    module_cache_kib=$(du -sk "$output/ModuleCache.noindex" | awk '{print $1 + 0}')
fi
estimated_kib=$((256 * 1024))
if (( module_cache_kib >= 100 * 1024 )); then
    estimated_kib=$((32 * 1024))
fi
# A cold module cache needs the full estimate; an existing populated cache makes
# this an incremental rebuild of small test executables.
if (( available_kib < 10 * 1024 * 1024 + estimated_kib )); then
    echo 'Insufficient free space for tests and the 10 GiB reserve.' >&2
    exit 1
fi
flags=(-fobjc-arc -fblocks -fmodules -fmodules-cache-path="$output/ModuleCache.noindex" -ISource -include Source/Prefix.pch -framework Cocoa -framework AudioToolbox -framework AVFoundation)
xcrun clang -std=c11 -Wall -Wextra -ISource tests/audio-lookahead.c \
    -o "$output/ez-embrace-lookahead-tests"
"$output/ez-embrace-lookahead-tests"
xcrun clang "${flags[@]}" tests/audio-seeking.m Source/HugAudioSource.m Source/HugAudioFile.m \
    Source/HugProtectedBuffer.m Source/HugUtils.m Source/HugError.m Source/HugAudioSettings.m \
    -o "$output/ez-embrace-audio-tests"
"$output/ez-embrace-audio-tests" "$@"
xcrun clang "${flags[@]}" tests/audio-failures.m Source/HugAudioSource.m Source/HugAudioFile.m \
    Source/HugProtectedBuffer.m Source/HugUtils.m Source/HugError.m Source/HugAudioSettings.m \
    -o "$output/ez-embrace-decoder-tests"
"$output/ez-embrace-decoder-tests"
xcrun clang "${flags[@]}" -framework CoreServices -framework CoreMedia tests/metadata.m Source/MetadataParser.m Source/TrackKeys.m \
    -o "$output/ez-embrace-metadata-tests"
"$output/ez-embrace-metadata-tests" "$@"
xcrun clang "${flags[@]}" -framework Accelerate -framework CoreAudio tests/effect-lifecycle.m \
    Source/HugAudioEngine.m Source/HugAudioSource.m Source/HugAudioFile.m Source/HugAudioSettings.m \
    Source/HugProtectedBuffer.m Source/HugUtils.m Source/HugError.m Source/HugFastUtils.m \
    Source/HugLimiter.m Source/HugLinearRamper.m Source/HugStereoField.m Source/HugLevelMeter.m \
    Source/HugMeterData.m Source/HugSimpleGraph.m Source/HugRingBuffer.m \
    -o "$output/ez-embrace-effect-tests"
"$output/ez-embrace-effect-tests"
xcrun clang "${flags[@]}" tests/eq-scaling.m Source/GraphicEQView.m \
    -o "$output/ez-embrace-eq-tests"
"$output/ez-embrace-eq-tests"
xcrun clang "${flags[@]}" tests/appearance.m Source/InterfaceAppearance.m Source/Preferences.m \
    -o "$output/ez-embrace-appearance-tests"
"$output/ez-embrace-appearance-tests"
bash tests/run-track-appearance.sh
