import AppKit
import OrbitCore
import OrbitUI
import SwiftUI

struct AppearancePane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Style", selection: $preferences.glassPreset) {
                    ForEach(GlassPreset.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                Text(preferences.glassPreset.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LabeledContent("Background opacity") {
                    Slider(value: $preferences.backgroundOpacity, in: 0...1) {
                        Text("Background opacity")
                    } minimumValueLabel: {
                        Image(systemName: "circle.dotted")
                    } maximumValueLabel: {
                        Image(systemName: "circle.fill")
                    }
                    .labelsHidden()
                }
            } header: {
                Text("Glass")
            } footer: {
                Text("macOS Liquid Glass comes in two variants, clear and regular, and Orbit can't change how strongly it blurs. Background opacity sets a layer Orbit draws behind the glass to keep text readable. Reduce Transparency and Increase Contrast in Accessibility settings take precedence.")
                    .settingsFootnote()
            }

            Section {
                AccentPicker(accent: $preferences.accent)
            } header: {
                Text("Accent")
            } footer: {
                Text("Used for selection, progress and focus. Album artwork supplies the rest of the color.")
                    .settingsFootnote()
            }

            Section("Pill") {
                Picker("Size", selection: $preferences.pillSize) {
                    ForEach(PillSize.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                Toggle("Show artwork", isOn: $preferences.showsArtwork)
            }

            Section {
                Toggle("Reduce animation", isOn: $preferences.reducesAnimation)
            } footer: {
                Text("Orbit also follows Reduce Motion in Accessibility settings.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AccentPicker: View {
    @Binding var accent: AccentChoice

    var body: some View {
        LabeledContent("Color") {
            HStack(spacing: OrbitTokens.Spacing.s) {
                ForEach(AccentChoice.presets, id: \.self) { choice in
                    swatch(choice)
                }
                ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .overlay {
                        if case .custom = accent { SelectionRing() }
                    }
                    .help("Custom color")
            }
        }
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        Button {
            accent = choice
        } label: {
            Circle()
                .fill(OrbitTokens.Palette.accent(choice))
                .overlay(Circle().strokeBorder(.separator))
                .frame(width: SettingsLayout.swatch, height: SettingsLayout.swatch)
                .overlay { if accent == choice { SelectionRing() } }
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(accent == choice ? .isSelected : [])
    }

    private var customColor: Binding<Color> {
        Binding {
            OrbitTokens.Palette.accent(accent)
        } set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            accent = .custom(RGBColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
        }
    }
}

private struct SelectionRing: View {
    var body: some View {
        Circle()
            .strokeBorder(Color.primary, lineWidth: 2)
            .padding(-OrbitTokens.Spacing.xs)
            .accessibilityHidden(true)
    }
}

extension AppearanceMode {
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

extension GlassPreset {
    var title: String {
        switch self {
        case .clear: "Clear"
        case .balanced: "Balanced"
        case .tinted: "Tinted"
        }
    }

    // Matches OrbitTokens.Material.glass: the presets pick a native variant and optionally add Orbit's tint.
    var summary: String {
        switch self {
        case .clear: "The native clear glass, for the most see-through pill."
        case .balanced: "The native regular glass, frostier and easier to read over busy windows."
        case .tinted: "The native regular glass with a wash of your accent color."
        }
    }
}

extension PillSize {
    var title: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        }
    }
}

extension AccentChoice {
    var title: String {
        switch self {
        case .neutral: "Neutral"
        case .mint: "Mint"
        case .ice: "Ice"
        case .amber: "Amber"
        case .lavender: "Lavender"
        case .custom: "Custom"
        }
    }
}

enum SettingsLayout {
    static let paneWidth: CGFloat = 520
    static let swatch: CGFloat = 20
    // The Spotify pane scrolls; the others size to their content.
    static let spotifyPaneHeight: CGFloat = 640
}

extension Text {
    func settingsFootnote() -> some View {
        font(.footnote).foregroundStyle(.secondary)
    }
}
