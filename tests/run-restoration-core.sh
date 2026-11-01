#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

output="builds/v4.3.0/mac/feature-tests/restoration-core"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 64 * 1024 )); then
    echo 'Insufficient free space for tests and the 10 GiB reserve.' >&2
    exit 1
fi

xcrun clang++ -std=c++17 -O2 -g -Wall -Wextra -ISource \
    tests/restoration-core.cpp Source/declick_core.cpp Source/dehum_core.cpp \
    -o "$output/core-tests"
"$output/core-tests"

xcrun clang++ -std=c++17 -O1 -g -Wall -Wextra \
    -fsanitize=address,undefined -fno-omit-frame-pointer -ISource \
    tests/restoration-core.cpp Source/declick_core.cpp Source/dehum_core.cpp \
    -o "$output/core-sanitizers"
"$output/core-sanitizers"
