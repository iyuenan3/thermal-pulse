import Foundation

public actor SMCProbeService {
    private let adapter: SMCReadAdapter
    private var sampledMetadata: [SMCKey: SMCKeyMetadata] = [:]
    private var sampledDescriptors: [SMCKey: SensorDescriptor] = [:]

    public init() throws {
        adapter = try SMCReadAdapter()
    }

    public func scan() async throws -> SMCProbeSnapshot {
        sampledMetadata.removeAll(keepingCapacity: true)
        sampledDescriptors.removeAll(keepingCapacity: true)

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

                let rawValue = try adapter.read(metadata)
                let reading = SensorClassifier.classify(rawValue)
                sampledKeyCount += 1
                sampledMetadata[key] = metadata
                sampledDescriptors[key] = reading.descriptor
                readings.append(reading)
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

    public func sample(keys: [SMCKey]) async -> SMCBatchSample {
        var readings: [SensorReading] = []
        var failedReadCount = 0

        for key in keys {
            guard let metadata = sampledMetadata[key],
                  let descriptor = sampledDescriptors[key]
            else {
                failedReadCount += 1
                continue
            }

            do {
                let rawValue = try adapter.read(metadata)
                readings.append(SensorClassifier.classify(rawValue))
            } catch {
                failedReadCount += 1
                readings.append(
                    SensorReading(
                        descriptor: descriptor,
                        value: nil,
                        validity: .unavailable("本轮读取失败"),
                        dataType: metadata.dataType
                    )
                )
            }
        }

        return SMCBatchSample(
            readings: readings.sorted { $0.descriptor.key < $1.descriptor.key },
            failedReadCount: failedReadCount
        )
    }
}
