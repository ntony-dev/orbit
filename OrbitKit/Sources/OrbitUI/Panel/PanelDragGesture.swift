import OrbitCore
import SwiftUI

// Moves the window through the host so the shell can follow the global mouse location; the gesture's own
// translation drifts as the window moves under it. High priority means a drag never also fires a button, and the
// minimum distance means a plain click is never mistaken for a drag.
private struct PanelDragGesture: ViewModifier {
    @Environment(\.panelHost) private var host
    @State private var isDragging = false

    func body(content: Content) -> some View {
        content.highPriorityGesture(
            DragGesture(minimumDistance: PanelGeometry.dragThreshold, coordinateSpace: .global)
                .onChanged { _ in
                    guard let host else { return }
                    if isDragging {
                        host.updateDrag()
                    } else {
                        isDragging = true
                        host.beginDrag()
                    }
                }
                .onEnded { _ in
                    guard isDragging else { return }
                    isDragging = false
                    host?.endDrag()
                }
        )
    }
}

extension View {
    func panelDraggable() -> some View {
        modifier(PanelDragGesture())
    }
}
