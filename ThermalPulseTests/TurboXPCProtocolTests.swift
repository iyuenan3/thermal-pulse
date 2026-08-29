import XCTest
@testable import ThermalPulseCore

final class TurboXPCProtocolTests: XCTestCase {
    func testIdentityIsFrozenAcrossHelperAndMachService() {
        XCTAssertEqual(
            ThermalPulseIdentity.appBundleIdentifier,
            "io.github.iyuenan3.thermalpulse"
        )
        XCTAssertEqual(
            ThermalPulseIdentity.helperIdentifier,
            "io.github.iyuenan3.thermalpulse.helper"
        )
        XCTAssertEqual(
            ThermalPulseIdentity.machServiceName,
            ThermalPulseIdentity.helperIdentifier
        )
    }

    func testPeerRequirementsPinAppleAnchorIdentifierAndTeam() throws {
        let appRequirement = try PeerCodeSigningRequirement.app(
            teamIdentifier: "ABCDE12345"
        )
        let helperRequirement = try PeerCodeSigningRequirement.helper(
            teamIdentifier: "ABCDE12345"
        )

        XCTAssertEqual(
            appRequirement,
            "anchor apple generic and identifier \"io.github.iyuenan3.thermalpulse\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
        XCTAssertEqual(
            helperRequirement,
            "anchor apple generic and identifier \"io.github.iyuenan3.thermalpulse.helper\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }

    func testPeerRequirementRejectsMissingOrUnsafeTeamIdentifier() {
        XCTAssertThrowsError(try PeerCodeSigningRequirement.app(teamIdentifier: ""))
        XCTAssertThrowsError(
            try PeerCodeSigningRequirement.helper(teamIdentifier: "TEAM\" or true")
        )
    }

    func testSecurePayloadRoundTripPreservesBoundedStatus() throws {
        let startedAt = Date(timeIntervalSince1970: 100)
        let status = TurboStatus(
            phase: .active,
            startedAt: startedAt,
            deadline: startedAt.addingTimeInterval(600)
        )
        let payload = TurboXPCStatusPayload(status: status)
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: payload,
            requiringSecureCoding: true
        )
        let decoded = try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(
                ofClass: TurboXPCStatusPayload.self,
                from: data
            )
        )

        XCTAssertEqual(try decoded.domainStatus(), status)
    }

    func testXPCInterfaceRegistersTheFixedProtocol() {
        XCTAssertNotNil(TurboXPCInterfaceFactory.makeInterface().protocol)
    }

    func testPayloadRejectsIncompatibleProtocolVersion() {
        let payload = TurboXPCStatusPayload(
            status: .inactive(),
            protocolVersion: ThermalPulseIdentity.turboProtocolVersion + 1
        )

        XCTAssertThrowsError(try payload.domainStatus()) { error in
            XCTAssertEqual(error as? TurboIssue, .incompatibleProtocol)
        }
    }
}
