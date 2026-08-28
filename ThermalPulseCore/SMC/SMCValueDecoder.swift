import Foundation

public enum SMCDecodedValue: Equatable, Sendable {
    case unsigned(UInt64)
    case signed(Int64)
    case floating(Double)
    case bytes([UInt8])

    public var numericValue: Double? {
        switch self {
        case let .unsigned(value): Double(value)
        case let .signed(value): Double(value)
        case let .floating(value): value
        case .bytes: nil
        }
    }
}

public enum SMCValueDecoder {
    public static func decode(_ rawValue: SMCRawValue) -> SMCDecodedValue {
        let type = rawValue.dataType.normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
        case "ui8": return decodeUnsigned(rawValue.bytes, width: 1)
        case "ui16": return decodeUnsigned(rawValue.bytes, width: 2)
        case "ui32": return decodeUnsigned(rawValue.bytes, width: 4)
        case "ui64": return decodeUnsigned(rawValue.bytes, width: 8)
        case "si8": return decodeSigned(rawValue.bytes, width: 1)
        case "si16": return decodeSigned(rawValue.bytes, width: 2)
        case "si32": return decodeSigned(rawValue.bytes, width: 4)
        case "flt": return decodeFloat(rawValue.bytes)
        default:
            if type.count == 4, type.hasPrefix("fp") {
                return decodeFixedPoint(rawValue.bytes, signed: false, type: type)
            }
            if type.count == 4, type.hasPrefix("sp") {
                return decodeFixedPoint(rawValue.bytes, signed: true, type: type)
            }
            return .bytes(rawValue.bytes)
        }
    }

    private static func decodeUnsigned(_ bytes: [UInt8], width: Int) -> SMCDecodedValue {
        guard bytes.count >= width else { return .bytes(bytes) }
        let value = bytes.prefix(width).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return .unsigned(value)
    }

    private static func decodeSigned(_ bytes: [UInt8], width: Int) -> SMCDecodedValue {
        guard bytes.count >= width else { return .bytes(bytes) }
        let unsigned = bytes.prefix(width).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let bitCount = width * 8
        let signBit = UInt64(1) << UInt64(bitCount - 1)
        if unsigned & signBit == 0 {
            return .signed(Int64(unsigned))
        }
        let magnitude = Int64((~unsigned + 1) & ((UInt64(1) << UInt64(bitCount)) - 1))
        return .signed(-magnitude)
    }

    private static func decodeFloat(_ bytes: [UInt8]) -> SMCDecodedValue {
        guard bytes.count >= 4 else { return .bytes(bytes) }
        // Apple Silicon exposes `flt ` payloads in little-endian IEEE 754 form.
        let bits = UInt32(bytes[0])
            | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24
        return .floating(Double(Float(bitPattern: bits)))
    }

    private static func decodeFixedPoint(
        _ bytes: [UInt8],
        signed: Bool,
        type: String
    ) -> SMCDecodedValue {
        guard bytes.count >= 2,
              let fractionalBits = Int(String(type.last!), radix: 16)
        else {
            return .bytes(bytes)
        }

        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let divisor = pow(2.0, Double(fractionalBits))
        if signed {
            return .floating(Double(Int16(bitPattern: raw)) / divisor)
        }
        return .floating(Double(raw) / divisor)
    }
}
