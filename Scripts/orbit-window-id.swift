// Prints the CGWindowID of one of Orbit's on-screen windows. Reading window bounds and IDs needs no permission.
// Usage: swift Scripts/orbit-window-id.swift PID [panel|settings]
// The panel floats (layer 3) unless "Keep above other windows" is off; Settings is an ordinary window (layer 0).
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard let pid = arguments.first.flatMap(Int32.init) else {
    FileHandle.standardError.write(Data("usage: orbit-window-id.swift PID [panel|settings]\n".utf8))
    exit(2)
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
    FileHandle.standardError.write(Data("Orbit (pid \(pid)) has no \(kind) window\n".utf8))
    exit(1)
}
print(id)
