#!/bin/zsh
# Launches this checkout's Debug build in the background, captures one of its windows by window ID, and quits it.
# Never moves the pointer, sends input, changes focus or touches any other Orbit instance.
# Usage: Scripts/screenshot.sh output.png [--window panel|settings] [launch arguments...]
#   Scripts/screenshot.sh /tmp/dark.png --demo --expanded --appearance dark
#   Scripts/screenshot.sh /tmp/spotify.png --window settings --demo --settings spotify
# ORBIT_SCREENSHOT_TIMEOUT (seconds, default 45) bounds the wait for the window on a busy machine.
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
timeout=${ORBIT_SCREENSHOT_TIMEOUT:-45}

app="$PWD/build/Build/Products/Debug/Orbit.app"
# Orbit ignores arguments it does not know. The tag names exactly the instance this run launched, so cleanup
# never touches another Orbit, including one launched by a concurrent run of this script.
tag="screenshot-$$-$RANDOM$RANDOM"
pattern="$app/Contents/MacOS/Orbit .*--screenshot-tag $tag"
launched=false

# Runs on every exit path, timeouts and failures included. `open` returns only once the process exists, but a
# loaded machine can register it late, so cleanup keeps looking briefly before giving up.
cleanup() {
    $launched || return 0
    local deadline=$(( SECONDS + 10 )) killed=false
    while (( SECONDS < deadline )); do
        local pids=$(pgrep -f "$pattern" || true)
        if [[ -n $pids ]]; then
            kill ${=pids} 2>/dev/null || true
            killed=true
        elif $killed; then
            return 0
        fi
        sleep 0.2
    done
    pids=$(pgrep -f "$pattern" || true)
    [[ -z $pids ]] || kill -9 ${=pids} 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

launched=true
# -n starts a separate instance even if another copy of Orbit is running; -g keeps it in the background.
open -n -g "$app" --args "$@" --screenshot-tag "$tag"

pid="" window_id=""
deadline=$(( SECONDS + timeout ))
while (( SECONDS < deadline )); do
    [[ -n $pid ]] || pid=$(pgrep -f "$pattern" | head -1 || true)
    if [[ -n $pid ]]; then
        window_id=$(swift Scripts/orbit-window-id.swift "$pid" "$window" 2>/dev/null || true)
        [[ -n $window_id ]] && break
    fi
    sleep 0.25
done
if [[ -z $window_id ]]; then
    echo "Orbit ${pid:+(pid $pid) }showed no $window window within ${timeout}s" >&2
    exit 1
fi

# The window exists before the UI has finished its entrance animation and loaded artwork.
sleep 2.5
screencapture -x -o -l "$window_id" "$output"
echo "$output"
