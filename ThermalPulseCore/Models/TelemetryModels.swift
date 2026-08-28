import Foundation

public enum SystemThermalState: String, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

public struct SMCBatchSample: Sendable {
    public let readings: [SensorReading]
    public let failedReadCount: Int

    public init(readings: [SensorReading], failedReadCount: Int) {
        self.readings = readings
        self.failedReadCount = failedReadCount
    }
}

public struct TelemetryFrame: Sendable {
    public let timestamp: Date
    public let thermalState: SystemThermalState
    public let readings: [SensorReading]
    public let failedReadCount: Int

    public init(
        timestamp: Date,
        thermalState: SystemThermalState,
        readings: [SensorReading],
        failedReadCount: Int
    ) {
        self.timestamp = timestamp
        self.thermalState = thermalState
        self.readings = readings
        self.failedReadCount = failedReadCount
    }
}

public struct SensorSamplePoint: Equatable, Sendable {
    public let timestamp: Date
    public let value: Double

    public init(timestamp: Date, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

public struct SensorStatistics: Equatable, Sendable {
    public let sampleCount: Int
    public let latest: Double
    public let minimum: Double
    public let maximum: Double
    public let average: Double

    public init(
        sampleCount: Int,
        latest: Double,
        minimum: Double,
        maximum: Double,
        average: Double
    ) {
        self.sampleCount = sampleCount
        self.latest = latest
        self.minimum = minimum
        self.maximum = maximum
        self.average = average
    }
}

public struct SensorSeriesSummary: Sendable {
    public let descriptor: SensorDescriptor
    public let statistics: SensorStatistics

    public init(descriptor: SensorDescriptor, statistics: SensorStatistics) {
        self.descriptor = descriptor
        self.statistics = statistics
    }
}

public struct TelemetrySummarySnapshot: Sendable {
    public let latestFrame: TelemetryFrame?
    public let series: [SMCKey: SensorSeriesSummary]
    public let capacityPerSeries: Int

    public init(
        latestFrame: TelemetryFrame?,
        series: [SMCKey: SensorSeriesSummary],
        capacityPerSeries: Int
    ) {
        self.latestFrame = latestFrame
        self.series = series
        self.capacityPerSeries = capacityPerSeries
    }
}
