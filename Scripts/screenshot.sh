#!/bin/zsh
# Captures Orbit's panel by window ID, without moving the pointer, sending input or changing focus.
# Usage: Scripts/screenshot.sh output.png [launch arguments...]
# With launch arguments, (re)launches the Debug build in the background first, e.g.
#   Scripts/screenshot.sh /tmp/dark.png --demo --expanded --appearance dark
# Needs Screen Recording permission for the app running this script (System Settings > Privacy & Security >
# Screen & System Audio Recording), otherwise screencapture fails with "could not create image from window".
set -euo pipefail
cd "$(dirname "$0")/.."

output=${1:?usage: Scripts/screenshot.sh output.png [launch arguments...]}
shift

if (( $# > 0 )); then
    pkill -x Orbit 2>/dev/null || true
    open -g build/Build/Products/Debug/Orbit.app --args "$@"
    sleep 3
fi

window_id=$(swift Scripts/orbit-window-id.swift)
screencapture -x -o -l "$window_id" "$output"
echo "$output"
