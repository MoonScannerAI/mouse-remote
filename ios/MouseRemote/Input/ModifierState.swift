import Foundation

enum StickyModifier: CaseIterable, Hashable {
    case win, ctrl, alt, shift

    var bit: UInt8 {
        switch self {
        case .win: return HIDModifier.leftGUI
        case .ctrl: return HIDModifier.leftCtrl
        case .alt: return HIDModifier.leftAlt
        case .shift: return HIDModifier.leftShift
        }
    }

    var title: String {
        switch self {
        case .win: return "Win"
        case .ctrl: return "Ctrl"
        case .alt: return "Alt"
        case .shift: return "Shift"
        }
    }
}

enum StickyMode {
    case off
    case once    // applies to the next key only
    case locked  // applies until tapped again
}

/// Sticky modifiers: tap = next key only, double-tap = locked, tap again = off.
@MainActor
final class ModifierState: ObservableObject {
    @Published private(set) var modes: [StickyModifier: StickyMode] = [:]
    private var lastTap: [StickyModifier: Date] = [:]
    private static let doubleTapWindow: TimeInterval = 0.4

    func mode(_ modifier: StickyModifier) -> StickyMode {
        modes[modifier] ?? .off
    }

    func tap(_ modifier: StickyModifier) {
        let now = Date()
        let isDoubleTap = lastTap[modifier].map { now.timeIntervalSince($0) < Self.doubleTapWindow } ?? false
        switch mode(modifier) {
        case .off:
            modes[modifier] = .once
        case .once:
            modes[modifier] = isDoubleTap ? .locked : .off
        case .locked:
            modes[modifier] = .off
        }
        lastTap[modifier] = now
    }

    /// Current mask without consuming one-shot modifiers.
    var activeMask: UInt8 {
        modes.reduce(UInt8(0)) { $1.value == .off ? $0 : ($0 | $1.key.bit) }
    }

    /// Returns the active mask and clears one-shot modifiers.
    func consume() -> UInt8 {
        let mask = activeMask
        if modes.values.contains(.once) {
            var updated = modes
            for (modifier, mode) in modes where mode == .once {
                updated[modifier] = .off
            }
            modes = updated
        }
        return mask
    }
}
