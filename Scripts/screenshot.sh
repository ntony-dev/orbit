#!/bin/zsh
# Launches this checkout's Debug build in the background, captures one of its windows by window ID, and quits it.
# Never moves the pointer, sends input, changes focus or touches any other Orbit instance.
# Usage: Scripts/screenshot.sh output.png [--window panel|settings] [launch arguments...]
#   Scripts/screenshot.sh /tmp/dark.png --demo --expanded --appearance dark
#   Scripts/screenshot.sh /tmp/spotify.png --window settings --demo --settings spotify
# Needs Screen Recording permission for the app running this script (System Settings > Privacy & Security >
# Screen & System Audio Recording), otherwise screencapture fails with "could not create image from window".
set -euo pipefail
cd "$(dirname "$0")/.."

output=${1:?usage: Scripts/screenshot.sh output.png [--window panel|settings] [launch arguments...]}
shift
window=panel
if [[ ${1:-} == --window ]]; then
    window=${2:?--window needs panel or settings}
    shift 2
fi

app="$PWD/build/Build/Products/Debug/Orbit.app"
before=$(pgrep -f "$app/Contents/MacOS/Orbit" || true)
# -n starts a separate instance even if another copy of Orbit is running; -g keeps it in the background.
open -n -g "$app" --args "$@"
pid=""
for _ in {1..50}; do
    pid=$(pgrep -n -f "$app/Contents/MacOS/Orbit" || true)
    [[ -n $pid && $before != *$pid* ]] && break
    pid=""
    sleep 0.1
done
[[ -n $pid ]] || { echo "Orbit did not start" >&2; exit 1; }
trap 'kill $pid 2>/dev/null || true' EXIT

sleep 3
window_id=$(swift Scripts/orbit-window-id.swift "$pid" "$window")
screencapture -x -o -l "$window_id" "$output"
echo "$output"
