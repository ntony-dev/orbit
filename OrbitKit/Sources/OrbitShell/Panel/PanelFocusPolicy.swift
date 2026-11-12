// What the open panel does when the user turns to something else. By default it stays open and on top and only
// hands keyboard focus back, so it collapses only when the user collapses it; with "Collapse when clicking
// outside" on it closes like a popover, as it always did. Either way it never keeps key status, and so never
// takes a keystroke, once the user has gone to another app.
struct PanelFocusPolicy: Equatable, Sendable {
    var collapsesOnOutsideClick: Bool

    enum Response: Equatable, Sendable {
        case collapse
        // Stay open, and hand key status back to the app the user went to.
        case resignKey
        case none
    }

    // A click in another app, on the desktop, or on a transparent part of Orbit's canvas while the panel is open.
    func outsideClick(panelIsKey: Bool) -> Response {
        if collapsesOnOutsideClick { return .collapse }
        return panelIsKey ? .resignKey : .none
    }

    // Key status went to another app without a click Orbit saw: Command-Tab, Mission Control, a shortcut that
    // activated an app. Focus moving to another Orbit window, such as Settings, never collapses.
    func keyMovedToAnotherApp() -> Response {
        collapsesOnOutsideClick ? .collapse : .none
    }

    // Whether an open panel collapses when a rule hides it (full screen, Spotify quitting). Otherwise it comes back
    // open once the rule lets it show again. Turning the pill off is the user closing Orbit, so that collapses.
    func collapsesWhenHidden(byHidingThePill: Bool) -> Bool {
        collapsesOnOutsideClick || byHidingThePill
    }
}
