#!/bin/zsh
# Regenerates the README and user guide screenshots in docs/images from the Debug build in demo mode.
# Usage: Scripts/readme-images.sh [--panel-anchor X,Y]
#
# Each screen is captured twice through Scripts/screenshot.sh: over the debug "plain" backdrop, and with no
# backdrop, whose transparent surroundings give the panel's exact shape. Scripts/compose-readme-image.swift cuts
# the panels out and lays them on one wallpaper. Captures come out at the backing scale of the display the panel
# opens on, so run this with the anchor on a Retina display for sharp 2x images.
set -euo pipefail
cd "${0:A:h}/.."

anchor=""
if [[ ${1:-} == --panel-anchor ]]; then
    anchor=${2:?--panel-anchor needs X,Y}
    shift 2
fi
(( $# == 0 )) || { echo "Usage: Scripts/readme-images.sh [--panel-anchor X,Y]" >&2; exit 1; }

# By default the panel opens in the top-right corner of the main display, clear of whatever is being worked on.
read -r main_anchor scale < <(swift - "$anchor" <<'EOF'
import AppKit
let requested = CommandLine.arguments.dropFirst().first.flatMap { $0.isEmpty ? nil : $0 }
let main = NSScreen.main!
let point: CGPoint
if let requested {
    let parts = requested.split(separator: ",").compactMap { Double($0) }
    point = CGPoint(x: parts[0], y: parts[1])
} else {
    point = CGPoint(x: main.frame.maxX - 40, y: main.frame.maxY - 100)
}
let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? main
print("\(Int(point.x)),\(Int(point.y)) \(Int(screen.backingScaleFactor))")
EOF
)
(( scale >= 2 )) || echo "warning: the panel opens on a ${scale}x display, so the images will not be sharp on Retina screens" >&2

shots=$(mktemp -d -t orbit-readme)
trap 'rm -rf "$shots"' EXIT

base=(--demo --appearance dark --panel-anchor "$main_anchor")
capture() {
    local name=$1; shift
    Scripts/screenshot.sh "$shots/$name.png" "${base[@]}" "$@" --ui-backdrop plain >/dev/null
    Scripts/screenshot.sh "$shots/$name-mask.png" "${base[@]}" "$@" >/dev/null
    echo "captured $name"
}
shot() { print -r -- "$shots/$1.png:$shots/$1-mask.png" }

capture pill
capture player --expanded --ui-screen player
capture library --expanded --ui-screen library --ui-shelf
capture queue --expanded --ui-screen queue
capture devices --expanded --ui-screen devices
capture search --expanded --ui-screen library --ui-query night
capture playlist --expanded --ui-screen playlist:pl-night-drive

compose=(swift Scripts/compose-readme-image.swift)
$compose docs/images/overview.png --scale $scale --column "$(shot pill),$(shot player)" --column "$(shot library)"
$compose docs/images/player-drawers.png --scale $scale --column "$(shot queue)" --column "$(shot devices)"
$compose docs/images/library-browsing.png --scale $scale --column "$(shot search)" --column "$(shot playlist)"
