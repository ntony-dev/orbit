#!/bin/zsh
# Starts this checkout's Debug build as a child of this script, captures one of its windows by window ID, and
# quits exactly that process. Never moves the pointer, sends input, changes focus or touches any other Orbit.
# Usage: Scripts/screenshot.sh output.png [--window panel|settings] [launch arguments...]
#   Scripts/screenshot.sh /tmp/dark.png --demo --expanded --appearance dark --panel-anchor 1688,1017
#   Scripts/screenshot.sh /tmp/spotify.png --window settings --demo --settings spotify
# ORBIT_SCREENSHOT_TIMEOUT (seconds, default 45) bounds the wait for the window on a busy machine.
# Needs Screen Recording permission for the app running this script (System Settings > Privacy & Security >
# Screen & System Audio Recording), otherwise screencapture fails with "could not create image from window".
#
# The binary is executed directly, never through `open`: LaunchServices launches are not children of this
# script, so a launch it cannot see (or one LaunchServices delivers late, for example after the display wakes)
# outlives the script and leaves a demo panel on the user's screen. A direct child has a PID known at once, and
# Orbit is an accessory app that does not activate itself, so it starts without taking focus.
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

binary="$PWD/build/Build/Products/Debug/Orbit.app/Contents/MacOS/Orbit"
[[ -x $binary ]] || { echo "no Debug build at $binary; build it first" >&2; exit 1; }

# Compiled once rather than run with `swift` on every poll, which costs seconds of compiler time each call on a
# loaded machine.
helper="$PWD/build/Scripts/orbit-window-id"
if [[ ! -x $helper || Scripts/orbit-window-id.swift -nt $helper ]]; then
    mkdir -p "${helper:h}"
    swiftc -O Scripts/orbit-window-id.swift -o "$helper.$$"
    mv -f "$helper.$$" "$helper"
fi

if ! reason=$("$helper" --display 2>&1); then
    echo "not launching Orbit: $reason, so no window could be captured" >&2
    exit 1
fi

pid="" watchdog="" log=$(mktemp -t orbit-screenshot)

# Runs on every exit path, timeouts and failures included, and quits only the process this script started.
cleanup() {
    if [[ -n $pid ]] && kill -0 $pid 2>/dev/null; then
        kill $pid 2>/dev/null || true
        local deadline=$(( SECONDS + 5 ))
        while kill -0 $pid 2>/dev/null && (( SECONDS < deadline )); do sleep 0.1; done
        kill -9 $pid 2>/dev/null || true
    fi
    [[ -z $pid ]] || wait $pid 2>/dev/null || true
    [[ -z $watchdog ]] || kill $watchdog 2>/dev/null || true
    rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

"$binary" "$@" >"$log" 2>&1 &
pid=$!
# Covers the one path the trap cannot: this script being killed outright (SIGKILL), which would orphan Orbit.
script=$$
{ while kill -0 $script 2>/dev/null; do sleep 1; done; kill -9 $pid 2>/dev/null } &!
watchdog=$!

window_id=""
deadline=$(( SECONDS + timeout ))
while (( SECONDS < deadline )); do
    if ! kill -0 $pid 2>/dev/null; then
        wait $pid && status=0 || status=$?
        pid=""
        echo "Orbit exited with status $status before showing a $window window" >&2
        tail -n 20 "$log" >&2
        exit 1
    fi
    if ! reason=$("$helper" --display 2>&1); then
        echo "stopped waiting for Orbit (pid $pid): $reason" >&2
        exit 1
    fi
    window_id=$("$helper" $pid "$window" 2>/dev/null) && break
    sleep 0.25
done
if [[ -z $window_id ]]; then
    echo "Orbit (pid $pid) showed no $window window within ${timeout}s" >&2
    exit 1
fi

# The window exists before the UI has finished its entrance animation and loaded artwork.
sleep 2.5
screencapture -x -o -l "$window_id" "$output"
front=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null | sed -n 's/.*pid = \([0-9]*\).*/\1/p' || true)
[[ $front != $pid ]] || echo "warning: Orbit (pid $pid) became the frontmost app during the capture" >&2
echo "$output"
