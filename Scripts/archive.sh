#!/bin/zsh
# Builds Orbit.app from a clean Release build, signs it ad hoc and packages it with Orbit's license and the
# third-party notices (App/Acknowledgements.txt, also shown in the About panel).
# Usage: Scripts/archive.sh [--friends]
#
# Without options it writes the public disk image, dist/Orbit-<version>.dmg, with no Spotify Client ID built in,
# so everyone who downloads it enters their own in Settings > Spotify. The build fails if a Client ID ends up in it.
#
# --friends writes dist/Orbit-<version>-friends.dmg for the people on your Spotify app's User Management list. It
# builds in the Client ID from the SPOTIFY_CLIENT_ID environment variable or, when that is unset, from
# SPOTIFY_CLIENT_ID in Config/Local.xcconfig, so they only have to click Connect Spotify. The image carries your
# Client ID: send it privately and never attach it to a public release.
#
# Either way, any signing identity in Local.xcconfig is overridden so the result is always ad hoc: a development
# certificate's signature names your team and must not leave your Mac. The build needs no paid Apple Developer
# account, so it is not notarized and Gatekeeper blocks the first launch of a downloaded copy until the user
# chooses Open Anyway in System Settings > Privacy & Security. Never disable Gatekeeper for this. Because ad-hoc
# signatures differ between builds, macOS asks again for Automation and Keychain access after an update.
set -euo pipefail
setopt extended_glob
cd "$(dirname "$0")/.."

friends=false
case "$*" in
    "") ;;
    --friends) friends=true ;;
    *) echo "Usage: Scripts/archive.sh [--friends]" >&2; exit 1 ;;
esac

client_id=
if $friends; then
    client_id=${SPOTIFY_CLIENT_ID:-}
    origin="The SPOTIFY_CLIENT_ID environment variable"
    if [[ -z $client_id && -f Config/Local.xcconfig ]]; then
        # The last assignment wins in an xcconfig, and // starts a comment anywhere on a line.
        client_id=$(sed -nE 's|//.*||; s/^[[:space:]]*SPOTIFY_CLIENT_ID[[:space:]]*=[[:space:]]*([^[:space:]]*)[[:space:]]*$/\1/p' \
            Config/Local.xcconfig | tail -n 1)
        origin="SPOTIFY_CLIENT_ID in Config/Local.xcconfig"
    fi
    if [[ -z $client_id ]]; then
        echo "No Spotify Client ID for the friends build. Set SPOTIFY_CLIENT_ID in the environment or in Config/Local.xcconfig." >&2
        exit 1
    fi
    [[ $client_id =~ '^[0-9A-Fa-f]{32}$' ]] || { echo "$origin is not a Spotify Client ID (32 hexadecimal characters)" >&2; exit 1; }
fi

derived=build/release
products="$derived/Build/Products/Release"
rm -rf "$derived"
mkdir -p "$derived"

# The Client ID goes in through a file rather than the command line, which xcodebuild echoes and ps shows. An
# -xcconfig file outranks Orbit.xcconfig and Local.xcconfig, so the public build is empty whatever Local.xcconfig says.
overrides="$derived/Overrides.xcconfig"
(umask 077; print -r -- "SPOTIFY_CLIENT_ID = $client_id" > "$overrides")

# Compiler diagnostics start with a file path, so the filter matches them anywhere in the line. xcodebuild's own
# status decides success, because a bundle can exist even when a later build phase failed. Command-line settings
# outrank every xcconfig, including conditional ones such as CODE_SIGN_IDENTITY[sdk=macosx*].
set +e
xcodebuild \
    -project Orbit.xcodeproj \
    -scheme Orbit \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived" \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -xcconfig "$overrides" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build \
    | grep -E "^\*\*|: (error|warning): "
build_status=${pipestatus[1]}
set -e
rm -f "$overrides"
(( build_status == 0 )) || { echo "Release build failed" >&2; exit 1; }

app="$products/Orbit.app"
[[ -d $app ]] || { echo "Release build produced no Orbit.app" >&2; exit 1; }
codesign --verify --deep --strict "$app"

# A copy that leaves this Mac must not name the owner's team or let other processes attach to it.
for code in "$app" $app/Contents/(Frameworks|PlugIns|XPCServices)/*(N); do
    details=$(codesign -dv "$code" 2>&1)
    [[ $details == *$'\nSignature=adhoc'* && $details == *$'\nTeamIdentifier=not set'* ]] \
        || { echo "${code:t} is not signed ad hoc" >&2; exit 1; }
done
[[ $(codesign -dv "$app" 2>&1) =~ $'\nCodeDirectory [^\n]*flags=0x[0-9a-f]+\\([^)]*runtime' ]] \
    || { echo "Orbit.app lacks the hardened runtime" >&2; exit 1; }
[[ $(codesign -d --entitlements - --xml "$app" 2>/dev/null) != *get-task-allow* ]] \
    || { echo "Orbit.app has the get-task-allow entitlement" >&2; exit 1; }

# PlistBuddy reads the file itself; `defaults read` can answer from a cache of an earlier build at this path.
info="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info")
built_in=$(/usr/libexec/PlistBuddy -c "Print :SpotifyClientID" "$info" 2>/dev/null || true)
if $friends; then
    [[ $built_in == "$client_id" ]] || { echo "Orbit.app does not carry the Client ID it was given" >&2; exit 1; }
else
    [[ -z $built_in ]] || { echo "Orbit.app has a Spotify Client ID built in; the public archive must not" >&2; exit 1; }
fi
revision=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
[[ -z $(git status --porcelain 2>/dev/null) ]] || revision="$revision with uncommitted changes"

# Every dependency's license must ship with the app. The notices file is written by hand, so this fails the
# archive when a package is added or its license changes without the file being updated.
notices=App/Acknowledgements.txt
cmp -s "$notices" "$app/Contents/Resources/Acknowledgements.txt" || { echo "Orbit.app lacks $notices" >&2; exit 1; }
for checkout in build/SourcePackages/checkouts/*(/); do
    license=( $checkout/(#i)licen[cs]e*(N.) )
    (( ${#license} )) || { echo "No license file in ${checkout:t}" >&2; exit 1; }
    [[ $(<$notices) == *"$(<${license[1]})"* ]] || { echo "$notices does not reproduce ${license[1]}" >&2; exit 1; }
done

staging="$derived/Orbit-$version"
mkdir -p "$staging" dist
ditto "$app" "$staging/Orbit.app"
cp -X LICENSE "$staging/LICENSE.txt"
cp -X "$notices" "$staging/Acknowledgements.txt"

# The Applications link gives the usual drag-to-install window. Finder lays the icons out itself, since arranging
# them would mean scripting Finder.
if $friends; then output="dist/Orbit-$version-friends.dmg"; else output="dist/Orbit-$version.dmg"; fi
ln -s /Applications "$staging/Applications"
rm -f "$output"
hdiutil create -quiet -volname "Orbit $version" -srcfolder "$staging" -fs HFS+ -format UDZO "$output"
hdiutil verify -quiet "$output"

echo "Built $output from $revision ($(lipo -archs "$app/Contents/MacOS/Orbit"))"
echo "Signature: $(codesign -dv "$app" 2>&1 | grep -E '^Signature=')"
if $friends; then
    echo "Spotify Client ID: yours, built in. Send this image only to people on your app's User Management list."
else
    echo "Spotify Client ID: none, users enter their own"
fi
shasum -a 256 "$output"
