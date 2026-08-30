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
        XCTAssertEqual(ThermalPulseIdentity.turboProtocolVersion, 8)
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

    func testPinnedPeerRequirementsAcceptOnlyExactCodeDirectoryHash() throws {
        let hash = String(repeating: "a", count: 40)

        XCTAssertEqual(
            try PeerCodeSigningRequirement.app(codeDirectoryHash: hash),
            "identifier \"io.github.iyuenan3.thermalpulse\" and cdhash H\"\(hash)\""
        )
        XCTAssertEqual(
            try PeerCodeSigningRequirement.helper(codeDirectoryHash: hash.uppercased()),
            "identifier \"io.github.iyuenan3.thermalpulse.helper\" and cdhash H\"\(hash)\""
        )
        XCTAssertThrowsError(
            try PeerCodeSigningRequirement.app(codeDirectoryHash: String(repeating: "a", count: 39))
        )
        XCTAssertThrowsError(
            try PeerCodeSigningRequirement.helper(
                codeDirectoryHash: "\(String(repeating: "a", count: 39))\""
            )
        )
    }

    func testPinnedInstallationAuthenticatesBothDirections() throws {
        let appHash = String(repeating: "a", count: 40)
        let helperHash = String(repeating: "b", count: 40)
        let manifestURL = try writeManifest(
            TurboInstallationManifest(
                appCodeDirectoryHash: appHash,
                helperCodeDirectoryHash: helperHash,
                appExecutableSHA256: String(repeating: "c", count: 64),
                helperExecutableSHA256: String(repeating: "d", count: 64)
            )
        )
        defer { try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent()) }

        let helperRequirement = try TurboPeerTrustResolver.helperRequirementForCurrentApp(
            identity: TurboCodeIdentity(
                identifier: ThermalPulseIdentity.appBundleIdentifier,
                codeDirectoryHash: appHash,
                teamIdentifier: nil
            ),
            appBundleURL: URL(fileURLWithPath: ThermalPulseIdentity.installedAppBundlePath),
            manifestURL: manifestURL,
            requireRootOwnership: false
        )
        let appRequirement = try TurboPeerTrustResolver.appRequirementForCurrentHelper(
            identity: TurboCodeIdentity(
                identifier: ThermalPulseIdentity.helperIdentifier,
                codeDirectoryHash: helperHash,
                teamIdentifier: nil
            ),
            executableURL: URL(
                fileURLWithPath: ThermalPulseIdentity.installedHelperExecutablePath
            ),
            manifestURL: manifestURL,
            requireRootOwnership: false
        )

        XCTAssertEqual(
            helperRequirement,
            "identifier \"io.github.iyuenan3.thermalpulse.helper\" and cdhash H\"\(helperHash)\""
        )
        XCTAssertEqual(
            appRequirement,
            "identifier \"io.github.iyuenan3.thermalpulse\" and cdhash H\"\(appHash)\""
        )
    }

    func testPinnedInstallationRejectsMovedOrChangedApp() throws {
        let appHash = String(repeating: "a", count: 40)
        let manifestURL = try writeManifest(
            TurboInstallationManifest(
                appCodeDirectoryHash: appHash,
                helperCodeDirectoryHash: String(repeating: "b", count: 40),
                appExecutableSHA256: String(repeating: "c", count: 64),
                helperExecutableSHA256: String(repeating: "d", count: 64)
            )
        )
        defer { try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent()) }
        let identity = TurboCodeIdentity(
            identifier: ThermalPulseIdentity.appBundleIdentifier,
            codeDirectoryHash: String(repeating: "e", count: 40),
            teamIdentifier: nil
        )

        XCTAssertThrowsError(
            try TurboPeerTrustResolver.helperRequirementForCurrentApp(
                identity: identity,
                appBundleURL: URL(fileURLWithPath: ThermalPulseIdentity.installedAppBundlePath),
                manifestURL: manifestURL,
                requireRootOwnership: false
            )
        ) { error in
            XCTAssertEqual(
                error as? TurboInstallationIdentityError,
                .currentExecutableMismatch
            )
        }
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

    func testSecurePayloadRoundTripPreservesSpecificReadbackIssue() throws {
        let status = TurboStatus(
            phase: .failedSafeAuto,
            issue: .targetReadbackMismatch
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

    func testXPCInterfaceRegistersOnlyTheBoundedPayloadClass() {
        let interface = TurboXPCInterfaceFactory.makeInterface()

        XCTAssertNotNil(interface.protocol)
        let replyClasses = interface.classes(
            for: #selector(TurboXPCProtocol.startTurbo(reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        let expectedClasses = NSSet(object: TurboXPCStatusPayload.self) as! Set<AnyHashable>
        let broadObjectClasses = NSSet(object: NSObject.self) as! Set<AnyHashable>
        XCTAssertEqual(replyClasses, expectedClasses)
        XCTAssertTrue(replyClasses.isDisjoint(with: broadObjectClasses))
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

    private func writeManifest(_ manifest: TurboInstallationManifest) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThermalPulseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        let url = directoryURL.appendingPathComponent("installation.plist")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(manifest).write(to: url, options: .atomic)
        return url
    }
}
