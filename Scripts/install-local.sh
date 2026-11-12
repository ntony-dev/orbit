#!/bin/zsh
# Builds Release with the signing identity from Config/Local.xcconfig, installs it to /Applications/Orbit.app and
# keeps a copy in dist/Orbit.app. Given a folder, it also writes a Finder alias named Orbit there.
# Usage: Scripts/install-local.sh [alias-folder]
#
# For your own Mac. A stable identity keeps macOS's Automation and Keychain grants across rebuilds, so this
# refuses an ad-hoc signature; Scripts/archive.sh makes the shareable ad-hoc zip.
set -euo pipefail
cd "$(dirname "$0")/.."

alias_folder=${1:-}
[[ -z $alias_folder || -d $alias_folder ]] || { echo "No folder at $alias_folder" >&2; exit 1; }

derived=build/signed
app="$derived/Build/Products/Release/Orbit.app"
installed=/Applications/Orbit.app

set +e
xcodebuild \
    -project Orbit.xcodeproj \
    -scheme Orbit \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived" \
    -clonedSourcePackagesDirPath build/SourcePackages \
    clean build \
    | grep -E "^\*\*|: (error|warning): "
build_status=${pipestatus[1]}
set -e
(( build_status == 0 )) || { echo "Release build failed" >&2; exit 1; }

codesign --verify --deep --strict "$app"
requirement=$(codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => //p')
if [[ $requirement != *"anchor apple generic"* ]]; then
    echo "Orbit.app is signed ad hoc. Set a signing identity in Config/Local.xcconfig (see Local.example.xcconfig)." >&2
    exit 1
fi

rm -rf dist/Orbit.app
mkdir -p dist
ditto "$app" dist/Orbit.app

# Replacing the bundle under a running copy would leave it executing deleted code.
pattern="^$installed/Contents/MacOS/Orbit( |\$)"
pids=$(pgrep -f "$pattern" || true)
if [[ -n $pids ]]; then
    echo "Quitting the running copy (pid ${pids//$'\n'/ })"
    kill ${=pids}
    for _ in {1..40}; do
        pgrep -f "$pattern" >/dev/null || break
        sleep 0.25
    done
    ! pgrep -f "$pattern" >/dev/null || { echo "The running copy did not quit" >&2; exit 1; }
fi

rm -rf "$installed"
ditto "$app" "$installed"
codesign --verify --deep --strict "$installed"
echo "Installed $installed ($(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$installed/Contents/Info.plist"))"

# An alias rather than a second copy: two bundles with one bundle ID confuse launch at login and the grants.
if [[ -n $alias_folder ]]; then
    alias_file="${alias_folder:A}/Orbit"
    if [[ -e $alias_file || -L $alias_file ]]; then
        [[ $(file -b "$alias_file") == "MacOS Alias file" ]] || { echo "$alias_file exists and is not an alias" >&2; exit 1; }
        rm "$alias_file"
    fi
    swift - "$installed" "$alias_file" <<'EOF'
import Foundation
let target = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
try URL.writeBookmarkData(data, to: URL(fileURLWithPath: CommandLine.arguments[2]))
EOF
    [[ $(file -b "$alias_file") == "MacOS Alias file" ]] || { echo "Could not write an alias at $alias_file" >&2; exit 1; }
    echo "Alias $alias_file -> $installed"
fi
