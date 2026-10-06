import Foundation
import CoreBluetooth

/// Constants from docs/PROTOCOL.md (v1).
enum BLEProtocol {
    static var serviceUUID: CBUUID { CBUUID(string: "A7E10001-3C2B-4F6E-9D41-7B8C2E5F1A00") }
    /// Phone -> dongle (write without response).
    static var rxUUID: CBUUID { CBUUID(string: "A7E10002-3C2B-4F6E-9D41-7B8C2E5F1A00") }
    /// Dongle -> phone (notify, AUTH replies only).
    static var txUUID: CBUUID { CBUUID(string: "A7E10003-3C2B-4F6E-9D41-7B8C2E5F1A00") }

    static let tokenLength = 16
    static let pingInterval: TimeInterval = 0.3
}

enum Opcode: UInt8 {
    case move = 0x01
    case buttons = 0x02
    case scroll = 0x03
    case keyTap = 0x04
    case keySet = 0x05
    case consumer = 0x06
    case releaseAll = 0x07
    case ping = 0x08
    case auth = 0x09
}

/// TX notification reply codes.
enum AuthReply: UInt8 {
    case denied = 0x00
    case ok = 0x01
    case newToken = 0x02
}

enum MouseButton: UInt8 {
    case left = 0x01
    case right = 0x02
    case middle = 0x04
}

/// Packet encoder. Every packet is `opcode` + fixed-length payload, little-endian.
enum Packet {
    static func move(dx: Int16, dy: Int16) -> Data {
        var d = Data([Opcode.move.rawValue])
        d.appendLE(dx)
        d.appendLE(dy)
        return d
    }

    static func buttons(_ mask: UInt8) -> Data {
        Data([Opcode.buttons.rawValue, mask])
    }

    static func scroll(vertical: Int8, horizontal: Int8) -> Data {
        Data([Opcode.scroll.rawValue, UInt8(bitPattern: vertical), UInt8(bitPattern: horizontal)])
    }

    static func keyTap(modifiers: UInt8, key: UInt8) -> Data {
        Data([Opcode.keyTap.rawValue, modifiers, key])
    }

    static func keySet(modifiers: UInt8, key: UInt8, down: Bool) -> Data {
        Data([Opcode.keySet.rawValue, modifiers, key, down ? 1 : 0])
    }

    static func consumer(_ usage: UInt16) -> Data {
        var d = Data([Opcode.consumer.rawValue])
        d.appendLE(usage)
        return d
    }

    static var releaseAll: Data { Data([Opcode.releaseAll.rawValue]) }

    static var ping: Data { Data([Opcode.ping.rawValue]) }

    /// `token` must be 16 bytes; anything else is replaced by zeros ("no token yet").
    static func auth(token: Data?) -> Data {
        var d = Data([Opcode.auth.rawValue])
        if let token, token.count == BLEProtocol.tokenLength {
            d.append(token)
        } else {
            d.append(Data(repeating: 0, count: BLEProtocol.tokenLength))
        }
        return d
    }
}

extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: Int16) {
        appendLE(UInt16(bitPattern: value))
    }
}
