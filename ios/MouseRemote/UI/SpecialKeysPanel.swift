import SwiftUI
import UIKit

struct KeyButtonStyle: ButtonStyle {
    var fill: Color = Color(white: 0.17)
    var stroke: Color = .clear
    var height: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Color(white: 0.34) : fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(stroke, lineWidth: 2)
            )
            .contentShape(Rectangle())
    }
}

enum KeyPage: String, CaseIterable, Identifiable {
    case nav = "Nav"
    case function = "F1–F12"
    case shortcuts = "Shortcuts"
    case media = "Media"

    var id: String { rawValue }
}

/// Sticky modifiers row + paged special keys.
@MainActor
struct SpecialKeysPanel: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var modifiers: ModifierState
    @State private var page: KeyPage = .nav
    @State private var altTabHeld = false

    private let columns6 = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    private let columns4 = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(spacing: 8) {
            modifierRow
            Picker("Keys", selection: $page) {
                ForEach(KeyPage.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch page {
                case .nav: navPage
                case .function: functionPage
                case .shortcuts: shortcutsPage
                case .media: mediaPage
                }
            }
            .frame(height: 94, alignment: .top)
        }
    }

    // MARK: Modifier row: Win, Esc, Tab, Ctrl, Alt, Shift

    private var modifierRow: some View {
        LazyVGrid(columns: columns6, spacing: 6) {
            modifierButton(.win)
            Button("Esc") { tapKey(HIDKey.escape) }.buttonStyle(KeyButtonStyle())
            Button("Tab") { tapKey(HIDKey.tab) }.buttonStyle(KeyButtonStyle())
            modifierButton(.ctrl)
            modifierButton(.alt)
            modifierButton(.shift)
        }
    }

    private func modifierButton(_ modifier: StickyModifier) -> some View {
        let mode = modifiers.mode(modifier)
        let fill: Color
        let stroke: Color
        switch mode {
        case .off:
            fill = Color(white: 0.17); stroke = .clear
        case .once:
            fill = Color(white: 0.17); stroke = .accentColor
        case .locked:
            fill = .accentColor; stroke = .accentColor
        }
        return Button(modifier.title) {
            Haptics.key()
            modifiers.tap(modifier)
        }
        .buttonStyle(KeyButtonStyle(fill: fill, stroke: stroke))
        .accessibilityValue(mode == .off ? "Off" : (mode == .once ? "Next key" : "Locked"))
    }

    // MARK: Pages

    private var navPage: some View {
        LazyVGrid(columns: columns6, spacing: 6) {
            Button("Home") { tapKey(HIDKey.home) }.buttonStyle(KeyButtonStyle())
            Button("PgUp") { tapKey(HIDKey.pageUp) }.buttonStyle(KeyButtonStyle())
            Button("↑") { tapKey(HIDKey.up) }.buttonStyle(KeyButtonStyle())
            Button("PgDn") { tapKey(HIDKey.pageDown) }.buttonStyle(KeyButtonStyle())
            Button("Del") { tapKey(HIDKey.delete) }.buttonStyle(KeyButtonStyle())
            Button("⌫") { tapKey(HIDKey.backspace) }.buttonStyle(KeyButtonStyle())

            Button("End") { tapKey(HIDKey.end) }.buttonStyle(KeyButtonStyle())
            Button("←") { tapKey(HIDKey.left) }.buttonStyle(KeyButtonStyle())
            Button("↓") { tapKey(HIDKey.down) }.buttonStyle(KeyButtonStyle())
            Button("→") { tapKey(HIDKey.right) }.buttonStyle(KeyButtonStyle())
            Button("Start") { shortcut(HIDModifier.leftGUI, 0) }.buttonStyle(KeyButtonStyle())
            Button("⏎") { tapKey(HIDKey.enter) }.buttonStyle(KeyButtonStyle())
        }
    }

    private var functionPage: some View {
        LazyVGrid(columns: columns6, spacing: 6) {
            ForEach(1...12, id: \.self) { n in
                Button("F\(n)") { tapKey(HIDKey.function(n)) }.buttonStyle(KeyButtonStyle())
            }
        }
    }

    private var shortcutsPage: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                // Alt+Tab: Alt stays down while held; "Tab ▸" cycles; releasing sends Alt up.
                HoldButton(title: altTabHeld ? "Alt (held)" : "Alt+Tab",
                           fontSize: 15,
                           color: UIColor(white: 0.17, alpha: 1),
                           pressedColor: UIColor.tintColor,
                           onDown: altTabBegin,
                           onUp: altTabEnd)
                    .frame(height: 44)
                HoldButton(title: "◂ Tab",
                           fontSize: 15,
                           onDown: { altTabCycle(reverse: true) })
                    .frame(height: 44)
                HoldButton(title: "Tab ▸",
                           fontSize: 15,
                           onDown: { altTabCycle(reverse: false) })
                    .frame(height: 44)
                Button("Win+Tab") { shortcut(HIDModifier.leftGUI, HIDKey.tab) }.buttonStyle(KeyButtonStyle())
            }
            LazyVGrid(columns: columns6, spacing: 6) {
                Button("Win+D") { shortcut(HIDModifier.leftGUI, HIDKey.d) }.buttonStyle(KeyButtonStyle())
                Button("Win+L") { shortcut(HIDModifier.leftGUI, HIDKey.l) }.buttonStyle(KeyButtonStyle())
                Button("Ctrl+C") { shortcut(HIDModifier.leftCtrl, HIDKey.c) }.buttonStyle(KeyButtonStyle())
                Button("Ctrl+V") { shortcut(HIDModifier.leftCtrl, HIDKey.v) }.buttonStyle(KeyButtonStyle())
                Button("Ctrl+Z") { shortcut(HIDModifier.leftCtrl, HIDKey.z) }.buttonStyle(KeyButtonStyle())
                Button("Ctrl+A") { shortcut(HIDModifier.leftCtrl, HIDKey.a) }.buttonStyle(KeyButtonStyle())
            }
        }
    }

    private var mediaPage: some View {
        LazyVGrid(columns: columns4, spacing: 6) {
            Button("Vol −") { media(ConsumerUsage.volumeDown) }.buttonStyle(KeyButtonStyle())
            Button("Vol +") { media(ConsumerUsage.volumeUp) }.buttonStyle(KeyButtonStyle())
            Button("Mute") { media(ConsumerUsage.mute) }.buttonStyle(KeyButtonStyle())
            Button("Play/Pause") { media(ConsumerUsage.playPause) }.buttonStyle(KeyButtonStyle())
            Button("Bright −") { media(ConsumerUsage.brightnessDown) }.buttonStyle(KeyButtonStyle())
            Button("Bright +") { media(ConsumerUsage.brightnessUp) }.buttonStyle(KeyButtonStyle())
            Button("Prev") { media(ConsumerUsage.previousTrack) }.buttonStyle(KeyButtonStyle())
            Button("Next") { media(ConsumerUsage.nextTrack) }.buttonStyle(KeyButtonStyle())
        }
    }

    // MARK: Actions

    /// Single key, with any sticky modifiers applied.
    private func tapKey(_ key: UInt8) {
        Haptics.key()
        ble.keyTap(modifiers: modifiers.consume(), key: key)
    }

    /// Fixed shortcut; sticky modifiers are left untouched.
    private func shortcut(_ mods: UInt8, _ key: UInt8) {
        Haptics.key()
        ble.keyTap(modifiers: mods, key: key)
    }

    private func media(_ usage: UInt16) {
        Haptics.key()
        ble.consumer(usage)
    }

    private func altTabBegin() {
        Haptics.key()
        altTabHeld = true
        ble.keySet(modifiers: HIDModifier.leftAlt, key: 0, down: true)
        pressTab(extraModifiers: 0)
    }

    private func altTabCycle(reverse: Bool) {
        Haptics.key()
        if altTabHeld {
            pressTab(extraModifiers: reverse ? HIDModifier.leftShift : 0)
        } else {
            // Not in Alt+Tab: behave like a normal (Shift+)Tab key.
            ble.keyTap(modifiers: reverse ? HIDModifier.leftShift : 0, key: HIDKey.tab)
        }
    }

    private func altTabEnd() {
        guard altTabHeld else { return }
        altTabHeld = false
        ble.keySet(modifiers: HIDModifier.leftAlt, key: 0, down: false)
    }

    /// Press and release Tab while keeping Alt held (KEY_SET only releases what it names).
    private func pressTab(extraModifiers: UInt8) {
        ble.keySet(modifiers: HIDModifier.leftAlt | extraModifiers, key: HIDKey.tab, down: true)
        ble.keySet(modifiers: extraModifiers, key: HIDKey.tab, down: false)
    }
}
