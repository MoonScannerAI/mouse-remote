import SwiftUI
import UIKit

@MainActor
struct ContentView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var modifiers: ModifierState
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.pointerSpeed) private var pointerSpeed: Double = SettingsDefault.pointerSpeed
    @AppStorage(SettingsKey.scrollSpeed) private var scrollSpeed: Double = SettingsDefault.scrollSpeed
    @AppStorage(SettingsKey.naturalScroll) private var naturalScroll: Bool = SettingsDefault.naturalScroll
    @AppStorage(SettingsKey.showKeys) private var showKeys: Bool = SettingsDefault.showKeys

    @State private var showSettings = false
    @State private var keyboardActive = false

    var body: some View {
        VStack(spacing: 10) {
            StatusBarView(showSettings: $showSettings)

            toolbarRow

            VStack(spacing: 8) {
                ModifierRow()
                if showKeys {
                    SpecialKeysPanel()
                }
            }

            HStack(spacing: 10) {
                HoldButton(title: "Left",
                           onDown: {
                               Haptics.click()
                               ble.setButton(.left, down: true)
                           },
                           onUp: { ble.setButton(.left, down: false) })
                HoldButton(title: "Right",
                           onDown: {
                               Haptics.click()
                               ble.setButton(.right, down: true)
                           },
                           onUp: { ble.setButton(.right, down: false) })
            }
            .frame(height: 76)

            // Touchpad sits last so it ends up directly above the system keyboard.
            Touchpad(ble: ble,
                     pointerSpeed: pointerSpeed,
                     scrollSpeed: scrollSpeed,
                     naturalScroll: naturalScroll)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Palette.pageBackground.ignoresSafeArea())
        .background(
            KeyboardCapture(isActive: $keyboardActive, ble: ble, modifiers: modifiers)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        )
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear { showKeyboardSoon() }
        .onChange(of: ble.state, initial: true) { _, newState in
            UIApplication.shared.isIdleTimerDisabled = (newState == .connected)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ble.appDidBecomeActive()
                showKeyboardSoon()
            case .background:
                ble.appDidEnterBackground()
            default:
                break
            }
        }
    }

    /// Raise the system keyboard on launch / return to foreground. Deferred so the hidden
    /// text view is attached to a window before it is asked to become first responder.
    private func showKeyboardSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            keyboardActive = true
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showKeys.toggle() }
            } label: {
                Label(showKeys ? "Hide Keys" : "Special Keys",
                      systemImage: showKeys ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(KeyButtonStyle())

            Button {
                keyboardActive.toggle()
            } label: {
                Label(keyboardActive ? "Hide Keyboard" : "Keyboard",
                      systemImage: keyboardActive ? "keyboard.chevron.compact.down" : "keyboard")
            }
            .buttonStyle(KeyButtonStyle(fill: keyboardActive ? Palette.accent : Palette.keyFill,
                                        stroke: keyboardActive ? Palette.accent : Palette.keyBorder,
                                        textColor: keyboardActive ? Palette.onAccent : Palette.text))
        }
    }
}
