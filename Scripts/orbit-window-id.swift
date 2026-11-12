// Prints the CGWindowID of one of Orbit's on-screen windows. Reading window bounds and IDs needs no permission.
// Usage: orbit-window-id PID [panel|settings]
//        orbit-window-id --display    exits 3 with the reason when no window could be captured right now
// The panel floats (layer 3) unless "Keep above other windows" is off; Settings is an ordinary window (layer 0).
import CoreGraphics
import Foundation

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(status)
}

let arguments = CommandLine.arguments.dropFirst()

// While the display sleeps, the screen is locked or another user has the console, a launched app's windows are
// not composited, so waiting for one only ends in a timeout.
if arguments.first == "--display" {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
        fail("the main display is asleep", status: 3)
    }
    if session["CGSSessionScreenIsLocked"] as? Bool == true {
        fail("the screen is locked", status: 3)
    }
    if session[kCGSessionOnConsoleKey as String] as? Bool == false {
        fail("this login session is not on the console", status: 3)
    }
    exit(0)
}

guard let pid = arguments.first.flatMap(Int32.init) else {
    fail("usage: orbit-window-id PID [panel|settings] | --display", status: 2)
}
let kind = arguments.dropFirst().first ?? "panel"
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let candidates = windows.filter { window in
    guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
          let layer = window[kCGWindowLayer as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Double],
          (bounds["Width"] ?? 0) > 1
    else { return false }
    // The menu bar item lives at the status bar layer (25); it is never what we want here.
    return kind == "settings" ? layer == 0 && (bounds["Height"] ?? 0) > 200 : layer == 3 || layer == 0 && (bounds["Height"] ?? 0) < 600
}
guard let id = candidates.first?[kCGWindowNumber as String] as? Int else {
    fail("Orbit (pid \(pid)) has no \(kind) window", status: 1)
}
print(id)
