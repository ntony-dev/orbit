import OrbitCore
@testable import OrbitUI
import SwiftUI
import Testing

struct PanelKeyRouterTests {
    private let player = PanelKeyContext(screen: .player)
    private let list = PanelKeyContext(screen: .list)
    private let emptyFilter = PanelKeyContext(screen: .list, field: .empty)
    private let typedFilter = PanelKeyContext(screen: .list, field: .filled)

    private func route(_ key: KeyEquivalent, _ modifiers: EventModifiers = [], in context: PanelKeyContext) -> PanelKeyAction {
        PanelKeyRouter.action(for: key, modifiers: modifiers, in: context)
    }

    @Test func playerKeepsSpotifyShortcuts() {
        #expect(route(.space, in: player) == .playback(.togglePlayback))
        #expect(route(.leftArrow, in: player) == .playback(.seek(by: -PlayerKeyCommand.seekStep)))
        #expect(route(.rightArrow, [.numericPad, .function], in: player) == .playback(.seek(by: PlayerKeyCommand.seekStep)))
        #expect(route(.rightArrow, .command, in: player) == .playback(.nextTrack))
        #expect(route(.upArrow, .command, in: player) == .playback(.changeVolume(by: PlayerKeyCommand.volumeStep)))
        #expect(route(.upArrow, in: player) == .ignored)
    }

    @Test func aFocusedFieldTypesSpaceAndMovesItsCaretWithArrows() {
        for context in [emptyFilter, typedFilter] {
            #expect(route(.space, in: context) == .textEditing)
            #expect(route("a", in: context) == .textEditing)
            #expect(route(.leftArrow, in: context) == .textEditing)
            #expect(route(.rightArrow, in: context) == .textEditing)
            #expect(route(.leftArrow, .command, in: context) == .textEditing)
            #expect(route(.rightArrow, [.command, .shift], in: context) == .textEditing)
            #expect(route(.upArrow, .command, in: context) == .textEditing)
            #expect(route(.delete, in: context) == .textEditing)
        }
    }

    @Test func aFieldAboveAListStillMovesAndPlaysTheSelection() {
        #expect(route(.downArrow, in: typedFilter) == .moveSelection(by: 1))
        #expect(route(.upArrow, in: emptyFilter) == .moveSelection(by: -1))
        #expect(route(.return, in: typedFilter) == .activateSelection)
        #expect(route(.downArrow, .shift, in: typedFilter) == .textEditing)
    }

    @Test func listArrowsMoveTheSelectionAndNeverSeek() {
        #expect(route(.downArrow, in: list) == .moveSelection(by: 1))
        #expect(route(.upArrow, [.numericPad, .function], in: list) == .moveSelection(by: -1))
        #expect(route(.return, in: list) == .activateSelection)
        #expect(route(.rightArrow, in: list) == .openSelection)
        #expect(route(.leftArrow, in: list) == .ignored)
        #expect(route(.leftArrow, in: PanelKeyContext(screen: .other)) == .ignored)
    }

    @Test func playbackShortcutsWorkOnListsWhenNoFieldHasFocus() {
        #expect(route(.space, in: list) == .playback(.togglePlayback))
        #expect(route(.leftArrow, .command, in: list) == .playback(.previousTrack))
        #expect(route(.downArrow, .command, in: list) == .playback(.changeVolume(by: -PlayerKeyCommand.volumeStep)))
        #expect(route(.space, in: PanelKeyContext(screen: .other)) == .playback(.togglePlayback))
    }

    @Test func escapeClearsAFieldThenStepsBackAFieldOrNot() {
        #expect(route(.escape, in: typedFilter) == .clearField)
        #expect(route(.escape, in: emptyFilter) == .dismissLayer)
        #expect(route(.escape, in: list) == .dismissLayer)
        #expect(route(.escape, in: player) == .dismissLayer)
        #expect(route(.escape, .shift, in: player) == .ignored)
    }

    @Test func commandCommaOpensSettingsFromEveryScreen() {
        for context in [player, list, emptyFilter, typedFilter, PanelKeyContext(screen: .other)] {
            #expect(route(",", .command, in: context) == .openSettings)
        }
        #expect(route(",", in: typedFilter) == .textEditing)
        #expect(route(",", [.command, .option], in: player) == .ignored)
    }

    @Test func eachActionHasExactlyOneOwner() {
        #expect(PanelKeyAction.textEditing.owner == .field)
        #expect(PanelKeyAction.clearField.owner == .field)
        #expect(PanelKeyAction.moveSelection(by: 1).owner == .list)
        #expect(PanelKeyAction.activateSelection.owner == .list)
        #expect(PanelKeyAction.dismissLayer.owner == .panel)
        #expect(PanelKeyAction.playback(.togglePlayback).owner == .panel)
        #expect(PanelKeyAction.openSettings.owner == .panel)
    }

    @MainActor
    @Test func screensDeclareWhoOwnsTheArrows() {
        let navigator = PanelNavigator()
        #expect(navigator.keyScreen == .player)
        navigator.show(.picker)
        #expect(navigator.keyScreen == .list)
        navigator.showLibrary(.queue)
        #expect(navigator.keyScreen == .other)
        navigator.showLibrary(.liked)
        #expect(navigator.keyScreen == .list)
        navigator.show(.player)
        navigator.push(.devices)
        #expect(navigator.keyScreen == .other)
    }

    @MainActor
    @Test func aFieldLeavingDuringATransitionDoesNotClearItsSuccessor() {
        let navigator = PanelNavigator()
        let outgoing = UUID(), incoming = UUID()
        navigator.setTextFieldFocus(.filled, owner: outgoing)
        navigator.setTextFieldFocus(.empty, owner: incoming)
        navigator.setTextFieldFocus(nil, owner: outgoing)
        #expect(navigator.textFieldFocus == .empty)
        navigator.setTextFieldFocus(nil, owner: incoming)
        #expect(navigator.textFieldFocus == nil)
    }
}
