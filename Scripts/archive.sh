#!/bin/zsh
# Builds Orbit.app from a clean Release build, signs it ad hoc and zips it into dist/Orbit-<version>.zip.
# Usage: Scripts/archive.sh
#
# The archive needs no paid Apple Developer account, so it is not notarized. Gatekeeper therefore blocks the
# first launch of a downloaded copy. To open it once you trust the source: open Orbit.app, dismiss the warning,
# then choose Open Anyway in System Settings > Privacy & Security. Never disable Gatekeeper for this. Because
# ad-hoc signatures differ between builds, macOS asks again for Automation and Keychain access after an update.
#
# The Spotify Client ID from Config/Local.xcconfig, if any, is built in; users can always enter their own in
# Settings > Spotify. Any signing identity in Local.xcconfig is overridden here so the result is always ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

derived=build/release
products="$derived/Build/Products/Release"
rm -rf "$derived"

# Compiler diagnostics start with a file path, so the filter matches them anywhere in the line. xcodebuild's own
# status decides success, because a bundle can exist even when a later build phase failed.
set +e
xcodebuild \
    -project Orbit.xcodeproj \
    -scheme Orbit \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived" \
    -clonedSourcePackagesDirPath build/SourcePackages \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    clean build \
    | grep -E "^\*\*|: (error|warning): "
build_status=${pipestatus[1]}
set -e
(( build_status == 0 )) || { echo "Release build failed" >&2; exit 1; }

app="$products/Orbit.app"
[[ -d $app ]] || { echo "Release build produced no Orbit.app" >&2; exit 1; }
codesign --verify --deep --strict "$app"

# PlistBuddy reads the file itself; `defaults read` can answer from a cache of an earlier build at this path.
info="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info")
client_id=$(/usr/libexec/PlistBuddy -c "Print :SpotifyClientID" "$info" 2>/dev/null || true)
revision=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
[[ -z $(git status --porcelain 2>/dev/null) ]] || revision="$revision with uncommitted changes"

mkdir -p dist
archive="dist/Orbit-$version.zip"
rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"

echo "Built $archive from $revision ($(lipo -archs "$app/Contents/MacOS/Orbit"))"
echo "Signature: $(codesign -dv "$app" 2>&1 | grep -E '^Signature=')"
echo "Spotify Client ID: ${client_id:+built in}${client_id:-none, users enter their own}"
shasum -a 256 "$archive"
