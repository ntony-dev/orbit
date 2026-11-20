#!/bin/zsh
# Builds Release with the signing identity from Config/Local.xcconfig, installs it as Orbit.app in a folder
# (/Applications by default) and keeps a copy in dist/Orbit.app. Given an alias folder, it also writes a Finder
# alias named Orbit there.
# Usage: Scripts/install-local.sh [--destination folder] [--quit-running] [alias-folder]
#
# It refuses to replace a copy that is running unless --quit-running is passed, which quits that copy first.
# For your own Mac. A stable identity keeps macOS's Automation and Keychain grants across rebuilds, so this
# refuses an ad-hoc signature; Scripts/archive.sh makes the shareable ad-hoc disk image.
set -euo pipefail
cd "$(dirname "$0")/.."

destination=/Applications
quit_running=false
while (( $# )); do
    case $1 in
        --destination) destination=${2:?--destination needs a folder}; shift 2 ;;
        --quit-running) quit_running=true; shift ;;
        -*) echo "Unknown option $1" >&2; exit 1 ;;
        *) break ;;
    esac
done
alias_folder=${1:-}
[[ -d $destination ]] || { echo "No folder at $destination" >&2; exit 1; }
[[ -z $alias_folder || -d $alias_folder ]] || { echo "No folder at $alias_folder" >&2; exit 1; }

derived=build/signed
app="$derived/Build/Products/Release/Orbit.app"
installed="${destination:A}/Orbit.app"
running="^$installed/Contents/MacOS/Orbit( |\$)"

# Replacing the bundle under a running copy would leave it executing deleted code, so it is checked up front and
# again just before the copy.
check_running() {
    local pids=$(pgrep -f "$running" || true)
    [[ -n $pids ]] || return 0
    if ! $quit_running; then
        echo "$installed is running (pid ${pids//$'\n'/ }). Quit it, or pass --quit-running." >&2
        exit 1
    fi
    echo "Quitting the running copy (pid ${pids//$'\n'/ })"
    kill ${=pids}
    for _ in {1..40}; do
        pgrep -f "$running" >/dev/null || return 0
        sleep 0.25
    done
    echo "The running copy did not quit" >&2
    exit 1
}
$quit_running || check_running

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

check_running
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
