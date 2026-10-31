#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

output="builds/v4.3.0/mac/feature-tests/restoration-audio-unit"
mkdir -p "$output"
module_cache="builds/v4.3.0/mac/feature-tests/ModuleCache.noindex"
module_cache_kib=$(du -sk "$module_cache" 2>/dev/null | awk '{print $1 + 0}')
estimated_kib=$((160 * 1024))
if (( module_cache_kib >= 100 * 1024 )); then
    estimated_kib=$((8 * 1024))
fi
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + estimated_kib )); then
    echo 'Insufficient free space for tests and the 10 GiB reserve.' >&2
    exit 1
fi

mkdir -p "$module_cache"
objects=()

for source in tests/restoration-audio-unit.mm Source/RestorationAudioUnit.mm; do
    object="$output/$(basename "$source").o"
    xcrun clang++ -c -fobjc-arc -fmodules -fmodules-cache-path="$module_cache" \
        -std=c++17 -O1 -g -Wall -Wextra -ISource -include Source/Prefix.pch \
        "$source" -o "$object"
    objects+=("$object")
done

for source in Source/declick_core.cpp Source/dehum_core.cpp; do
    object="$output/$(basename "$source").o"
    xcrun clang++ -c -std=c++17 -O1 -g -Wall -Wextra -ISource "$source" -o "$object"
    objects+=("$object")
done

for source in Source/ParameterFormView.m Source/HugAudioFile.m Source/HugUtils.m Source/HugError.m Source/Log.m; do
    object="$output/$(basename "$source").o"
    xcrun clang -c -fobjc-arc -fmodules -fmodules-cache-path="$module_cache" \
        -O1 -g -Wall -Wextra -ISource -include Source/Prefix.pch \
        "$source" -o "$object"
    objects+=("$object")
done

xcrun clang++ "${objects[@]}" \
    -framework Cocoa -framework AudioToolbox -framework AVFoundation \
    -framework CoreAudioKit -o "$output/unit-tests"
"$output/unit-tests"
