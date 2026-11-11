import OrbitCore
import SwiftUI

// Moves the window through the host so the shell can follow the global mouse location; the gesture's own
// translation drifts as the window moves under it. High priority means a drag never also fires a button, and the
// minimum distance means a plain click is never mistaken for a drag.
struct PanelDragGesture: ViewModifier {
    let host: any PanelHost
    @State private var isDragging = false

    func body(content: Content) -> some View {
        content.highPriorityGesture(
            DragGesture(minimumDistance: OrbitTokens.Motion.dragThreshold, coordinateSpace: .global)
                .onChanged { _ in
                    if isDragging {
                        host.updateDrag()
                    } else {
                        isDragging = true
                        host.beginDrag()
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    host.endDrag()
                }
        )
    }
}

extension View {
    func panelDragGesture(_ host: any PanelHost) -> some View {
        modifier(PanelDragGesture(host: host))
    }
}
