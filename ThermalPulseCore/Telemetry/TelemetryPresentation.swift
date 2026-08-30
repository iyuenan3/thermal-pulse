import Foundation

public struct TemperatureFamilySummary: Equatable, Sendable {
    public let sensorCount: Int
    public let average: Double
    public let maximum: Double
    public let hottestKey: SMCKey

    public init(
        sensorCount: Int,
        average: Double,
        maximum: Double,
        hottestKey: SMCKey
    ) {
        self.sensorCount = sensorCount
        self.average = average
        self.maximum = maximum
        self.hottestKey = hottestKey
    }

    public var reportedValue: Double { maximum }
}

public enum ComponentTemperature: String, CaseIterable, Sendable {
    case performanceCore
    case efficiencyCore
    case battery
}

public struct ComponentTemperatureSummary: Equatable, Sendable {
    public let component: ComponentTemperature
    public let sensorCount: Int
    public let average: Double
    public let maximum: Double
    public let representativeKey: SMCKey

    public init(
        component: ComponentTemperature,
        sensorCount: Int,
        average: Double,
        maximum: Double,
        representativeKey: SMCKey
    ) {
        self.component = component
        self.sensorCount = sensorCount
        self.average = average
        self.maximum = maximum
        self.representativeKey = representativeKey
    }

    public var reportedValue: Double {
        switch component {
        case .performanceCore, .efficiencyCore:
            maximum
        case .battery:
            average
        }
    }
}

public enum ComponentTemperaturePolicy {
    private static let batteryKeys = Set(["TB1T", "TB2T"])

    public static func matchingReadings(
        for component: ComponentTemperature,
        from readings: [SensorReading]
    ) -> [SensorReading] {
        readings.filter { reading in
            guard reading.validity == .valid,
                  reading.descriptor.kind == .temperatureCandidate,
                  reading.descriptor.unit == .celsius,
                  reading.value?.isFinite == true
            else { return false }

            let key = reading.descriptor.key.rawValue
            switch component {
            case .performanceCore:
                return key.hasPrefix("Tp")
                    && normalizedDataType(reading.dataType) == "flt"
                    && reading.value.map(Self.isPlausibleCoreTemperature) == true
            case .efficiencyCore:
                return key.hasPrefix("Te")
                    && normalizedDataType(reading.dataType) == "flt"
                    && reading.value.map(Self.isPlausibleCoreTemperature) == true
            case .battery:
                return batteryKeys.contains(key)
            }
        }.sorted { $0.descriptor.key < $1.descriptor.key }
    }

    public static func summary(
        for component: ComponentTemperature,
        from readings: [SensorReading]
    ) -> ComponentTemperatureSummary? {
        let candidates = matchingReadings(for: component, from: readings).compactMap {
            reading -> (key: SMCKey, value: Double)? in
            guard let value = reading.value else { return nil }
            return (reading.descriptor.key, value)
        }
        guard let hottest = candidates.max(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }) else { return nil }

        return ComponentTemperatureSummary(
            component: component,
            sensorCount: candidates.count,
            average: candidates.reduce(0) { $0 + $1.value } / Double(candidates.count),
            maximum: hottest.value,
            representativeKey: hottest.key
        )
    }

    public static func summaries(from readings: [SensorReading]) -> [ComponentTemperatureSummary] {
        ComponentTemperature.allCases.compactMap { summary(for: $0, from: readings) }
    }

    public static func displayHistoryPoints(
        for component: ComponentTemperature,
        from points: [SensorSamplePoint]
    ) -> [SensorSamplePoint] {
        points.filter { point in
            guard point.value.isFinite else { return false }
            switch component {
            case .performanceCore, .efficiencyCore:
                return isPlausibleCoreTemperature(point.value)
            case .battery:
                return true
            }
        }
    }

    private static func normalizedDataType(_ dataType: SMCDataType) -> String {
        dataType.normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlausibleCoreTemperature(_ value: Double) -> Bool {
        (10...120).contains(value)
    }
}

public enum MenuBarFanColumnLayout: Equatable, Sendable {
    case centered(String)
    case stacked(top: String, bottom: String)
}

public enum MenuBarFanColumnPolicy {
    public static func layout(from fanTexts: [String]) -> MenuBarFanColumnLayout {
        let values = fanTexts.prefix(2).map(compactValue)
        switch values.count {
        case 0:
            return .centered("--")
        case 1:
            return .centered(values[0])
        default:
            return .stacked(top: values[0], bottom: values[1])
        }
    }

    private static func compactValue(_ text: String) -> String {
        text.split(separator: " ", maxSplits: 1).last.map(String.init) ?? "--"
    }
}

public enum PerformanceCoreTemperaturePolicy {
    public static func matchingReadings(from readings: [SensorReading]) -> [SensorReading] {
        readings.filter { reading in
            reading.validity == .valid
                && reading.descriptor.kind == .temperatureCandidate
                && reading.descriptor.unit == .celsius
                && reading.descriptor.key.rawValue.hasPrefix("Tp")
                && normalizedDataType(reading.dataType) == "flt"
                && reading.value.map { $0.isFinite && (10...120).contains($0) } == true
        }.sorted { $0.descriptor.key < $1.descriptor.key }
    }

    public static func summary(from readings: [SensorReading]) -> TemperatureFamilySummary? {
        let candidates = matchingReadings(from: readings).compactMap { reading -> (key: SMCKey, value: Double)? in
            guard let value = reading.value else { return nil }
            return (key: reading.descriptor.key, value: value)
        }

        guard let hottest = candidates.max(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }) else {
            return nil
        }

        return TemperatureFamilySummary(
            sensorCount: candidates.count,
            average: candidates.reduce(0) { $0 + $1.value } / Double(candidates.count),
            maximum: hottest.value,
            hottestKey: hottest.key
        )
    }

    private static func normalizedDataType(_ dataType: SMCDataType) -> String {
        dataType.normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum SensorSelectionPolicy {
    public static func defaultKeys(
        from readings: [SensorReading],
        limit: Int
    ) -> Set<SMCKey> {
        guard limit > 0 else { return [] }

        let fanKeys = readings.lazy
            .filter {
                $0.validity == .valid
                    && $0.descriptor.kind == .fanActualSpeed
                    && $0.descriptor.evidence == .runtimeValidated
            }
            .map(\.descriptor.key)
            .sorted()

        var selectedKeys = Set(fanKeys.prefix(limit))
        guard selectedKeys.count < limit else { return selectedKeys }

        let hottestTemperatureKey = PerformanceCoreTemperaturePolicy.summary(from: readings)?.hottestKey
            ?? readings
            .filter {
                $0.validity == .valid
                    && $0.descriptor.kind == .temperatureCandidate
                    && $0.descriptor.evidence == .rawUnverified
                    && $0.value?.isFinite == true
            }
            .sorted { lhs, rhs in
                let lhsValue = lhs.value ?? -Double.infinity
                let rhsValue = rhs.value ?? -Double.infinity
                if lhsValue == rhsValue {
                    return lhs.descriptor.key < rhs.descriptor.key
                }
                return lhsValue > rhsValue
            }
            .first?
            .descriptor.key

        if let hottestTemperatureKey {
            selectedKeys.insert(hottestTemperatureKey)
        }
        return selectedKeys
    }

    public static func toggled(
        _ key: SMCKey,
        in selection: Set<SMCKey>,
        availableKeys: Set<SMCKey>,
        limit: Int
    ) -> Set<SMCKey> {
        if selection.contains(key) {
            return selection.subtracting([key])
        }

        guard limit > 0,
              selection.count < limit,
              availableKeys.contains(key)
        else {
            return selection
        }

        return selection.union([key])
    }
}

public enum TelemetryDisplayReducer {
    public static func reduce(
        _ points: [SensorSamplePoint],
        maximumPointCount: Int
    ) -> [SensorSamplePoint] {
        guard maximumPointCount > 0, !points.isEmpty else { return [] }
        guard points.count > maximumPointCount else { return points }

        switch maximumPointCount {
        case 1:
            return [points[points.count - 1]]
        case 2:
            return [points[0], points[points.count - 1]]
        case 3:
            return [points[0], mostSalientPoint(in: points), points[points.count - 1]]
        default:
            break
        }

        let interiorCount = points.count - 2
        let bucketCount = max(1, (maximumPointCount - 2) / 2)
        var reduced = [points[0]]
        reduced.reserveCapacity(maximumPointCount)

        for bucketIndex in 0..<bucketCount {
            let start = 1 + (bucketIndex * interiorCount / bucketCount)
            let end = 1 + ((bucketIndex + 1) * interiorCount / bucketCount)
            guard start < end else { continue }

            var minimumIndex = start
            var maximumIndex = start
            for index in (start + 1)..<end {
                if points[index].value < points[minimumIndex].value {
                    minimumIndex = index
                }
                if points[index].value > points[maximumIndex].value {
                    maximumIndex = index
                }
            }

            if minimumIndex == maximumIndex {
                reduced.append(points[minimumIndex])
            } else {
                for index in [minimumIndex, maximumIndex].sorted() {
                    reduced.append(points[index])
                }
            }
        }

        reduced.append(points[points.count - 1])
        return reduced
    }

    public static func reduceSegments(
        _ points: [SensorSamplePoint],
        maximumPointCount: Int,
        maximumGap: TimeInterval
    ) -> [[SensorSamplePoint]] {
        guard maximumPointCount > 0 else { return [] }
        let segments = split(points, maximumGap: maximumGap)
        guard !segments.isEmpty else { return [] }
        guard points.count > maximumPointCount else { return segments }

        if segments.count >= maximumPointCount {
            if maximumPointCount == 1 {
                return [[segments[segments.count - 1].last!]]
            }

            return (0..<maximumPointCount).map { index in
                let segmentIndex = index * (segments.count - 1) / (maximumPointCount - 1)
                return [segments[segmentIndex].last!]
            }
        }

        var allocations = Array(repeating: 1, count: segments.count)
        var remaining = maximumPointCount - segments.count
        let totalCount = segments.reduce(0) { $0 + $1.count }

        for index in segments.indices where remaining > 0 {
            let proportional = remaining * segments[index].count / totalCount
            let added = min(proportional, segments[index].count - 1)
            allocations[index] += added
        }

        remaining = maximumPointCount - allocations.reduce(0, +)
        let rankedIndices = segments.indices.sorted {
            let lhsRemaining = segments[$0].count - allocations[$0]
            let rhsRemaining = segments[$1].count - allocations[$1]
            if lhsRemaining == rhsRemaining { return $0 < $1 }
            return lhsRemaining > rhsRemaining
        }

        for index in rankedIndices where remaining > 0 {
            let available = segments[index].count - allocations[index]
            guard available > 0 else { continue }
            let added = min(available, remaining)
            allocations[index] += added
            remaining -= added
        }

        return zip(segments, allocations).map { segment, allocation in
            reduce(segment, maximumPointCount: allocation)
        }
    }

    private static func split(
        _ points: [SensorSamplePoint],
        maximumGap: TimeInterval
    ) -> [[SensorSamplePoint]] {
        guard let first = points.first else { return [] }

        var segments: [[SensorSamplePoint]] = []
        var current = [first]

        for point in points.dropFirst() {
            if let previous = current.last,
               point.timestamp.timeIntervalSince(previous.timestamp) > maximumGap
            {
                segments.append(current)
                current = [point]
            } else {
                current.append(point)
            }
        }

        segments.append(current)
        return segments
    }

    private static func mostSalientPoint(in points: [SensorSamplePoint]) -> SensorSamplePoint {
        let first = points[0]
        let last = points[points.count - 1]
        let duration = last.timestamp.timeIntervalSince(first.timestamp)

        return points[1..<(points.count - 1)].max { lhs, rhs in
            deviation(of: lhs, from: first, to: last, duration: duration)
                < deviation(of: rhs, from: first, to: last, duration: duration)
        }!
    }

    private static func deviation(
        of point: SensorSamplePoint,
        from first: SensorSamplePoint,
        to last: SensorSamplePoint,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0 else { return abs(point.value - first.value) }
        let fraction = point.timestamp.timeIntervalSince(first.timestamp) / duration
        let expected = first.value + ((last.value - first.value) * fraction)
        return abs(point.value - expected)
    }
}
