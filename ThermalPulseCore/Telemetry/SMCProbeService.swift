import Foundation

public actor SMCProbeService {
    private let adapter: SMCReadAdapter

    public init() throws {
        adapter = try SMCReadAdapter()
    }

    public func scan() throws -> SMCProbeSnapshot {
        let advertisedKeyCount = try adapter.keyCount()
        let keys = try adapter.enumerateKeys()
        var metadataReadCount = 0
        var sampledKeyCount = 0
        var failedReadCount = 0
        var readings: [SensorReading] = []

        for key in keys {
            do {
                let metadata = try adapter.metadata(for: key)
                metadataReadCount += 1
                guard SensorClassifier.shouldSample(metadata) else { continue }

                let rawValue = try adapter.read(key)
                sampledKeyCount += 1
                readings.append(SensorClassifier.classify(rawValue))
            } catch {
                failedReadCount += 1
            }
        }

        let fanCount = readings.first(where: { $0.descriptor.key == .fanCount })?.value.map(Int.init)
        return SMCProbeSnapshot(
            timestamp: Date(),
            advertisedKeyCount: advertisedKeyCount,
            enumeratedKeyCount: keys.count,
            metadataReadCount: metadataReadCount,
            sampledKeyCount: sampledKeyCount,
            failedReadCount: failedReadCount,
            fanCount: fanCount,
            readings: readings.sorted { $0.descriptor.key < $1.descriptor.key }
        )
    }
}
