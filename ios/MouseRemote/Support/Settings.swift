import Foundation

/// @AppStorage / UserDefaults keys and defaults.
enum SettingsKey {
    static let pointerSpeed = "settings.pointerSpeed"
    static let scrollSpeed = "settings.scrollSpeed"
    static let naturalScroll = "settings.naturalScroll"
    static let haptics = "settings.haptics"
    static let showKeys = "settings.showKeys"
}

enum SettingsDefault {
    static let pointerSpeed: Double = 1.0
    static let scrollSpeed: Double = 1.0
    static let naturalScroll: Bool = true
    static let haptics: Bool = true
    static let showKeys: Bool = true
}
