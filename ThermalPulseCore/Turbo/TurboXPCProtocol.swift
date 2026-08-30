import Foundation
import Security

public enum ThermalPulseIdentity {
    public static let appBundleIdentifier = "io.github.iyuenan3.thermalpulse"
    public static let helperIdentifier = "io.github.iyuenan3.thermalpulse.helper"
    public static let machServiceName = helperIdentifier
    public static let launchDaemonPlistName = "\(helperIdentifier).plist"
    public static let turboProtocolVersion = 8
    public static let installedAppBundlePath = "/Applications/ThermalPulse.app"
    public static let installedHelperExecutablePath =
        "/Library/PrivilegedHelperTools/io.github.iyuenan3.thermalpulse.helper"
    public static let installationManifestPath =
        "/Library/Application Support/ThermalPulse/installation.plist"
}

public enum PeerCodeSigningRequirement {
    public static func app(teamIdentifier: String) throws -> String {
        try requirement(
            identifier: ThermalPulseIdentity.appBundleIdentifier,
            teamIdentifier: teamIdentifier
        )
    }

    public static func helper(teamIdentifier: String) throws -> String {
        try requirement(
            identifier: ThermalPulseIdentity.helperIdentifier,
            teamIdentifier: teamIdentifier
        )
    }

    public static func app(codeDirectoryHash: String) throws -> String {
        try pinnedRequirement(
            identifier: ThermalPulseIdentity.appBundleIdentifier,
            codeDirectoryHash: codeDirectoryHash
        )
    }

    public static func helper(codeDirectoryHash: String) throws -> String {
        try pinnedRequirement(
            identifier: ThermalPulseIdentity.helperIdentifier,
            codeDirectoryHash: codeDirectoryHash
        )
    }

    private static func requirement(
        identifier: String,
        teamIdentifier: String
    ) throws -> String {
        let isSafeTeamIdentifier = !teamIdentifier.isEmpty && teamIdentifier.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
        guard isSafeTeamIdentifier else {
            throw TurboIssue.callerUnauthorized
        }

        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    private static func pinnedRequirement(
        identifier: String,
        codeDirectoryHash: String
    ) throws -> String {
        let normalizedHash = codeDirectoryHash.lowercased()
        let isSafeHash = normalizedHash.count == 40 && normalizedHash.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }
        guard isSafeHash else {
            throw TurboIssue.callerUnauthorized
        }

        return "identifier \"\(identifier)\" and cdhash H\"\(normalizedHash)\""
    }
}

public enum CurrentCodeSignature {
    public static func identity() -> TurboCodeIdentity? {
        resolvedIdentity
    }

    public static func freshIdentity() -> TurboCodeIdentity? {
        resolveIdentity()
    }

    public static func teamIdentifier() -> String? {
        resolvedIdentity?.teamIdentifier
    }

    private static let resolvedIdentity = resolveIdentity()

    private static func resolveIdentity() -> TurboCodeIdentity? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code
        else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(
            code,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
        let staticCode
        else {
            return nil
        }

        guard SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            nil
        ) == errSecSuccess else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let dictionary = information as? [String: Any]
        else {
            return nil
        }

        guard let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String,
              let codeDirectoryHash = dictionary[kSecCodeInfoUnique as String] as? Data
        else {
            return nil
        }

        return TurboCodeIdentity(
            identifier: identifier,
            codeDirectoryHash: codeDirectoryHash.map { String(format: "%02x", $0) }.joined(),
            teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }
}

@objc(ThermalPulseTurboXPCStatusPayload)
public final class TurboXPCStatusPayload: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let protocolVersion: Int
    public let phaseRawValue: String
    public let startedAt: Date?
    public let deadline: Date?
    public let issueRawValue: String?

    public init(
        status: TurboStatus,
        protocolVersion: Int = ThermalPulseIdentity.turboProtocolVersion
    ) {
        self.protocolVersion = protocolVersion
        phaseRawValue = status.phase.rawValue
        startedAt = status.startedAt
        deadline = status.deadline
        issueRawValue = status.issue?.rawValue
    }

    public required init?(coder: NSCoder) {
        protocolVersion = coder.decodeInteger(forKey: CodingKey.protocolVersion)
        guard let phaseRawValue = coder.decodeObject(
            of: NSString.self,
            forKey: CodingKey.phaseRawValue
        ) as String? else {
            return nil
        }
        self.phaseRawValue = phaseRawValue
        startedAt = coder.decodeObject(of: NSDate.self, forKey: CodingKey.startedAt) as Date?
        deadline = coder.decodeObject(of: NSDate.self, forKey: CodingKey.deadline) as Date?
        issueRawValue = coder.decodeObject(
            of: NSString.self,
            forKey: CodingKey.issueRawValue
        ) as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(protocolVersion, forKey: CodingKey.protocolVersion)
        coder.encode(phaseRawValue, forKey: CodingKey.phaseRawValue)
        coder.encode(startedAt, forKey: CodingKey.startedAt)
        coder.encode(deadline, forKey: CodingKey.deadline)
        coder.encode(issueRawValue, forKey: CodingKey.issueRawValue)
    }

    public func domainStatus() throws -> TurboStatus {
        guard protocolVersion == ThermalPulseIdentity.turboProtocolVersion else {
            throw TurboIssue.incompatibleProtocol
        }
        guard let phase = TurboPhase(rawValue: phaseRawValue) else {
            throw TurboIssue.invalidStatusResponse
        }

        let issue: TurboIssue?
        if let issueRawValue {
            guard let decodedIssue = TurboIssue(rawValue: issueRawValue) else {
                throw TurboIssue.invalidStatusResponse
            }
            issue = decodedIssue
        } else {
            issue = nil
        }

        return TurboStatus(
            phase: phase,
            startedAt: startedAt,
            deadline: deadline,
            issue: issue
        )
    }

    private enum CodingKey {
        static let protocolVersion = "protocolVersion"
        static let phaseRawValue = "phaseRawValue"
        static let startedAt = "startedAt"
        static let deadline = "deadline"
        static let issueRawValue = "issueRawValue"
    }
}

@objc(ThermalPulseTurboXPCProtocol)
public protocol TurboXPCProtocol {
    func startTurbo(reply: @escaping (TurboXPCStatusPayload) -> Void)
    func stopTurbo(reply: @escaping (TurboXPCStatusPayload) -> Void)
    func getTurboStatus(reply: @escaping (TurboXPCStatusPayload) -> Void)
}

public enum TurboXPCInterfaceFactory {
    public static func makeInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: TurboXPCProtocol.self)
        let payloadClasses = NSSet(object: TurboXPCStatusPayload.self) as! Set<AnyHashable>
        interface.setClasses(
            payloadClasses,
            for: #selector(TurboXPCProtocol.startTurbo(reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        interface.setClasses(
            payloadClasses,
            for: #selector(TurboXPCProtocol.stopTurbo(reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        interface.setClasses(
            payloadClasses,
            for: #selector(TurboXPCProtocol.getTurboStatus(reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        return interface
    }
}
