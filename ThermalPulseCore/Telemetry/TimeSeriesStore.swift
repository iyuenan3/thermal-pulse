import Foundation

public actor TimeSeriesStore {
    public let capacityPerSeries: Int

    private var buffers: [SMCKey: SensorRingBuffer] = [:]
    private var descriptors: [SMCKey: SensorDescriptor] = [:]
    private var latestFrame: TelemetryFrame?

    public init(capacityPerSeries: Int = 3_600) {
        self.capacityPerSeries = max(1, capacityPerSeries)
    }

    public func reset() {
        buffers.removeAll(keepingCapacity: true)
        descriptors.removeAll(keepingCapacity: true)
        latestFrame = nil
    }

    public func append(_ frame: TelemetryFrame) {
        latestFrame = frame

        for reading in frame.readings {
            guard reading.validity == .valid,
                  let value = reading.value,
                  value.isFinite
            else {
                continue
            }

            let key = reading.descriptor.key
            descriptors[key] = reading.descriptor
            let buffer: SensorRingBuffer
            if let existingBuffer = buffers[key] {
                buffer = existingBuffer
            } else {
                buffer = SensorRingBuffer(capacity: capacityPerSeries)
                buffers[key] = buffer
            }
            buffer.append(SensorSamplePoint(timestamp: frame.timestamp, value: value))
        }
    }

    public func summary() -> TelemetrySummarySnapshot {
        var series: [SMCKey: SensorSeriesSummary] = [:]

        for (key, buffer) in buffers {
            guard let statistics = buffer.statistics,
                  let descriptor = descriptors[key]
            else { continue }
            series[key] = SensorSeriesSummary(descriptor: descriptor, statistics: statistics)
        }

        return TelemetrySummarySnapshot(
            latestFrame: latestFrame,
            series: series,
            capacityPerSeries: capacityPerSeries
        )
    }

    public func history(for key: SMCKey) -> [SensorSamplePoint] {
        buffers[key]?.elements ?? []
    }

    public func histories(
        for keys: [SMCKey],
        since cutoff: Date? = nil
    ) -> [SMCKey: [SensorSamplePoint]] {
        var result: [SMCKey: [SensorSamplePoint]] = [:]

        for key in keys {
            guard let buffer = buffers[key] else { continue }
            let points = buffer.elements
            if let cutoff {
                result[key] = points.filter { $0.timestamp >= cutoff }
            } else {
                result[key] = points
            }
        }

        return result
    }
}

private final class SensorRingBuffer {
    let capacity: Int

    private var storage: [SensorSamplePoint?]
    private var nextWriteIndex = 0
    private(set) var count = 0
    private var total = 0.0
    private var minimum: Double?
    private var maximum: Double?

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = Array(repeating: nil, count: max(1, capacity))
    }

    func append(_ element: SensorSamplePoint) {
        let evicted = storage[nextWriteIndex]
        let needsMinimumRecalculation = evicted?.value == minimum
        let needsMaximumRecalculation = evicted?.value == maximum

        if let evicted {
            total -= evicted.value
        } else {
            count += 1
        }

        storage[nextWriteIndex] = element
        nextWriteIndex = (nextWriteIndex + 1) % capacity
        total += element.value

        if needsMinimumRecalculation || needsMaximumRecalculation {
            recomputeExtrema()
        } else {
            minimum = min(minimum ?? element.value, element.value)
            maximum = max(maximum ?? element.value, element.value)
        }
    }

    var statistics: SensorStatistics? {
        guard count > 0,
              let latest = storage[(nextWriteIndex - 1 + capacity) % capacity],
              let minimum,
              let maximum
        else { return nil }

        return SensorStatistics(
            sampleCount: count,
            latest: latest.value,
            minimum: minimum,
            maximum: maximum,
            average: total / Double(count)
        )
    }

    var elements: [SensorSamplePoint] {
        guard count > 0 else { return [] }

        if count < capacity {
            return storage.prefix(count).compactMap { $0 }
        }

        return (storage[nextWriteIndex...] + storage[..<nextWriteIndex]).compactMap { $0 }
    }

    private func recomputeExtrema() {
        minimum = nil
        maximum = nil

        for point in storage.compactMap({ $0 }) {
            minimum = min(minimum ?? point.value, point.value)
            maximum = max(maximum ?? point.value, point.value)
        }
    }
}
