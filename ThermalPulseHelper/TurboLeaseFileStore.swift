import Foundation
import ThermalPulseCore

final class TurboLeaseFileStore: TurboLeaseStore, @unchecked Sendable {
    static let defaultURL = URL(
        fileURLWithPath: "/Library/Application Support/ThermalPulse/turbo-lease.plist",
        isDirectory: false
    )

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: PropertyListEncoder
    private let decoder: PropertyListDecoder

    init(
        fileURL: URL = TurboLeaseFileStore.defaultURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        decoder = PropertyListDecoder()
    }

    func load() throws -> TurboLease? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(TurboLease.self, from: Data(contentsOf: fileURL))
    }

    func save(_ lease: TurboLease) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let data = try encoder.encode(lease)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
