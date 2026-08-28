import XCTest
@testable import ThermalPulseCore

final class SMCValueDecoderTests: XCTestCase {
    func testDecodesBigEndianUnsignedInteger() throws {
        let value = raw(type: "ui32", bytes: [0x00, 0x00, 0x04, 0xd2])
        XCTAssertEqual(SMCValueDecoder.decode(value), .unsigned(1_234))
    }

    func testDecodesSP78Temperature() throws {
        let value = raw(type: "sp78", bytes: [0x2a, 0x80])
        XCTAssertEqual(SMCValueDecoder.decode(value), .floating(42.5))
    }

    func testDecodesFPE2FanSpeed() throws {
        let value = raw(type: "fpe2", bytes: [0x17, 0x70])
        XCTAssertEqual(SMCValueDecoder.decode(value), .floating(1_500))
    }

    func testDecodesLittleEndianFloat() throws {
        let value = raw(type: "flt ", bytes: [0x00, 0x80, 0xbb, 0x44])
        XCTAssertEqual(SMCValueDecoder.decode(value), .floating(1_500))
    }

    func testPreservesUnsupportedBytes() throws {
        let value = raw(type: "ch8*", bytes: [0x41, 0x42])
        XCTAssertEqual(SMCValueDecoder.decode(value), .bytes([0x41, 0x42]))
    }

    private func raw(type: String, bytes: [UInt8]) -> SMCRawValue {
        let key = SMCKey(rawValue: "TEST")!
        let metadata = SMCKeyMetadata(
            key: key,
            dataSize: bytes.count,
            dataType: SMCDataType(rawValue: type)!,
            attributes: 0
        )
        return SMCRawValue(metadata: metadata, bytes: bytes)
    }
}
