import XCTest
@testable import ThermalPulseCore

final class TelemetrySamplerTests: XCTestCase {
    func testPrepareBuildsStableDynamicSamplingAllowlist() async throws {
        let source = FakeTelemetryReadingSource(catalog: makeCatalog(), batch: makeBatch())
        let sampler = TelemetrySampler(
            source: source,
            ticker: SuspendingTicker(),
            environment: FixedTelemetryEnvironment(),
            store: TimeSeriesStore(capacityPerSeries: 3)
        )

        _ = try await sampler.prepare()
        let keys = await sampler.samplingKeys().map(\.rawValue)

        XCTAssertEqual(keys, ["F0Ac", "Tp09"])
    }

    func testSampleOnceIsolatesFailureAndStoresValidSeries() async throws {
        let source = FakeTelemetryReadingSource(catalog: makeCatalog(), batch: makeBatch())
        let sampler = TelemetrySampler(
            source: source,
            ticker: SuspendingTicker(),
            environment: FixedTelemetryEnvironment(),
            store: TimeSeriesStore(capacityPerSeries: 3)
        )

        _ = try await sampler.prepare()
        let summary = await sampler.sampleOnce()
        let requests = await source.sampleRequests()
        let fanKey = try XCTUnwrap(SMCKey(rawValue: "F0Ac"))
        let temperatureKey = try XCTUnwrap(SMCKey(rawValue: "Tp09"))

        XCTAssertEqual(requests, [[fanKey, temperatureKey]])
        XCTAssertEqual(summary.latestFrame?.failedReadCount, 1)
        XCTAssertEqual(summary.latestFrame?.thermalState, .fair)
        XCTAssertEqual(summary.series[fanKey]?.statistics.latest, 1_500)
        XCTAssertNil(summary.series[temperatureKey])
    }

    func testStopClearsRunningState() async throws {
        let source = FakeTelemetryReadingSource(catalog: makeCatalog(), batch: makeBatch())
        let sampler = TelemetrySampler(
            source: source,
            ticker: SuspendingTicker(),
            environment: FixedTelemetryEnvironment(),
            store: TimeSeriesStore(capacityPerSeries: 3)
        )

        _ = try await sampler.start { _ in }
        let runningBeforeStop = await sampler.isRunning()
        await sampler.stop()
        let runningAfterStop = await sampler.isRunning()

        XCTAssertTrue(runningBeforeStop)
        XCTAssertFalse(runningAfterStop)
    }

    private func makeCatalog() -> SMCProbeSnapshot {
        SMCProbeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            advertisedKeyCount: 4,
            enumeratedKeyCount: 4,
            metadataReadCount: 4,
            sampledKeyCount: 4,
            failedReadCount: 0,
            fanCount: 1,
            readings: [
                reading(key: "F0Ac", kind: .fanActualSpeed, value: 1_400),
                reading(key: "F0Mx", kind: .fanMaximumSpeed, value: 5_700),
                reading(key: "Tp09", kind: .temperatureCandidate, value: 42),
                reading(
                    key: "Tp10",
                    kind: .temperatureCandidate,
                    value: 200,
                    validity: .invalid("超出合理范围")
                ),
            ]
        )
    }

    private func makeBatch() -> SMCBatchSample {
        SMCBatchSample(
            readings: [
                reading(key: "F0Ac", kind: .fanActualSpeed, value: 1_500),
                reading(
                    key: "Tp09",
                    kind: .temperatureCandidate,
                    value: nil,
                    validity: .unavailable("本轮读取失败")
                ),
            ],
            failedReadCount: 1
        )
    }

    private func reading(
        key: String,
        kind: SensorKind,
        value: Double?,
        validity: SensorValidity = .valid
    ) -> SensorReading {
        let smcKey = SMCKey(rawValue: key)!
        let descriptor = SensorDescriptor(
            key: smcKey,
            kind: kind,
            unit: kind == .temperatureCandidate ? .celsius : .rpm,
            evidence: kind == .temperatureCandidate ? .rawUnverified : .runtimeValidated,
            defaultVisible: kind != .temperatureCandidate,
            displayName: kind == .temperatureCandidate ? nil : key
        )
        return SensorReading(
            descriptor: descriptor,
            value: value,
            validity: validity,
            dataType: SMCDataType(rawValue: "flt ")!
        )
    }
}

private actor FakeTelemetryReadingSource: TelemetryReadingSource {
    private let catalog: SMCProbeSnapshot
    private let batch: SMCBatchSample
    private var requests: [[SMCKey]] = []

    init(catalog: SMCProbeSnapshot, batch: SMCBatchSample) {
        self.catalog = catalog
        self.batch = batch
    }

    func scan() async throws -> SMCProbeSnapshot {
        catalog
    }

    func sample(keys: [SMCKey]) async -> SMCBatchSample {
        requests.append(keys)
        return batch
    }

    func sampleRequests() -> [[SMCKey]] {
        requests
    }
}

private struct FixedTelemetryEnvironment: TelemetryEnvironment {
    func currentTimestamp() async -> Date {
        Date(timeIntervalSince1970: 2_000)
    }

    func currentThermalState() async -> SystemThermalState {
        .fair
    }
}

private struct SuspendingTicker: SamplingTicker {
    func reset() async {}

    func waitForNextTick() async throws {
        try await Task.sleep(for: .seconds(60))
    }
}
