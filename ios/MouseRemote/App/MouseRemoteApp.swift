import SwiftUI

@main
@MainActor
struct MouseRemoteApp: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var modifiers = ModifierState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(modifiers)
                .preferredColorScheme(.light)
                .tint(.blue)
        }
    }
}
