// Prints the CGWindowID of Orbit's on-screen panel. Reading window bounds and IDs needs no permission.
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
guard let orbit = windows.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "Orbit" }),
      let id = orbit[kCGWindowNumber as String] as? Int
else {
    FileHandle.standardError.write(Data("Orbit has no on-screen window\n".utf8))
    exit(1)
}
print(id)
