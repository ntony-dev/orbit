@testable import OrbitShell
import Testing

struct PanelFocusPolicyTests {
    private let staysOpen = PanelFocusPolicy(collapsesOnOutsideClick: false)
    private let collapses = PanelFocusPolicy(collapsesOnOutsideClick: true)

    @Test func byDefaultAnOutsideClickOnlyHandsTheKeyboardBack() {
        #expect(staysOpen.outsideClick(panelIsKey: true) == .resignKey)
        // Already unfocused (the click went to an app that took key itself): nothing left to do.
        #expect(staysOpen.outsideClick(panelIsKey: false) == .none)
    }

    @Test func byDefaultSwitchingAppsLeavesThePanelOpen() {
        #expect(staysOpen.keyMovedToAnotherApp() == .none)
    }

    @Test func collapsingOnOutsideClickKeepsThePopoverBehaviour() {
        #expect(collapses.outsideClick(panelIsKey: true) == .collapse)
        #expect(collapses.outsideClick(panelIsKey: false) == .collapse)
        #expect(collapses.keyMovedToAnotherApp() == .collapse)
    }

    @Test func aHiddenPanelComesBackOpenUnlessTheUserHidThePill() {
        #expect(!staysOpen.collapsesWhenHidden(byHidingThePill: false))
        #expect(staysOpen.collapsesWhenHidden(byHidingThePill: true))
        #expect(collapses.collapsesWhenHidden(byHidingThePill: false))
    }

    // The rule that matters most: whatever the setting, an outside click never leaves Orbit holding key status.
    @Test func neverKeepsKeyStatusAfterAnOutsideClick() {
        for policy in [staysOpen, collapses] {
            #expect(policy.outsideClick(panelIsKey: true) != .none)
        }
    }
}
