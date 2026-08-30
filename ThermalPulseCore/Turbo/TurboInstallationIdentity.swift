import Foundation

public struct TurboCodeIdentity: Sendable, Equatable {
    public let identifier: String
    public let codeDirectoryHash: String
    public let teamIdentifier: String?

    public init(
        identifier: String,
        codeDirectoryHash: String,
        teamIdentifier: String?
    ) {
        self.identifier = identifier
        self.codeDirectoryHash = codeDirectoryHash.lowercased()
        self.teamIdentifier = teamIdentifier?.isEmpty == false ? teamIdentifier : nil
    }
}

public struct TurboInstallationManifest: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let appIdentifier: String
    public let helperIdentifier: String
    public let appBundlePath: String
    public let helperExecutablePath: String
    public let appCodeDirectoryHash: String
    public let helperCodeDirectoryHash: String
    public let appExecutableSHA256: String
    public let helperExecutableSHA256: String

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        appIdentifier: String = ThermalPulseIdentity.appBundleIdentifier,
        helperIdentifier: String = ThermalPulseIdentity.helperIdentifier,
        appBundlePath: String = ThermalPulseIdentity.installedAppBundlePath,
        helperExecutablePath: String = ThermalPulseIdentity.installedHelperExecutablePath,
        appCodeDirectoryHash: String,
        helperCodeDirectoryHash: String,
        appExecutableSHA256: String,
        helperExecutableSHA256: String
    ) {
        self.formatVersion = formatVersion
        self.appIdentifier = appIdentifier
        self.helperIdentifier = helperIdentifier
        self.appBundlePath = appBundlePath
        self.helperExecutablePath = helperExecutablePath
        self.appCodeDirectoryHash = appCodeDirectoryHash.lowercased()
        self.helperCodeDirectoryHash = helperCodeDirectoryHash.lowercased()
        self.appExecutableSHA256 = appExecutableSHA256.lowercased()
        self.helperExecutableSHA256 = helperExecutableSHA256.lowercased()
    }

    public func validated() throws -> Self {
        guard formatVersion == Self.currentFormatVersion,
              appIdentifier == ThermalPulseIdentity.appBundleIdentifier,
              helperIdentifier == ThermalPulseIdentity.helperIdentifier,
              appBundlePath == ThermalPulseIdentity.installedAppBundlePath,
              helperExecutablePath == ThermalPulseIdentity.installedHelperExecutablePath,
              Self.isCodeDirectoryHash(appCodeDirectoryHash),
              Self.isCodeDirectoryHash(helperCodeDirectoryHash),
              Self.isSHA256(appExecutableSHA256),
              Self.isSHA256(helperExecutableSHA256)
        else {
            throw TurboInstallationIdentityError.invalidManifest
        }
        return self
    }

    public func requirementForApp() throws -> String {
        try PeerCodeSigningRequirement.app(codeDirectoryHash: appCodeDirectoryHash)
    }

    public func requirementForHelper() throws -> String {
        try PeerCodeSigningRequirement.helper(codeDirectoryHash: helperCodeDirectoryHash)
    }

    private static func isCodeDirectoryHash(_ value: String) -> Bool {
        isLowercaseHex(value, count: 40)
    }

    private static func isSHA256(_ value: String) -> Bool {
        isLowercaseHex(value, count: 64)
    }

    private static func isLowercaseHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }
    }
}

public enum TurboInstallationIdentityError: Error, Sendable, Equatable {
    case notInstalled
    case insecureManifest
    case invalidManifest
    case currentExecutableMismatch
}

public enum TurboInstallationIdentityStore {
    public static let defaultManifestURL = URL(
        fileURLWithPath: ThermalPulseIdentity.installationManifestPath,
        isDirectory: false
    )

    public static func load(
        from url: URL = defaultManifestURL,
        requireRootOwnership: Bool = true,
        fileManager: FileManager = .default
    ) throws -> TurboInstallationManifest {
        guard fileManager.fileExists(atPath: url.path) else {
            throw TurboInstallationIdentityError.notInstalled
        }

        if requireRootOwnership {
            try validateRootOwnedItem(
                at: url.deletingLastPathComponent(),
                expectedType: .typeDirectory,
                fileManager: fileManager
            )
            try validateRootOwnedItem(
                at: url,
                expectedType: .typeRegular,
                fileManager: fileManager
            )
        }

        do {
            let manifest = try PropertyListDecoder().decode(
                TurboInstallationManifest.self,
                from: Data(contentsOf: url, options: [.mappedIfSafe])
            )
            return try manifest.validated()
        } catch let error as TurboInstallationIdentityError {
            throw error
        } catch {
            throw TurboInstallationIdentityError.invalidManifest
        }
    }

    private static func validateRootOwnedItem(
        at url: URL,
        expectedType: FileAttributeType,
        fileManager: FileManager
    ) throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw TurboInstallationIdentityError.insecureManifest
        }

        guard attributes[.type] as? FileAttributeType == expectedType,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
              permissions & 0o022 == 0
        else {
            throw TurboInstallationIdentityError.insecureManifest
        }
    }
}

public enum TurboPeerTrustResolver {
    public static func helperRequirementForCurrentApp(
        identity: TurboCodeIdentity? = CurrentCodeSignature.identity(),
        appBundleURL: URL = Bundle.main.bundleURL,
        manifestURL: URL = TurboInstallationIdentityStore.defaultManifestURL,
        requireRootOwnership: Bool = true
    ) throws -> String {
        guard let identity else {
            throw TurboInstallationIdentityError.currentExecutableMismatch
        }
        if let teamIdentifier = identity.teamIdentifier {
            return try PeerCodeSigningRequirement.helper(teamIdentifier: teamIdentifier)
        }

        let manifest = try TurboInstallationIdentityStore.load(
            from: manifestURL,
            requireRootOwnership: requireRootOwnership
        )
        guard identity.identifier == manifest.appIdentifier,
              identity.codeDirectoryHash == manifest.appCodeDirectoryHash,
              appBundleURL.standardizedFileURL.path == manifest.appBundlePath
        else {
            throw TurboInstallationIdentityError.currentExecutableMismatch
        }
        return try manifest.requirementForHelper()
    }

    public static func appRequirementForCurrentHelper(
        identity: TurboCodeIdentity? = CurrentCodeSignature.identity(),
        executableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0]),
        manifestURL: URL = TurboInstallationIdentityStore.defaultManifestURL,
        requireRootOwnership: Bool = true
    ) throws -> String {
        guard let identity else {
            throw TurboInstallationIdentityError.currentExecutableMismatch
        }
        if let teamIdentifier = identity.teamIdentifier {
            return try PeerCodeSigningRequirement.app(teamIdentifier: teamIdentifier)
        }

        let manifest = try TurboInstallationIdentityStore.load(
            from: manifestURL,
            requireRootOwnership: requireRootOwnership
        )
        guard identity.identifier == manifest.helperIdentifier,
              identity.codeDirectoryHash == manifest.helperCodeDirectoryHash,
              executableURL.standardizedFileURL.path == manifest.helperExecutablePath
        else {
            throw TurboInstallationIdentityError.currentExecutableMismatch
        }
        return try manifest.requirementForApp()
    }
}
