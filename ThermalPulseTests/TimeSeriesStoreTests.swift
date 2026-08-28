import XCTest
@testable import ThermalPulseCore

final class TimeSeriesStoreTests: XCTestCase {
    func testEvictsOldestPointAndComputesStatistics() async throws {
        let store = TimeSeriesStore(capacityPerSeries: 3)
        let base = Date(timeIntervalSince1970: 1_000)

        for value in 1...4 {
            await store.append(
                frame(
                    timestamp: base.addingTimeInterval(Double(value)),
                    readings: [reading(key: "F0Ac", value: Double(value))]
                )
            )
        }

        let key = try XCTUnwrap(SMCKey(rawValue: "F0Ac"))
        let summary = await store.summary()
        let statistics = try XCTUnwrap(summary.series[key]?.statistics)
        XCTAssertEqual(statistics.sampleCount, 3)
        XCTAssertEqual(statistics.latest, 4)
        XCTAssertEqual(statistics.minimum, 2)
        XCTAssertEqual(statistics.maximum, 4)
        XCTAssertEqual(statistics.average, 3, accuracy: 0.0001)

        let history = await store.history(for: key)
        XCTAssertEqual(history.map(\.value), [2, 3, 4])
    }

    func testUnavailableReadingDoesNotPolluteHistory() async throws {
        let store = TimeSeriesStore(capacityPerSeries: 3)
        let key = try XCTUnwrap(SMCKey(rawValue: "F0Ac"))
        await store.append(frame(timestamp: Date(), readings: [reading(key: "F0Ac", value: 1_500)]))

        let unavailable = SensorReading(
            descriptor: descriptor(key: key),
            value: nil,
            validity: .unavailable("测试读取失败"),
            dataType: SMCDataType(rawValue: "flt ")!
        )
        await store.append(frame(timestamp: Date(), readings: [unavailable], failedReadCount: 1))

        let summary = await store.summary()
        XCTAssertEqual(summary.latestFrame?.failedReadCount, 1)
        XCTAssertEqual(summary.series[key]?.statistics.sampleCount, 1)
        XCTAssertEqual(summary.series[key]?.statistics.latest, 1_500)
    }

    func testHistoriesReturnOnlyRequestedKeysInsideCutoff() async throws {
        let store = TimeSeriesStore(capacityPerSeries: 10)
        let base = Date(timeIntervalSince1970: 3_000)
        let fan0 = try XCTUnwrap(SMCKey(rawValue: "F0Ac"))
        let fan1 = try XCTUnwrap(SMCKey(rawValue: "F1Ac"))

        for second in 0..<5 {
            await store.append(
                frame(
                    timestamp: base.addingTimeInterval(Double(second)),
                    readings: [
                        reading(key: fan0.rawValue, value: Double(second)),
                        reading(key: fan1.rawValue, value: Double(second + 100)),
                    ]
                )
            )
        }

        let histories = await store.histories(
            for: [fan0],
            since: base.addingTimeInterval(2)
        )

        XCTAssertEqual(Set(histories.keys), Set([fan0]))
        XCTAssertEqual(histories[fan0]?.map(\.value), [2, 3, 4])
    }

    func testOneHourAtOneHertzAcrossCurrentMachineScaleStaysBounded() async throws {
        let store = TimeSeriesStore()
        let base = Date(timeIntervalSince1970: 4_000)
        let sensorCount = 312
        let keys = try (0..<sensorCount).map { index in
            try XCTUnwrap(SMCKey(rawValue: String(format: "T%03X", index)))
        }

        for second in 0...3_600 {
            let readings = keys.enumerated().map { index, key in
                reading(key: key.rawValue, value: Double(second) + Double(index) / 1_000)
            }
            await store.append(
                frame(
                    timestamp: base.addingTimeInterval(Double(second)),
                    readings: readings
                )
            )
            _ = await store.summary()
        }

        let summary = await store.summary()
        let firstStatistics = try XCTUnwrap(summary.series[keys[0]]?.statistics)
        XCTAssertEqual(summary.series.count, sensorCount)
        XCTAssertEqual(firstStatistics.sampleCount, 3_600)
        XCTAssertEqual(firstStatistics.minimum, 1)
        XCTAssertEqual(firstStatistics.maximum, 3_600)
        XCTAssertEqual(firstStatistics.average, 1_800.5, accuracy: 0.0001)

        let selectedHistory = await store.histories(
            for: [keys[0], keys[1]],
            since: base.addingTimeInterval(3_591)
        )
        XCTAssertEqual(selectedHistory[keys[0]]?.count, 10)
        XCTAssertEqual(selectedHistory[keys[1]]?.count, 10)
    }

    private func frame(
        timestamp: Date,
        readings: [SensorReading],
        failedReadCount: Int = 0
    ) -> TelemetryFrame {
        TelemetryFrame(
            timestamp: timestamp,
            thermalState: .nominal,
            readings: readings,
            failedReadCount: failedReadCount
        )
    }

    private func reading(key: String, value: Double) -> SensorReading {
        let smcKey = SMCKey(rawValue: key)!
        return SensorReading(
            descriptor: descriptor(key: smcKey),
            value: value,
            validity: .valid,
            dataType: SMCDataType(rawValue: "flt ")!
        )
    }

    private func descriptor(key: SMCKey) -> SensorDescriptor {
        SensorDescriptor(
            key: key,
            kind: .fanActualSpeed,
            unit: .rpm,
            evidence: .runtimeValidated,
            defaultVisible: true,
            displayName: "测试风扇"
        )
    }
}
