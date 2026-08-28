import Foundation

public struct SMCKey: RawRepresentable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        let bytes = Array(rawValue.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    init(code: UInt32) {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        self.rawValue = String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    var code: UInt32 {
        rawValue.utf8.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }

    public var description: String { rawValue }

    public static func < (lhs: SMCKey, rhs: SMCKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static let keyCount = SMCKey(rawValue: "#KEY")!
    public static let fanCount = SMCKey(rawValue: "FNum")!
}

public struct SMCDataType: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.utf8.count == 4 else {
            return nil
        }
        self.rawValue = rawValue
    }

    init(code: UInt32) {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        self.rawValue = String(decoding: bytes, as: UTF8.self)
    }

    public var normalized: String {
        rawValue.replacingOccurrences(of: "\0", with: " ")
    }

    var code: UInt32 {
        rawValue.utf8.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }

    public var description: String {
        normalized.replacingOccurrences(of: " ", with: "·")
    }
}

