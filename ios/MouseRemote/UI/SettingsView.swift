import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.pointerSpeed) private var pointerSpeed: Double = SettingsDefault.pointerSpeed
    @AppStorage(SettingsKey.pointerAcceleration) private var pointerAcceleration: Bool = SettingsDefault.pointerAcceleration
    @AppStorage(SettingsKey.scrollSpeed) private var scrollSpeed: Double = SettingsDefault.scrollSpeed
    @AppStorage(SettingsKey.naturalScroll) private var naturalScroll: Bool = SettingsDefault.naturalScroll
    @AppStorage(SettingsKey.haptics) private var haptics: Bool = SettingsDefault.haptics

    @State private var confirmForget = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Pointer speed: \(pointerSpeed, specifier: "%.1f")×")
                        Slider(value: $pointerSpeed, in: 0.3...3.0, step: 0.1)
                    }
                    Toggle("Acceleration", isOn: $pointerAcceleration)
                } header: {
                    Text("Pointer")
                } footer: {
                    Text("Faster swipes move the cursor further. Turn off if Windows \"Enhance pointer precision\" is on, so acceleration isn't applied twice.")
                }

                Section("Scrolling") {
                    VStack(alignment: .leading) {
                        Text("Scroll speed: \(scrollSpeed, specifier: "%.1f")×")
                        Slider(value: $scrollSpeed, in: 0.3...3.0, step: 0.1)
                    }
                    Toggle("Natural scrolling", isOn: $naturalScroll)
                }

                Section("Feedback") {
                    Toggle("Haptics", isOn: $haptics)
                }

                Section {
                    Button("Forget Dongle", role: .destructive) {
                        confirmForget = true
                    }
                } footer: {
                    Text("Clears the remembered dongle and its pairing token. To pair again, press the dongle button. If the dongle was reset, also forget it in iOS Settings › Bluetooth.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Forget this dongle?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget Dongle", role: .destructive) {
                    ble.forgetDongle()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
