import UIKit

@MainActor
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.haptics) as? Bool ?? SettingsDefault.haptics
    }

    /// Mouse clicks.
    static func click() {
        guard isEnabled else { return }
        mediumGenerator.impactOccurred()
    }

    /// Key buttons.
    static func key() {
        guard isEnabled else { return }
        lightGenerator.impactOccurred()
    }
}
