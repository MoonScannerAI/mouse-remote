import SwiftUI
import UIKit

/// Light-theme palette, defined once. Semantic system colors so it adapts cleanly.
enum Palette {
    // UIKit flavors (HoldButton, TouchpadView).
    static let uiKeyFill = UIColor.systemBackground
    static let uiKeyPressed = UIColor.systemGray4
    static let uiKeyBorder = UIColor.systemGray4
    static let uiText = UIColor.label
    static let uiTextSecondary = UIColor.secondaryLabel
    static let uiOnAccent = UIColor.white
    static let uiTouchpadFill = UIColor.systemGray5
    static let uiTouchpadBorder = UIColor.systemGray3

    // SwiftUI flavors.
    static let pageBackground = Color(.systemGroupedBackground)
    static let keyFill = Color(uiKeyFill)
    static let keyPressed = Color(uiKeyPressed)
    static let keyBorder = Color(uiKeyBorder)
    static let text = Color.primary
    static let textSecondary = Color.secondary
    static let accent = Color.accentColor
    /// Text on an accent-filled key.
    static let onAccent = Color.white
}
