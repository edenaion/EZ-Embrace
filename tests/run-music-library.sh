#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="builds/v4.3.0/mac/feature-tests/music-library"
mkdir -p "$output"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 32 * 1024 )); then
    echo 'Insufficient space for library tests and 10 GiB reserve.' >&2
    exit 1
fi
bundle="$output/EZ-Embrace Library QA.app"
fixture_root="$(pwd)"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ezscape.EZEmbrace.LibraryQA</string>
<key>CFBundleExecutable</key><string>Library QA</string>
<key>CFBundleName</key><string>EZ-Embrace Library QA</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun clang -fobjc-arc -fblocks -fno-modules -DEZ_EMBRACE_TEST_ROOT="\"$fixture_root\"" -Wno-incomplete-implementation -Wno-objc-property-implementation \
    -ISource -include Source/Prefix.pch -framework Cocoa -framework AudioToolbox -framework CoreServices -framework iTunesLibrary -framework AVFoundation -framework CoreAudio \
    tests/music-library.m Source/MusicLibrary.m Source/MusicLibraryBackupStore.m Source/MusicLibraryController.m \
    Source/InterfaceAppearance.m Source/Preferences.m Source/MusicAppManager.m Source/TrackKeys.m Source/AuditionPlayer.m Source/AuditionRoute.m \
    -o "$bundle/Contents/MacOS/Library QA"
"$bundle/Contents/MacOS/Library QA" "$@"
