import SwiftUI
import UIKit

struct KeyButtonStyle: ButtonStyle {
    var fill: Color = Palette.keyFill
    var stroke: Color = Palette.keyBorder
    var textColor: Color = Palette.text
    var height: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Palette.keyPressed : fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(stroke, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
    }
}

enum KeyPage: String, CaseIterable, Identifiable {
    case function = "F1–F12"
    case shortcuts = "Shortcuts"

    var id: String { rawValue }
}

private let keyColumns6 = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

/// Sticky modifiers row (Win, Esc, Tab, Ctrl, Alt, Shift); always visible.
@MainActor
struct ModifierRow: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var modifiers: ModifierState

    var body: some View {
        LazyVGrid(columns: keyColumns6, spacing: 6) {
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
        let text: Color
        switch mode {
        case .off:
            fill = Palette.keyFill; stroke = Palette.keyBorder; text = Palette.text
        case .once:
            fill = Palette.keyFill; stroke = Palette.accent; text = Palette.text
        case .locked:
            fill = Palette.accent; stroke = Palette.accent; text = Palette.onAccent
        }
        return Button(modifier.title) {
            Haptics.key()
            modifiers.tap(modifier)
        }
        .buttonStyle(KeyButtonStyle(fill: fill, stroke: stroke, textColor: text))
        .accessibilityValue(mode == .off ? "Off" : (mode == .once ? "Next key" : "Locked"))
    }

    /// Single key, with any sticky modifiers applied.
    private func tapKey(_ key: UInt8) {
        Haptics.key()
        ble.keyTap(modifiers: modifiers.consume(), key: key)
    }
}

/// Paged special keys (F1-F12, shortcuts).
@MainActor
struct SpecialKeysPanel: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var modifiers: ModifierState
    @State private var page: KeyPage = .function
    @State private var altTabHeld = false

    private let columns6 = keyColumns6

    var body: some View {
        VStack(spacing: 8) {
            Picker("Keys", selection: $page) {
                ForEach(KeyPage.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch page {
                case .function: functionPage
                case .shortcuts: shortcutsPage
                }
            }
            .frame(height: 94, alignment: .top)
        }
    }

    // MARK: Pages

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
                           pressedColor: UIColor.tintColor,
                           pressedTextColor: Palette.uiOnAccent,
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
