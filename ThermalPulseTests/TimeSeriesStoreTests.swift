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
