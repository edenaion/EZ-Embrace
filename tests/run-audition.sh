#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="builds/v4.3.0/mac/feature-tests/audition"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 32 * 1024 )); then
    echo 'Insufficient space for audition tests and 10 GiB reserve.' >&2
    exit 1
fi
bundle="$output/EZ-Embrace Audition QA.app"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ezscape.EZEmbrace.AuditionQA</string>
<key>CFBundleExecutable</key><string>Audition QA</string>
<key>CFBundleName</key><string>EZ-Embrace Audition QA</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun clang -fobjc-arc -fblocks -fno-modules -DEZ_EMBRACE_TEST_ROOT="\"$(pwd)\"" \
    -Wno-incomplete-implementation -Wno-objc-property-implementation \
    -ISource -include Source/Prefix.pch -framework Cocoa -framework AVFoundation -framework CoreAudio \
    tests/audition.m Source/AuditionPlayer.m Source/AuditionRoute.m Source/Preferences.m \
    -o "$bundle/Contents/MacOS/Audition QA"
"$bundle/Contents/MacOS/Audition QA"
