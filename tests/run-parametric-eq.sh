#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="builds/v4.3.0/mac/feature-tests/parametric-eq"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 256 * 1024 )); then
    echo 'Insufficient free space for tests and the 10 GiB reserve.' >&2
    exit 1
fi
xcrun clang++ -std=c++17 -O2 -g -ISource tests/parametric-eq-core.cpp Source/paraeq_core.cpp -o "$output/core-tests"
"$output/core-tests"
xcrun clang++ -std=c++17 -O0 -g -fsanitize=address,undefined -fno-omit-frame-pointer -ISource \
    tests/parametric-eq-core.cpp Source/paraeq_core.cpp -o "$output/core-sanitizers"
"$output/core-sanitizers"
objects=()
for source in tests/parametric-eq-unit.mm Source/ParametricEQAudioUnit.mm Source/ParametricEQView.mm Source/paraeq_core.cpp; do
    object="$output/$(basename "$source").o"
    if [[ "$source" == *.cpp ]]; then
        xcrun clang++ -c -std=c++17 -O1 -g -Wall -ISource "$source" -o "$object"
    else
        xcrun clang++ -c -fobjc-arc -fmodules -std=c++17 -O1 -g -Wall -ISource "$source" -o "$object"
    fi
    objects+=("$object")
done
for source in Source/EffectType.m Source/EffectAdditions.m Source/AudioUnitStateValidation.m Source/Effect.m Source/Log.m Source/HugUtils.m Source/EQStateButton.m; do
    object="$output/$(basename "$source").o"
    xcrun clang -c -fobjc-arc -fmodules -O1 -g -Wall -ISource -include Source/Prefix.pch "$source" -o "$object"
    objects+=("$object")
done
xcrun clang++ "${objects[@]}" -framework Cocoa -framework AudioToolbox -framework AVFoundation -framework CoreAudioKit -o "$output/unit-tests"
"$output/unit-tests"
objects_without_main=()
for object in "${objects[@]}"; do
    [[ "$object" == */parametric-eq-unit.mm.o ]] || objects_without_main+=("$object")
done
xcrun clang -c -fobjc-arc -fmodules -O1 -g -Wall -ISource -include Source/Prefix.pch tests/audio-unit-state.m -o "$output/audio-unit-state.m.o"
state_bundle="$output/State Tests.app/Contents"
mkdir -p "$state_bundle/MacOS" "$state_bundle/Resources"
cp Resources/EmbraceParametricEQ-{Violin,Singer}.aupreset "$state_bundle/Resources/"
cat > "$state_bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>state-tests</string>
<key>CFBundleExecutable</key><string>state-tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun clang++ "$output/audio-unit-state.m.o" "${objects_without_main[@]}" -framework Cocoa -framework AudioToolbox -framework AVFoundation -framework CoreAudioKit -o "$state_bundle/MacOS/state-tests"
"$state_bundle/MacOS/state-tests"
"$state_bundle/MacOS/state-tests" --verify-slots
toggle_objects=()
for source in tests/eq-toggle.m Source/SetlistEQButton.m Source/InterfaceAppearance.m Source/Preferences.m Source/EditEffectController.m; do
    object="$output/$(basename "$source").o"
    xcrun clang -c -fobjc-arc -fmodules -O1 -g -Wall -ISource -include Source/Prefix.pch "$source" -o "$object"
    toggle_objects+=("$object")
done
toggle_bundle="$output/EQ Toggle Tests.app/Contents"
mkdir -p "$toggle_bundle/MacOS" "$toggle_bundle/Resources"
cp Resources/EmbraceParametricEQ-{Violin,Singer}.aupreset "$toggle_bundle/Resources/"
sed 's/state-tests/eq-toggle-tests/g' "$state_bundle/Info.plist" > "$toggle_bundle/Info.plist"
xcrun clang++ "${toggle_objects[@]}" "${objects_without_main[@]}" -framework Cocoa -framework AudioToolbox -framework AVFoundation -framework CoreAudioKit -o "$toggle_bundle/MacOS/eq-toggle-tests"
"$toggle_bundle/MacOS/eq-toggle-tests"
