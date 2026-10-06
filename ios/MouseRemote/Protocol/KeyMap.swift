import Foundation

struct KeyStroke: Equatable {
    let modifiers: UInt8
    let key: UInt8
}

/// HID modifier bits (`mod`).
enum HIDModifier {
    static let leftCtrl: UInt8 = 0x01
    static let leftShift: UInt8 = 0x02
    static let leftAlt: UInt8 = 0x04
    static let leftGUI: UInt8 = 0x08
}

/// USB HID Keyboard/Keypad page (0x07) usages.
enum HIDKey {
    static let a: UInt8 = 0x04
    static let c: UInt8 = 0x06
    static let d: UInt8 = 0x07
    static let l: UInt8 = 0x0F
    static let v: UInt8 = 0x19
    static let x: UInt8 = 0x1B
    static let y: UInt8 = 0x1C
    static let z: UInt8 = 0x1D
    static let enter: UInt8 = 0x28
    static let escape: UInt8 = 0x29
    static let backspace: UInt8 = 0x2A
    static let tab: UInt8 = 0x2B
    static let space: UInt8 = 0x2C
    static let f1: UInt8 = 0x3A
    static let printScreen: UInt8 = 0x46
    static let insert: UInt8 = 0x49
    static let home: UInt8 = 0x4A
    static let pageUp: UInt8 = 0x4B
    static let delete: UInt8 = 0x4C
    static let end: UInt8 = 0x4D
    static let pageDown: UInt8 = 0x4E
    static let right: UInt8 = 0x4F
    static let left: UInt8 = 0x50
    static let down: UInt8 = 0x51
    static let up: UInt8 = 0x52

    /// F1...F12 (n = 1...12).
    static func function(_ n: Int) -> UInt8 {
        UInt8(Int(f1) + max(0, min(11, n - 1)))
    }
}

/// HID Consumer page usages.
enum ConsumerUsage {
    static let volumeUp: UInt16 = 0x00E9
    static let volumeDown: UInt16 = 0x00EA
    static let mute: UInt16 = 0x00E2
    static let playPause: UInt16 = 0x00CD
    static let nextTrack: UInt16 = 0x00B5
    static let previousTrack: UInt16 = 0x00B6
    static let brightnessUp: UInt16 = 0x006F
    static let brightnessDown: UInt16 = 0x0070
}

/// Maps text to US-layout key strokes.
enum KeyMap {
    /// Unshifted / shifted symbol table (US layout). Value: (keycode, needsShift).
    private static let symbols: [Unicode.Scalar: (UInt8, Bool)] = [
        " ": (0x2C, false),
        "\n": (0x28, false),
        "\t": (0x2B, false),
        "-": (0x2D, false), "_": (0x2D, true),
        "=": (0x2E, false), "+": (0x2E, true),
        "[": (0x2F, false), "{": (0x2F, true),
        "]": (0x30, false), "}": (0x30, true),
        "\\": (0x31, false), "|": (0x31, true),
        ";": (0x33, false), ":": (0x33, true),
        "'": (0x34, false), "\"": (0x34, true),
        "`": (0x35, false), "~": (0x35, true),
        ",": (0x36, false), "<": (0x36, true),
        ".": (0x37, false), ">": (0x37, true),
        "/": (0x38, false), "?": (0x38, true),
        "!": (0x1E, true), "@": (0x1F, true), "#": (0x20, true),
        "$": (0x21, true), "%": (0x22, true), "^": (0x23, true),
        "&": (0x24, true), "*": (0x25, true), "(": (0x26, true),
        ")": (0x27, true),
    ]

    /// Replaces typographic characters produced by smart punctuation with ASCII.
    static func normalizedScalars(_ text: String) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(text.unicodeScalars.count)
        for s in text.unicodeScalars {
            switch s.value {
            case 0x2018, 0x2019, 0x201A, 0x201B, 0x2032:
                out.append("'")
            case 0x201C, 0x201D, 0x201E, 0x201F, 0x2033:
                out.append("\"")
            case 0x2010...0x2015, 0x2212:
                out.append("-")
            case 0x2026:
                out.append(contentsOf: ["." as Unicode.Scalar, ".", "."])
            case 0x00A0, 0x2007, 0x202F:
                out.append(" ")
            case 0x0D:
                continue // CR: "\r\n" becomes a single Enter.
            default:
                out.append(s)
            }
        }
        return out
    }

    static func stroke(for scalar: Unicode.Scalar) -> KeyStroke? {
        let v = scalar.value
        switch v {
        case 0x61...0x7A: // a-z
            return KeyStroke(modifiers: 0, key: UInt8(0x04 + v - 0x61))
        case 0x41...0x5A: // A-Z
            return KeyStroke(modifiers: HIDModifier.leftShift, key: UInt8(0x04 + v - 0x41))
        case 0x31...0x39: // 1-9
            return KeyStroke(modifiers: 0, key: UInt8(0x1E + v - 0x31))
        case 0x30: // 0
            return KeyStroke(modifiers: 0, key: 0x27)
        default:
            guard let entry = symbols[scalar] else { return nil }
            return KeyStroke(modifiers: entry.1 ? HIDModifier.leftShift : 0, key: entry.0)
        }
    }

    /// Key strokes for `text`; unmappable characters (emoji, accents, ...) are skipped.
    static func strokes(for text: String) -> [KeyStroke] {
        normalizedScalars(text).compactMap { stroke(for: $0) }
    }
}
