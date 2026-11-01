#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

version="4.5.0"
label="${RELEASE_LABEL:-$(date +%y%m%d-%H%M%S)}"
output="${OUTPUT_DIR:-builds/v4.5.0/mac/release-${label}}"
derived="$output/derived"
app="$output/EZ-Embrace.app"
package="$output/EZ-Embrace-${version}.pkg"
app_zip="$output/EZ-Embrace-${version}-notarization.zip"
application_identity="${EZ_EMBRACE_SIGN_IDENTITY:?Set EZ_EMBRACE_SIGN_IDENTITY to a Developer ID Application identity}"
installer_identity="${EZ_EMBRACE_INSTALLER_IDENTITY:?Set EZ_EMBRACE_INSTALLER_IDENTITY to a Developer ID Installer identity}"
notary_profile="${EZ_EMBRACE_NOTARY_PROFILE:-notary}"

if [[ -e "$output" ]]; then
    echo "Release output already exists: $output" >&2
    echo "Use a new RELEASE_LABEL or OUTPUT_DIR so prior evidence stays intact." >&2
    exit 1
fi

output_parent=$(dirname "$output")
mkdir -p "$output_parent"
available_kib=$(df -k "$output_parent" | awk 'END {print $4}')
# Recent universal release directories use about 350 MiB. Allow 512 MiB, then preserve 10 GiB.
if (( available_kib < 10 * 1024 * 1024 + 512 * 1024 )); then
    echo 'Insufficient free space for the release build and 10 GiB reserve.' >&2
    exit 1
fi

for tool in xcodebuild codesign pkgbuild pkgutil lipo ditto shasum xcrun spctl; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

security find-identity -v -p codesigning | grep -F "$application_identity" >/dev/null || {
    echo "Developer ID Application identity is unavailable: $application_identity" >&2
    exit 1
}
security find-certificate -a -c "$installer_identity" -p >/dev/null 2>&1 || {
    echo "Developer ID Installer certificate is unavailable: $installer_identity" >&2
    exit 1
}
xcrun notarytool history --keychain-profile "$notary_profile" --output-format json >/dev/null

mkdir -p "$output"
xcodebuild -project Embrace.xcodeproj -scheme Embrace -configuration Release \
    -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO \
    ARCHS='arm64 x86_64' build 2>&1 | tee "$output/build.log"

ditto "$derived/Build/Products/Release/EZ-Embrace.app" "$app"
mkdir -p "$app/Contents/Resources/Licenses"
cp LICENSE LICENSE.EmbraceNG "$app/Contents/Resources/Licenses/"

codesign --force --options runtime --timestamp --sign "$application_identity" \
    --entitlements Resources/Worker.entitlements "$app/Contents/XPCServices/EmbraceWorker.xpc"
codesign --force --options runtime --timestamp --sign "$application_identity" \
    --entitlements Resources/CrashPad.entitlements "$app/Contents/SharedSupport/Crash Pad.app"
codesign --force --options runtime --timestamp --sign "$application_identity" \
    --entitlements Resources/Embrace.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app" 2>&1 | tee "$output/codesign-verify.log"

architectures=$(lipo -archs "$app/Contents/MacOS/EZ-Embrace")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
    echo "Universal executable required; found: $architectures" >&2
    exit 1
}

ditto -c -k --keepParent "$app" "$app_zip"
xcrun notarytool submit "$app_zip" --keychain-profile "$notary_profile" --wait \
    --output-format json > "$output/app-notary-submit.json"
app_status=$(/usr/bin/plutil -extract status raw -o - "$output/app-notary-submit.json")
app_submission=$(/usr/bin/plutil -extract id raw -o - "$output/app-notary-submit.json")
xcrun notarytool log "$app_submission" --keychain-profile "$notary_profile" \
    "$output/app-notary-log.json"
[[ "$app_status" == "Accepted" ]] || {
    echo "App notarization failed: $app_status ($app_submission)" >&2
    exit 1
}
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app" 2>&1 | tee "$output/app-gatekeeper.log"

pkgbuild --component "$app" --install-location /Applications \
    --identifier com.ezscape.EZEmbrace.pkg --version "$version" \
    --sign "$installer_identity" "$package"
pkgutil --check-signature "$package" | tee "$output/package-signature.log"

xcrun notarytool submit "$package" --keychain-profile "$notary_profile" --wait \
    --output-format json > "$output/package-notary-submit.json"
package_status=$(/usr/bin/plutil -extract status raw -o - "$output/package-notary-submit.json")
package_submission=$(/usr/bin/plutil -extract id raw -o - "$output/package-notary-submit.json")
xcrun notarytool log "$package_submission" --keychain-profile "$notary_profile" \
    "$output/package-notary-log.json"
[[ "$package_status" == "Accepted" ]] || {
    echo "Package notarization failed: $package_status ($package_submission)" >&2
    exit 1
}
xcrun stapler staple "$package"
xcrun stapler validate "$package"
spctl --assess --type install --verbose=4 "$package" 2>&1 | tee "$output/package-gatekeeper.log"

shasum -a 256 "$app/Contents/MacOS/EZ-Embrace" "$app_zip" "$package" > "$output/SHA256SUMS.txt"
{
    printf 'git_commit=%s\n' "$(git rev-parse HEAD)"
    printf 'version=%s\n' "$version"
    printf 'architectures=%s\n' "$architectures"
    printf 'app_notarization_id=%s\n' "$app_submission"
    printf 'package_notarization_id=%s\n' "$package_submission"
    printf 'package=%s\n' "$package"
} > "$output/release-manifest.txt"

echo "Release package ready: $package"
