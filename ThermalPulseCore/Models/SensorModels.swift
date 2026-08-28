import Foundation

public enum SensorKind: String, Sendable {
    case temperatureCandidate
    case fanActualSpeed
    case fanMaximumSpeed
    case metadata
    case raw
}

public enum SensorUnit: String, Sendable {
    case celsius = "°C"
    case rpm = "RPM"
    case count = "个"
    case raw = "raw"
}

public enum SensorEvidence: String, Sendable {
    case runtimeValidated
    case rawUnverified
}

public enum SensorValidity: Equatable, Sendable {
    case valid
    case unavailable(String)
    case invalid(String)
}

public struct SensorDescriptor: Identifiable, Equatable, Sendable {
    public var id: SMCKey { key }
    public let key: SMCKey
    public let kind: SensorKind
    public let unit: SensorUnit
    public let evidence: SensorEvidence
    public let defaultVisible: Bool
    public let displayName: String?

    public init(
        key: SMCKey,
        kind: SensorKind,
        unit: SensorUnit,
        evidence: SensorEvidence,
        defaultVisible: Bool,
        displayName: String?
    ) {
        self.key = key
        self.kind = kind
        self.unit = unit
        self.evidence = evidence
        self.defaultVisible = defaultVisible
        self.displayName = displayName
    }
}

public struct SensorReading: Identifiable, Equatable, Sendable {
    public var id: SMCKey { descriptor.id }
    public let descriptor: SensorDescriptor
    public let value: Double?
    public let validity: SensorValidity
    public let dataType: SMCDataType

    public init(
        descriptor: SensorDescriptor,
        value: Double?,
        validity: SensorValidity,
        dataType: SMCDataType
    ) {
        self.descriptor = descriptor
        self.value = value
        self.validity = validity
        self.dataType = dataType
    }
}

public struct SMCProbeSnapshot: Sendable {
    public let timestamp: Date
    public let advertisedKeyCount: Int
    public let enumeratedKeyCount: Int
    public let metadataReadCount: Int
    public let sampledKeyCount: Int
    public let failedReadCount: Int
    public let fanCount: Int?
    public let readings: [SensorReading]

    public init(
        timestamp: Date,
        advertisedKeyCount: Int,
        enumeratedKeyCount: Int,
        metadataReadCount: Int,
        sampledKeyCount: Int,
        failedReadCount: Int,
        fanCount: Int?,
        readings: [SensorReading]
    ) {
        self.timestamp = timestamp
        self.advertisedKeyCount = advertisedKeyCount
        self.enumeratedKeyCount = enumeratedKeyCount
        self.metadataReadCount = metadataReadCount
        self.sampledKeyCount = sampledKeyCount
        self.failedReadCount = failedReadCount
        self.fanCount = fanCount
        self.readings = readings
    }
}

