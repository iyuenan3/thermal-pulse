import XCTest
@testable import ThermalPulseCore

final class TelemetryPresentationTests: XCTestCase {
    func testReducerPreservesEndpointsAndExtremaWithinBudget() {
        let base = Date(timeIntervalSince1970: 1_000)
        var points = (0..<1_000).map { index in
            SensorSamplePoint(
                timestamp: base.addingTimeInterval(Double(index)),
                value: 50
            )
        }
        points[333] = SensorSamplePoint(
            timestamp: points[333].timestamp,
            value: -100
        )
        points[777] = SensorSamplePoint(
            timestamp: points[777].timestamp,
            value: 200
        )

        let reduced = TelemetryDisplayReducer.reduce(points, maximumPointCount: 120)

        XCTAssertLessThanOrEqual(reduced.count, 120)
        XCTAssertEqual(reduced.first, points.first)
        XCTAssertEqual(reduced.last, points.last)
        XCTAssertTrue(reduced.contains { $0.value == -100 })
        XCTAssertTrue(reduced.contains { $0.value == 200 })
        XCTAssertEqual(reduced.map(\.timestamp), reduced.map(\.timestamp).sorted())
    }

    func testReducerKeepsSamplingGapsAsSeparateBoundedSegments() throws {
        let base = Date(timeIntervalSince1970: 2_000)
        let points = [0, 1, 2, 10, 11].map { second in
            SensorSamplePoint(
                timestamp: base.addingTimeInterval(Double(second)),
                value: Double(second)
            )
        }

        let segments = TelemetryDisplayReducer.reduceSegments(
            points,
            maximumPointCount: 4,
            maximumGap: 1.75
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertLessThanOrEqual(segments.flatMap { $0 }.count, 4)
        XCTAssertEqual(segments[0].first?.timestamp, points[0].timestamp)
        XCTAssertEqual(segments[1].last?.timestamp, points[4].timestamp)
        XCTAssertGreaterThan(
            try XCTUnwrap(segments[1].first?.timestamp).timeIntervalSince(
                try XCTUnwrap(segments[0].last?.timestamp)
            ),
            1.75
        )
    }

    func testSelectionDefaultsToValidatedFansAndEnforcesLimit() throws {
        let fan0 = reading(key: "F0Ac", kind: .fanActualSpeed, evidence: .runtimeValidated)
        let fan1 = reading(key: "F1Ac", kind: .fanActualSpeed, evidence: .runtimeValidated)
        let temperature = reading(
            key: "Tp09",
            kind: .temperatureCandidate,
            evidence: .rawUnverified
        )
        let readings = [temperature, fan1, fan0]

        let defaults = SensorSelectionPolicy.defaultKeys(from: readings, limit: 6)
        XCTAssertEqual(defaults.map(\.rawValue).sorted(), ["F0Ac", "F1Ac"])

        let temperatureKey = try XCTUnwrap(SMCKey(rawValue: "Tp09"))
        let available = Set(readings.map(\.descriptor.key))
        let fullSelection = SensorSelectionPolicy.toggled(
            temperatureKey,
            in: defaults,
            availableKeys: available,
            limit: 2
        )
        XCTAssertEqual(fullSelection, defaults)

        let removed = SensorSelectionPolicy.toggled(
            try XCTUnwrap(SMCKey(rawValue: "F0Ac")),
            in: defaults,
            availableKeys: available,
            limit: 2
        )
        let added = SensorSelectionPolicy.toggled(
            temperatureKey,
            in: removed,
            availableKeys: available,
            limit: 2
        )
        XCTAssertTrue(added.contains(temperatureKey))
        XCTAssertEqual(added.count, 2)
    }

    private func reading(
        key: String,
        kind: SensorKind,
        evidence: SensorEvidence
    ) -> SensorReading {
        let smcKey = SMCKey(rawValue: key)!
        return SensorReading(
            descriptor: SensorDescriptor(
                key: smcKey,
                kind: kind,
                unit: kind == .temperatureCandidate ? .celsius : .rpm,
                evidence: evidence,
                defaultVisible: kind == .fanActualSpeed,
                displayName: nil
            ),
            value: 42,
            validity: .valid,
            dataType: SMCDataType(rawValue: "flt ")!
        )
    }
}
