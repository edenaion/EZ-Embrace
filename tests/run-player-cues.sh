#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="builds/v4.3.0/mac/feature-tests/player-cues"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 64 * 1024 )); then
    echo 'Insufficient free space for Player cue tests and the 10 GiB reserve.' >&2
    exit 1
fi
xcrun clang -fobjc-arc -fblocks -fno-modules -Wno-incomplete-implementation -Wno-objc-property-implementation \
    -ISource -include Source/Prefix.pch -framework Cocoa -framework AVFoundation \
    -framework AudioToolbox -framework CoreAudio -framework IOKit -framework Accelerate \
    tests/player-cues.m Source/Player.m \
    -o "$output/ez-embrace-player-cue-tests"

test_home=$(mktemp -d "${TMPDIR:-/tmp}/embrace-player-cues.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
CFFIXED_USER_HOME="$test_home" "$output/ez-embrace-player-cue-tests"
