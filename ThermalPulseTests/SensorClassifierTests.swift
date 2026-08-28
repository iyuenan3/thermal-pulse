import XCTest
@testable import ThermalPulseCore

final class SensorClassifierTests: XCTestCase {
    func testClassifiesDynamicallyIndexedFanActualSpeed() throws {
        let reading = SensorClassifier.classify(raw(key: "F1Ac", type: "fpe2", bytes: [0x17, 0x70]))
        XCTAssertEqual(reading.descriptor.kind, .fanActualSpeed)
        XCTAssertEqual(reading.descriptor.displayName, "风扇 2 实际转速")
        XCTAssertEqual(reading.descriptor.evidence, .runtimeValidated)
        XCTAssertEqual(reading.value, 1_500)
        XCTAssertEqual(reading.validity, .valid)
    }

    func testKeepsTemperatureIdentityUnverified() throws {
        let reading = SensorClassifier.classify(raw(key: "Tp09", type: "sp78", bytes: [0x30, 0x00]))
        XCTAssertEqual(reading.descriptor.kind, .temperatureCandidate)
        XCTAssertEqual(reading.descriptor.evidence, .rawUnverified)
        XCTAssertNil(reading.descriptor.displayName)
        XCTAssertFalse(reading.descriptor.defaultVisible)
    }

    func testRejectsImplausibleTemperatureValue() throws {
        let reading = SensorClassifier.classify(raw(key: "Tp09", type: "sp78", bytes: [0x7f, 0x00]))
        XCTAssertEqual(reading.value, 127)
        XCTAssertEqual(reading.validity, .valid)

        let invalid = SensorClassifier.classify(raw(key: "Tp09", type: "flt ", bytes: [0x00, 0x00, 0x48, 0x43]))
        XCTAssertEqual(invalid.value, 200)
        XCTAssertEqual(invalid.validity, .invalid("超出合理范围"))
    }

    func testDoesNotSampleUnknownNonSensorKey() throws {
        let metadata = SMCKeyMetadata(
            key: SMCKey(rawValue: "REV ")!,
            dataSize: 6,
            dataType: SMCDataType(rawValue: "ch8*")!,
            attributes: 0
        )
        XCTAssertFalse(SensorClassifier.shouldSample(metadata))
    }

    private func raw(key: String, type: String, bytes: [UInt8]) -> SMCRawValue {
        let metadata = SMCKeyMetadata(
            key: SMCKey(rawValue: key)!,
            dataSize: bytes.count,
            dataType: SMCDataType(rawValue: type)!,
            attributes: 0
        )
        return SMCRawValue(metadata: metadata, bytes: bytes)
    }
}
