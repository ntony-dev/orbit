import AppKit
import OrbitCore
import OrbitEngine
import OrbitUI
import SwiftUI

// Owns the floating canvas: where it sits, when it is on screen, and when it holds keyboard focus.
//
// Focus follows the popover model. Opening Orbit (clicking the pill, a shortcut, the menu bar) makes the
// non-activating panel key without activating the app, so Escape, arrow keys and typing reach Orbit while it is
// visibly open. Collapsing hands key status straight back to the user's app. The collapsed pill never takes key,
// so its playback buttons leave focus where it was, and Orbit never listens for keys it does not visibly own.
@MainActor
final class PanelController: PanelHost {
    let state = PanelState()
    private let panel: FloatingPanel
    private let preferences: Preferences
    private let account: AccountStore
    private var positions: [String: SavedPanelPosition]
    private var displayID: String?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var clickMonitor: Any?
    private var observations: [Task<Void, Never>] = []
    private var fullscreenCheck: Task<Void, Never>?
    private var isFullscreenAppFrontmost = false
    private var isPresentedOnDemand = false
    // Set by the --expanded launch argument, so a test run never takes keyboard focus from the user, even if the
    // UI asks for it on appear. Cleared by the first real click in the panel or the next deliberate opening.
    private var suppressesFocus = false
    // Set by --panel-anchor, which holds the pill exactly where asked until the user drags it.
    private var isPinned = false

    init(stores: OrbitStores, preferences: Preferences) {
        self.preferences = preferences
        account = stores.account
        positions = preferences.remembersPosition ? preferences.savedPositions : [:]
        displayID = preferences.remembersPosition ? preferences.panelDisplayID : nil
        panel = FloatingPanel(contentRect: .zero)
        let hostingView = NSHostingView(rootView: PanelRootView(stores: stores, panel: state, host: self, preferences: preferences))
        // The UI sizes the canvas explicitly through setCanvasSize; the hosting view must not resize the window.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.onCancel = { [state] in state.collapse() }
        // Runs before the panel handles the click, so a click on an open but unfocused panel also makes it key.
        panel.onMouseDown = { [weak self] in
            guard let self else { return }
            suppressesFocus = false
            if state.isExpanded { panel.acceptsKey = true }
        }
    }

    // `pinnedAt` is the --panel-anchor launch argument: the canvas corner nearest to that point is pinned there
    // and nothing is restored or remembered from it.
    func start(pinnedAt point: CGPoint?, expanded: Bool) {
        panel.setFrame(CGRect(origin: .zero, size: collapsedCanvasSize), display: false)
        if let point {
            pin(at: point)
        } else {
            restore()
        }
        applyLevel()
        observe()
        updateVisibility()
        if expanded {
            suppressesFocus = true
            state.expand()
        }
    }

    // Opens Orbit at `destination` for the user, including when the pill is hidden, and gives it keyboard focus.
    func present(_ destination: PanelDestination = .player) {
        suppressesFocus = false
        if !visibility(presentedOnDemand: false).showsPanel { isPresentedOnDemand = true }
        updateVisibility()
        state.expand(to: destination)
        takeKeyboardFocus()
    }

    func toggle() {
        if state.isExpanded, panel.isVisible {
            state.collapse()
        } else {
            present()
        }
    }

    func resetPosition() {
        state.collapse()
        positions = [:]
        displayID = nil
        persistPositions()
        restore()
    }

    func setCanvasSize(_ size: CGSize) {
        panel.setFrame(PanelGeometry.resize(panel.frame, to: size, keeping: state.anchor), display: true)
        guard isCollapsedAtRest else { return }
        // The UI reports the collapsed size only after the collapse animation, which is when an on-demand
        // presentation can go away without cutting the morph short.
        if isPresentedOnDemand {
            isPresentedOnDemand = false
            updateVisibility()
        }
        settle(movedByUser: false)
    }

    func beginDrag() {
        isPinned = false
        dragStart = (panel.lastMouseDownLocation ?? NSEvent.mouseLocation, panel.frame.origin)
        state.isDragging = true
        updateDrag()
    }

    func updateDrag() {
        guard let dragStart else { return }
        let mouse = NSEvent.mouseLocation
        var origin = PanelGeometry.dragOrigin(startOrigin: dragStart.origin, pressLocation: dragStart.mouse, mouse: mouse)
        if preferences.snapsToEdges, !preferences.docksAtTopCenter,
           let display = NSScreen.layouts.first(where: { $0.visibleFrame.contains(mouse) }) {
            let surface = Self.surface(ofCanvas: CGRect(origin: origin, size: panel.frame.size))
            let snapped = PanelPlacement.snap(surface, in: display.visibleFrame)
            origin.x += snapped.minX - surface.minX
            origin.y += snapped.minY - surface.minY
        }
        panel.setFrameOrigin(origin)
    }

    func endDrag() {
        updateDrag()
        dragStart = nil
        state.isDragging = false
        if isCollapsedAtRest {
            settle(movedByUser: true)
        } else {
            keepExpandedSurfaceOnScreen()
        }
        scheduleFullscreenCheck()
    }

    // While Orbit is open the panel keeps key status whatever the UI asks, so Escape still reaches it after a
    // search field gives up focus; key status goes back to the user's app when the panel collapses.
    func setAcceptsKeyboardInput(_ accepts: Bool) {
        if accepts {
            takeKeyboardFocus()
        } else if !state.isExpanded {
            returnKeyboardFocus()
        }
    }

    private var collapsedCanvasSize: CGSize {
        OrbitTokens.Size.canvas(for: OrbitTokens.Size.pill(preferences.pillSize))
    }

    // Collapsed and no longer animating, so the canvas is exactly the pill plus its margin.
    private var isCollapsedAtRest: Bool {
        !state.isExpanded && panel.frame.size == collapsedCanvasSize
    }

    private var placementOptions: PlacementOptions {
        PlacementOptions(snapsToEdges: preferences.snapsToEdges, docksAtTopCenter: preferences.docksAtTopCenter)
    }

    private static func surface(ofCanvas canvas: CGRect) -> CGRect {
        canvas.insetBy(dx: OrbitTokens.Size.canvasMargin, dy: OrbitTokens.Size.canvasMargin)
    }

    // Where the pill is, or will be once an expansion collapses back into its anchored corner.
    private var pillSurface: CGRect {
        Self.surface(ofCanvas: PanelGeometry.resize(panel.frame, to: collapsedCanvasSize, keeping: state.anchor))
    }

    private func movePill(to surface: CGRect) {
        let current = pillSurface
        panel.setFrameOrigin(CGPoint(
            x: panel.frame.minX + surface.minX - current.minX,
            y: panel.frame.minY + surface.minY - current.minY
        ))
    }

    // The anchor decides which way the next expansion grows, so it changes only while the pill is at rest.
    private func updateAnchor(for surface: CGRect, in display: DisplayLayout) {
        guard isCollapsedAtRest else { return }
        state.anchor = PanelPlacement.anchor(for: surface, in: display.visibleFrame)
    }

    private func pin(at point: CGPoint) {
        isPinned = true
        let visible = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? .zero
        state.anchor = PanelGeometry.anchor(forCanvas: CGRect(origin: point, size: .zero), in: visible)
        panel.setFrame(PanelGeometry.resize(CGRect(origin: point, size: .zero), to: collapsedCanvasSize, keeping: state.anchor), display: false)
    }

    private func restore() {
        guard let restored = PanelPlacement.restore(
            size: OrbitTokens.Size.pill(preferences.pillSize),
            saved: positions,
            preferredDisplayID: displayID,
            displays: NSScreen.layouts,
            options: placementOptions
        ) else { return }
        movePill(to: restored.surface)
        updateAnchor(for: restored.surface, in: restored.display)
    }

    // Applies clamping, snapping or docking where the pill now is. Only a move by the user changes which display
    // the pill belongs to; otherwise a fallback onto the main display while the user's display is disconnected
    // would make the pill forget to return there.
    private func settle(movedByUser: Bool) {
        guard !isPinned else { return }
        let pill = pillSurface
        guard let display = PanelPlacement.display(for: pill, in: NSScreen.layouts) else { return }
        let settled = PanelPlacement.settle(pill, in: display.visibleFrame, options: placementOptions)
        movePill(to: settled)
        updateAnchor(for: settled, in: display)
        guard movedByUser || display.id == displayID else { return }
        displayID = display.id
        positions[display.id] = PanelPlacement.savedPosition(of: settled, in: display.visibleFrame)
        persistPositions()
    }

    private func keepExpandedSurfaceOnScreen() {
        let surface = Self.surface(ofCanvas: panel.frame)
        guard let display = PanelPlacement.display(for: surface, in: NSScreen.layouts) else { return }
        let clamped = PanelPlacement.clamp(surface, to: display.visibleFrame)
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + clamped.minX - surface.minX, y: panel.frame.minY + clamped.minY - surface.minY))
    }

    private func persistPositions() {
        guard preferences.remembersPosition else { return }
        if preferences.savedPositions != positions { preferences.savedPositions = positions }
        if preferences.panelDisplayID != displayID { preferences.panelDisplayID = displayID }
    }

    private func applyLevel() {
        panel.level = preferences.alwaysOnTop ? .floating : .normal
    }

    private func visibility(presentedOnDemand: Bool) -> PanelVisibility {
        PanelVisibility(
            isPillVisible: preferences.isPillVisible,
            hidesInFullscreen: preferences.hidesInFullscreen,
            isFullscreenAppFrontmost: isFullscreenAppFrontmost,
            hidesWhenSpotifyQuits: preferences.hidesWhenSpotifyQuits,
            isSpotifyRunning: account.isSpotifyRunning,
            isPresentedOnDemand: presentedOnDemand
        )
    }

    private func updateVisibility() {
        if visibility(presentedOnDemand: isPresentedOnDemand).showsPanel {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            state.collapse()
            panel.orderOut(nil)
            // A collapse animation does not run in a hidden window, so the canvas is shrunk here instead.
            panel.setFrame(PanelGeometry.resize(panel.frame, to: collapsedCanvasSize, keeping: state.anchor), display: false)
        }
    }

    private func takeKeyboardFocus() {
        guard !suppressesFocus else { return }
        panel.acceptsKey = true
        if panel.isVisible { panel.makeKey() }
    }

    private func returnKeyboardFocus() {
        panel.acceptsKey = false
        guard panel.isKeyWindow else { return }
        // Orbit is never the active app, so dropping the panel out of the window list hands key status straight
        // back to the frontmost app's window; re-ordering it in the same pass avoids any flicker.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func observe() {
        let state = state
        let preferences = preferences
        let account = account
        observations.append(Task { [weak self] in
            for await expanded in Observations({ state.isExpanded }) {
                self?.expansionChanged(expanded)
            }
        })
        observations.append(Task { [weak self] in
            for await _ in Observations({ preferences.alwaysOnTop }) {
                self?.applyLevel()
            }
        })
        observations.append(Task { [weak self] in
            for await _ in Observations({
                (preferences.isPillVisible, preferences.hidesWhenSpotifyQuits, account.isSpotifyRunning)
            }) {
                self?.updateVisibility()
            }
        })
        observations.append(Task { [weak self] in
            for await _ in Observations({ preferences.hidesInFullscreen }) {
                self?.scheduleFullscreenCheck()
            }
        })
        observations.append(Task { [weak self] in
            for await _ in Observations({ (preferences.snapsToEdges, preferences.docksAtTopCenter) }) {
                self?.settle(movedByUser: false)
            }
        })
        observations.append(Task { [weak self] in
            for await remembers in Observations({ preferences.remembersPosition }) {
                self?.remembersPositionChanged(remembers)
            }
        })
        observe(NotificationCenter.default, NSWindow.didResignKeyNotification, object: panel) { $0.keyStatusChanged() }
        observe(NotificationCenter.default, NSWindow.didBecomeKeyNotification, object: panel) { $0.keyStatusChanged() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) {
            $0.restore()
            $0.scheduleFullscreenCheck()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.scheduleFullscreenCheck() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.scheduleFullscreenCheck() }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: NSWindow? = nil,
        perform action: @escaping (PanelController) -> Void
    ) {
        let notifications = center.notifications(named: name, object: object).map { _ in () }
        observations.append(Task { [weak self] in
            for await _ in notifications {
                guard let self else { return }
                action(self)
            }
        })
    }

    private func remembersPositionChanged(_ remembers: Bool) {
        if remembers {
            persistPositions()
        } else {
            preferences.savedPositions = [:]
            preferences.panelDisplayID = nil
        }
    }

    private func keyStatusChanged() {
        state.isKeyWindow = panel.isKeyWindow
        // Focus moved to another app (Cmd-Tab, a click the outside-click monitor did not see) while Orbit was
        // open for typing: close like a popover. Focus moving to another Orbit window, such as Settings, does not.
        if !panel.isKeyWindow, state.isExpanded, panel.acceptsKey, NSApp.keyWindow == nil {
            state.collapse()
        }
    }

    private func expansionChanged(_ expanded: Bool) {
        if expanded {
            installClickMonitor()
            takeKeyboardFocus()
        } else {
            removeClickMonitor()
            returnKeyboardFocus()
        }
    }

    // Clicks in other apps collapse the expanded panel. Clicks in Orbit's own windows (Settings, the menu bar
    // item) do not, so appearance changes can be watched live. Transparent canvas areas pass clicks through to
    // the app below, so they count as outside clicks too. Mouse monitors need no permission.
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.collapse() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    // Space switches animate, so the window list is read again once the new Space has settled.
    private func scheduleFullscreenCheck() {
        fullscreenCheck?.cancel()
        guard preferences.hidesInFullscreen,
              let layout = PanelPlacement.display(for: pillSurface, in: NSScreen.layouts),
              let displayID = NSScreen.screen(for: layout)?.displayID
        else {
            fullscreenChanged(false)
            return
        }
        let displayBounds = CGDisplayBounds(displayID)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        fullscreenCheck = Task { [weak self] in
            for delay in [Duration.zero, .milliseconds(800)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                let windows = await Task.detached(priority: .utility) { FullscreenDetection.onScreenWindows() }.value
                self?.fullscreenChanged(FullscreenDetection.isCovered(displayBounds: displayBounds, by: windows, excluding: ownPID))
            }
        }
    }

    private func fullscreenChanged(_ covered: Bool) {
        guard covered != isFullscreenAppFrontmost else { return }
        isFullscreenAppFrontmost = covered
        updateVisibility()
    }
}
