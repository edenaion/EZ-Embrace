#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-builds/v4.3.0/mac/qa-tools}"
qa_bundle="$output/EZ-Embrace QA Capture.app"
mkdir -p "$qa_bundle/Contents/MacOS"
available_kib=$(df -k "$output" | awk 'END {print $4}')
if (( available_kib < 10 * 1024 * 1024 + 256 * 1024 )); then
    echo 'QA capture build refused: 10 GiB reserve.' >&2
    exit 1
fi
cat > "$qa_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ezscape.ezembrace.qa-capture</string>
<key>CFBundleName</key><string>EZ-Embrace QA Capture</string>
<key>CFBundleExecutable</key><string>ez-embrace-qa-capture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>LSUIElement</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>Capture only EZ-Embrace playback to verify audio continuity during its local stability test. No microphone or other app audio is included.</string>
</dict></plist>
PLIST
xcrun clang -fobjc-arc -fblocks -fmodules -mmacosx-version-min=14.2 \
    -framework AppKit -framework CoreAudio -framework AudioToolbox \
    tests/qa-audio-capture.m -o "$qa_bundle/Contents/MacOS/ez-embrace-qa-capture"
codesign --force --sign "${EZ_EMBRACE_QA_SIGN_IDENTITY:--}" --options runtime --timestamp=none "$qa_bundle"
codesign --verify --strict "$qa_bundle"
