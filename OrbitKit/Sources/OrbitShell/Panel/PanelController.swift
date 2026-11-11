import AppKit
import OrbitCore
import OrbitEngine
import OrbitUI
import SwiftUI

@MainActor
final class PanelController: PanelHost {
    private let state = PanelState()
    private let panel: FloatingPanel
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var clickMonitors: [Any] = []
    private var observations: [Task<Void, Never>] = []
    private lazy var escapeHotKey = EscapeHotKey { [weak self] in self?.state.collapse() }

    init(stores: OrbitStores, preferences: Preferences) {
        panel = FloatingPanel(contentRect: .zero)
        let hostingView = NSHostingView(rootView: PanelRootView(stores: stores, panel: state, host: self, preferences: preferences))
        // The UI sizes the canvas explicitly through setCanvasSize; the hosting view must not resize the window.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.onCancel = { [state] in state.collapse() }
        observeKeyStatus()
        observeExpansion()
    }

    // The panel starts as a zero-size frame at `anchorPoint`. Because every resize keeps the anchored corner
    // fixed, that point becomes the pill's corner and the canvas grows away from it toward the screen centre.
    // Defaults to just inside the bottom-right corner of the main screen.
    func show(anchoredAt anchorPoint: CGPoint? = nil, expanded: Bool = false) {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let inset: CGFloat = 24
        let point = anchorPoint ?? CGPoint(x: visible.maxX - inset, y: visible.minY + inset)
        panel.setFrame(NSRect(origin: point, size: .zero), display: false)
        updateAnchor()
        panel.orderFrontRegardless()
        if expanded { state.expand() }
    }

    func setCanvasSize(_ size: CGSize) {
        panel.setFrame(PanelGeometry.resize(panel.frame, to: size, keeping: state.anchor), display: true)
        if !state.isExpanded { updateAnchor() }
    }

    func beginDrag() {
        dragStart = (panel.lastMouseDownLocation ?? NSEvent.mouseLocation, panel.frame.origin)
        state.isDragging = true
        updateDrag()
    }

    func updateDrag() {
        guard let dragStart else { return }
        panel.setFrameOrigin(PanelGeometry.dragOrigin(
            startOrigin: dragStart.origin,
            pressLocation: dragStart.mouse,
            mouse: NSEvent.mouseLocation
        ))
    }

    func endDrag() {
        updateDrag()
        dragStart = nil
        state.isDragging = false
        if !state.isExpanded { updateAnchor() }
    }

    func setAcceptsKeyboardInput(_ accepts: Bool) {
        panel.acceptsKey = accepts
        if accepts {
            panel.makeKey()
        } else if panel.isKeyWindow {
            // Orbit is never the active app, so dropping the panel out of the window list hands key status
            // straight back to the frontmost app's window; re-ordering it in the same pass avoids any flicker.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func updateAnchor() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        state.anchor = PanelGeometry.anchor(forCanvas: panel.frame, in: screen.visibleFrame)
    }

    private func observeKeyStatus() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            let updates = center.notifications(named: name, object: panel)
            observations.append(Task { [weak self] in
                for await _ in updates.map({ _ in () }) {
                    self?.keyStatusChanged()
                }
            })
        }
    }

    private func observeExpansion() {
        let state = state
        observations.append(Task { [weak self] in
            for await expanded in Observations({ state.isExpanded }) {
                self?.expansionChanged(expanded)
            }
        })
    }

    private func keyStatusChanged() {
        state.isKeyWindow = panel.isKeyWindow
        updateEscapeHotKey()
    }

    private func expansionChanged(_ expanded: Bool) {
        if expanded {
            installClickMonitors()
        } else {
            removeClickMonitors()
            setAcceptsKeyboardInput(false)
        }
        updateEscapeHotKey()
    }

    // When the panel is key, Escape reaches it through cancelOperation, and the UI may want it first.
    private func updateEscapeHotKey() {
        if state.isExpanded, !panel.isKeyWindow {
            escapeHotKey.register()
        } else {
            escapeHotKey.unregister()
        }
    }

    private func installClickMonitors() {
        guard clickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.state.collapse() }
        }) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.state.collapse() }
            }
            return event
        }) {
            clickMonitors.append(local)
        }
    }

    private func removeClickMonitors() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }
}
