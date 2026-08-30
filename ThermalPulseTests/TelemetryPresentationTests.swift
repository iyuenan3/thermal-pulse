import XCTest
@testable import ThermalPulseCore

final class TelemetryPresentationTests: XCTestCase {
    func testMenuBarFanColumnCentersZeroOrOneFan() {
        XCTAssertEqual(
            MenuBarFanColumnPolicy.layout(from: []),
            .centered("--")
        )
        XCTAssertEqual(
            MenuBarFanColumnPolicy.layout(from: ["F1 6559"]),
            .centered("6559")
        )
    }

    func testMenuBarFanColumnStacksOnlyTheFirstTwoDynamicFans() {
        XCTAssertEqual(
            MenuBarFanColumnPolicy.layout(from: ["F1 1200", "F2 1300"]),
            .stacked(top: "1200", bottom: "1300")
        )
        XCTAssertEqual(
            MenuBarFanColumnPolicy.layout(from: ["F1 1200", "F2 1300", "F3 1400"]),
            .stacked(top: "1200", bottom: "1300")
        )
    }

    func testPerformanceCoreSummaryUsesValidFloatTpFamilyOnly() throws {
        let readings = [
            reading(key: "Tp09", kind: .temperatureCandidate, evidence: .rawUnverified, value: 42),
            reading(key: "Tp10", kind: .temperatureCandidate, evidence: .rawUnverified, value: 66),
            reading(key: "Te09", kind: .temperatureCandidate, evidence: .rawUnverified, value: 90),
            reading(
                key: "Tp11",
                kind: .temperatureCandidate,
                evidence: .rawUnverified,
                value: 99,
                validity: .invalid("test")
            ),
            reading(
                key: "Tp12",
                kind: .temperatureCandidate,
                evidence: .rawUnverified,
                value: 88,
                dataType: "sp78"
            )
        ]

        let summary = try XCTUnwrap(PerformanceCoreTemperaturePolicy.summary(from: readings))

        XCTAssertEqual(summary.sensorCount, 2)
        XCTAssertEqual(summary.average, 54, accuracy: 0.001)
        XCTAssertEqual(summary.maximum, 66, accuracy: 0.001)
        XCTAssertEqual(summary.reportedValue, 66, accuracy: 0.001)
        XCTAssertEqual(summary.hottestKey.rawValue, "Tp10")
    }

    func testPerformanceCoreSummaryIsUnknownWithoutValidTpFloatReadings() {
        let readings = [
            reading(key: "Te09", kind: .temperatureCandidate, evidence: .rawUnverified),
            reading(
                key: "Tp09",
                kind: .temperatureCandidate,
                evidence: .rawUnverified,
                validity: .unavailable("test")
            )
        ]

        XCTAssertNil(PerformanceCoreTemperaturePolicy.summary(from: readings))
    }

    func testComponentTemperaturePolicyUsesOnlyNamedEvidenceFamilies() throws {
        let readings = [
            reading(key: "Tp09", kind: .temperatureCandidate, evidence: .rawUnverified, value: 48),
            reading(key: "Tp10", kind: .temperatureCandidate, evidence: .rawUnverified, value: 62),
            reading(key: "Te09", kind: .temperatureCandidate, evidence: .rawUnverified, value: 44),
            reading(key: "Te10", kind: .temperatureCandidate, evidence: .rawUnverified, value: 50),
            reading(key: "Tm0p", kind: .temperatureCandidate, evidence: .rawUnverified, value: 41),
            reading(key: "TH0x", kind: .temperatureCandidate, evidence: .rawUnverified, value: 35),
            reading(key: "TB1T", kind: .temperatureCandidate, evidence: .rawUnverified, value: 32),
            reading(key: "TB2T", kind: .temperatureCandidate, evidence: .rawUnverified, value: 34),
            reading(key: "TW0P", kind: .temperatureCandidate, evidence: .rawUnverified, value: 99),
        ]

        let performanceCore = try XCTUnwrap(
            ComponentTemperaturePolicy.summary(for: .performanceCore, from: readings)
        )
        let efficiencyCore = try XCTUnwrap(
            ComponentTemperaturePolicy.summary(for: .efficiencyCore, from: readings)
        )
        let battery = try XCTUnwrap(
            ComponentTemperaturePolicy.summary(for: .battery, from: readings)
        )

        XCTAssertEqual(performanceCore.average, 55, accuracy: 0.001)
        XCTAssertEqual(performanceCore.reportedValue, 62, accuracy: 0.001)
        XCTAssertEqual(performanceCore.representativeKey.rawValue, "Tp10")
        XCTAssertEqual(efficiencyCore.average, 47, accuracy: 0.001)
        XCTAssertEqual(efficiencyCore.reportedValue, 50, accuracy: 0.001)
        XCTAssertEqual(efficiencyCore.representativeKey.rawValue, "Te10")
        XCTAssertEqual(battery.average, 33, accuracy: 0.001)
        XCTAssertEqual(battery.reportedValue, 33, accuracy: 0.001)
        XCTAssertEqual(battery.representativeKey.rawValue, "TB2T")
    }

    func testCoreFamiliesIgnoreImplausibleIdleSentinels() throws {
        let readings = [
            reading(key: "Tp09", kind: .temperatureCandidate, evidence: .rawUnverified, value: 0),
            reading(key: "Tp10", kind: .temperatureCandidate, evidence: .rawUnverified, value: 48),
            reading(key: "Te09", kind: .temperatureCandidate, evidence: .rawUnverified, value: -10),
            reading(key: "Te10", kind: .temperatureCandidate, evidence: .rawUnverified, value: 44),
        ]

        let performanceCore = try XCTUnwrap(
            ComponentTemperaturePolicy.summary(for: .performanceCore, from: readings)
        )
        let efficiencyCore = try XCTUnwrap(
            ComponentTemperaturePolicy.summary(for: .efficiencyCore, from: readings)
        )

        XCTAssertEqual(performanceCore.sensorCount, 1)
        XCTAssertEqual(performanceCore.reportedValue, 48)
        XCTAssertEqual(efficiencyCore.sensorCount, 1)
        XCTAssertEqual(efficiencyCore.reportedValue, 44)
    }

    func testCoreChartHistoryDropsZeroSentinelsAndLeavesAVisibleGap() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        let points = [48.0, 0, 50].enumerated().map { index, value in
            SensorSamplePoint(
                timestamp: base.addingTimeInterval(Double(index)),
                value: value
            )
        }

        let displayed = ComponentTemperaturePolicy.displayHistoryPoints(
            for: .performanceCore,
            from: points
        )
        let segments = TelemetryDisplayReducer.reduceSegments(
            displayed,
            maximumPointCount: 10,
            maximumGap: 1.75
        )

        XCTAssertEqual(displayed.map(\.value), [48, 50])
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.flatMap { $0 }.map(\.value), [48, 50])
    }

    func testMissingEfficiencyCoreEvidenceRemainsUnavailable() {
        let readings = [
            reading(key: "Tp09", kind: .temperatureCandidate, evidence: .rawUnverified, value: 48),
            reading(key: "TH0x", kind: .temperatureCandidate, evidence: .rawUnverified, value: 35),
        ]

        XCTAssertNil(ComponentTemperaturePolicy.summary(for: .efficiencyCore, from: readings))
    }

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

    func testSelectionDefaultsToValidatedFansAndHottestTemperatureCandidate() throws {
        let fan0 = reading(key: "F0Ac", kind: .fanActualSpeed, evidence: .runtimeValidated)
        let fan1 = reading(key: "F1Ac", kind: .fanActualSpeed, evidence: .runtimeValidated)
        let coolerTemperature = reading(
            key: "Tp09",
            kind: .temperatureCandidate,
            evidence: .rawUnverified,
            value: 42
        )
        let hotterTemperature = reading(
            key: "Tp10",
            kind: .temperatureCandidate,
            evidence: .rawUnverified,
            value: 67
        )
        let invalidTemperature = reading(
            key: "Tp11",
            kind: .temperatureCandidate,
            evidence: .rawUnverified,
            value: 99,
            validity: .invalid("test")
        )
        let readings = [coolerTemperature, fan1, invalidTemperature, hotterTemperature, fan0]

        let defaults = SensorSelectionPolicy.defaultKeys(from: readings, limit: 6)
        XCTAssertEqual(defaults.map(\.rawValue).sorted(), ["F0Ac", "F1Ac", "Tp10"])

        let limitedDefaults = SensorSelectionPolicy.defaultKeys(from: readings, limit: 2)
        XCTAssertEqual(limitedDefaults.map(\.rawValue).sorted(), ["F0Ac", "F1Ac"])

        let temperatureKey = try XCTUnwrap(SMCKey(rawValue: "Tp09"))
        let available = Set(readings.map(\.descriptor.key))
        let fullSelection = SensorSelectionPolicy.toggled(
            temperatureKey,
            in: limitedDefaults,
            availableKeys: available,
            limit: 2
        )
        XCTAssertEqual(fullSelection, limitedDefaults)

        let removed = SensorSelectionPolicy.toggled(
            try XCTUnwrap(SMCKey(rawValue: "F0Ac")),
            in: limitedDefaults,
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
        evidence: SensorEvidence,
        value: Double = 42,
        validity: SensorValidity = .valid,
        dataType: String = "flt "
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
            value: value,
            validity: validity,
            dataType: SMCDataType(rawValue: dataType)!
        )
    }
}
