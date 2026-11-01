#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${EZ_EMBRACE_SIGN_IDENTITY:?Set a local Developer ID Application signing identity}"
version="4.6.0"
output="builds/v${version}/mac/candidate"
derived="builds/v${version}/mac/candidate-derived"
mkdir -p "$output"
if [[ -e "$output/EZ-Embrace.app" ]]; then
    echo 'Candidate already exists. Preserve the tested candidate before building another.' >&2
    exit 1
fi
available_kib=$(df -k "$output" | awk 'END {print $4}')
# Recent universal candidate builds use about 350 MiB. Allow 512 MiB, then retain 10 GiB.
if (( available_kib < 10 * 1024 * 1024 + 512 * 1024 )); then
    echo 'Insufficient free space for candidate build and 10 GiB reserve.' >&2
    exit 1
fi
xcodebuild -project Embrace.xcodeproj -scheme Embrace -configuration Release \
    -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO \
    ARCHS='arm64 x86_64' build
ditto "$derived/Build/Products/Release/EZ-Embrace.app" "$output/EZ-Embrace.app"
licenses="$output/EZ-Embrace.app/Contents/Resources/Licenses"
mkdir -p "$licenses"
cp LICENSE LICENSE.EmbraceNG "$licenses/"
codesign --force --options runtime --timestamp --sign "$EZ_EMBRACE_SIGN_IDENTITY" \
    --entitlements Resources/Worker.entitlements "$output/EZ-Embrace.app/Contents/XPCServices/EmbraceWorker.xpc"
codesign --force --options runtime --timestamp --sign "$EZ_EMBRACE_SIGN_IDENTITY" \
    --entitlements Resources/CrashPad.entitlements "$output/EZ-Embrace.app/Contents/SharedSupport/Crash Pad.app"
codesign --force --options runtime --timestamp --sign "$EZ_EMBRACE_SIGN_IDENTITY" \
    --entitlements Resources/Embrace.entitlements "$output/EZ-Embrace.app"
codesign --verify --deep --strict --verbose=2 "$output/EZ-Embrace.app"
mkdir -p "$output/dmg-root"
ditto "$output/EZ-Embrace.app" "$output/dmg-root/EZ-Embrace.app"
cp LICENSE LICENSE.EmbraceNG "$output/dmg-root/"
cat > "$output/dmg-root/Read me.txt" <<EOF
EZ-Embrace ${version} local test candidate

Includes seeking, text size and bold preferences, uniform window scaling,
and the EmbraceNG custom parametric equalizer.

Signed with Developer ID. Not notarized. Release QA remains open.
Test this candidate on the intended macOS and audio hardware before use in a set.
Embrace and EmbraceNG license notices are included beside and inside the app.
EOF
ln -s /Applications "$output/dmg-root/Applications"
hdiutil create -volname 'EZ-Embrace candidate' -srcfolder "$output/dmg-root" \
    -format UDZO "$output/EZ-Embrace-${version}.dmg"
codesign --sign "$EZ_EMBRACE_SIGN_IDENTITY" --timestamp "$output/EZ-Embrace-${version}.dmg"
hdiutil verify "$output/EZ-Embrace-${version}.dmg"
shasum -a 256 "$output/EZ-Embrace.app/Contents/MacOS/EZ-Embrace" "$output/EZ-Embrace-${version}.dmg" > "$output/SHA256SUMS.txt"
