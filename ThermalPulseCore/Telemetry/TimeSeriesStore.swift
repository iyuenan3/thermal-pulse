import Foundation

public actor TimeSeriesStore {
    public let capacityPerSeries: Int

    private var buffers: [SMCKey: FixedRingBuffer<SensorSamplePoint>] = [:]
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
            var buffer = buffers[key] ?? FixedRingBuffer(capacity: capacityPerSeries)
            buffer.append(SensorSamplePoint(timestamp: frame.timestamp, value: value))
            buffers[key] = buffer
        }
    }

    public func summary() -> TelemetrySummarySnapshot {
        var series: [SMCKey: SensorSeriesSummary] = [:]

        for (key, buffer) in buffers {
            let points = buffer.elements
            guard let latest = points.last else { continue }

            var minimum = latest.value
            var maximum = latest.value
            var total = 0.0
            for point in points {
                minimum = min(minimum, point.value)
                maximum = max(maximum, point.value)
                total += point.value
            }
            let statistics = SensorStatistics(
                sampleCount: points.count,
                latest: latest.value,
                minimum: minimum,
                maximum: maximum,
                average: total / Double(points.count)
            )
            guard let descriptor = descriptors[key] else { continue }
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
}

private struct FixedRingBuffer<Element: Sendable>: Sendable {
    let capacity: Int

    private var storage: [Element?]
    private var nextWriteIndex = 0
    private(set) var count = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = Array(repeating: nil, count: max(1, capacity))
    }

    mutating func append(_ element: Element) {
        storage[nextWriteIndex] = element
        nextWriteIndex = (nextWriteIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    var elements: [Element] {
        guard count > 0 else { return [] }

        if count < capacity {
            return storage.prefix(count).compactMap { $0 }
        }

        return (storage[nextWriteIndex...] + storage[..<nextWriteIndex]).compactMap { $0 }
    }
}
