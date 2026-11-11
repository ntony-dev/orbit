import KeyboardShortcuts
import SwiftUI

struct ShortcutsPane: View {
    let shortcuts: GlobalShortcuts

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        KeyboardShortcuts.Recorder(for: shortcuts.name(for: action))
                    }
                }
            } footer: {
                Text("Shortcuts work from any app. Each one is off until you record a combination for it.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}
