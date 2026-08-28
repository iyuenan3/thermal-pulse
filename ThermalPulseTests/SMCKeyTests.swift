import XCTest
@testable import ThermalPulseCore

final class SMCKeyTests: XCTestCase {
    func testRoundTripsFourCharacterCode() throws {
        let key = try XCTUnwrap(SMCKey(rawValue: "F0Ac"))
        XCTAssertEqual(SMCKey(code: key.code), key)
        XCTAssertEqual(key.code, 0x46304163)
    }

    func testRejectsNonFourByteKey() {
        XCTAssertNil(SMCKey(rawValue: "F0A"))
        XCTAssertNil(SMCKey(rawValue: "温度00"))
    }

    func testAppleSMCParameterLayoutMatchesUserClientABI() {
        XCTAssertEqual(SMCReadAdapter.parameterStructSize, 80)
    }

    func testAdapterCommandSurfaceContainsOnlyReadOperations() {
        XCTAssertEqual(Set(SMCReadCommand.allCases.map(\.rawValue)), Set([5, 8, 9]))
    }
}
