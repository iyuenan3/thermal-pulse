import Foundation

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

        let hottestTemperatureKey = readings
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
