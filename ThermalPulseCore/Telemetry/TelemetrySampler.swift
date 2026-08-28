import Foundation

public protocol TelemetryReadingSource: Sendable {
    func scan() async throws -> SMCProbeSnapshot
    func sample(keys: [SMCKey]) async -> SMCBatchSample
}

extension SMCProbeService: TelemetryReadingSource {}

public protocol SamplingTicker: Sendable {
    func reset() async
    func waitForNextTick() async throws
}

public protocol TelemetryEnvironment: Sendable {
    func currentTimestamp() async -> Date
    func currentThermalState() async -> SystemThermalState
}

public actor IntervalSamplingTicker: SamplingTicker {
    private let interval: Duration
    private let clock = ContinuousClock()
    private var previousDeadline: ContinuousClock.Instant?

    public init(interval: Duration = .seconds(1)) {
        self.interval = interval
    }

    public func reset() {
        previousDeadline = nil
    }

    public func waitForNextTick() async throws {
        let now = clock.now
        guard let previousDeadline else {
            self.previousDeadline = now
            return
        }

        let candidate = previousDeadline.advanced(by: interval)
        let deadline = candidate > now ? candidate : now.advanced(by: interval)
        self.previousDeadline = deadline
        try await clock.sleep(until: deadline, tolerance: .milliseconds(20))
    }
}

public struct SystemTelemetryEnvironment: TelemetryEnvironment {
    public init() {}

    public func currentTimestamp() async -> Date {
        Date()
    }

    public func currentThermalState() async -> SystemThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}

public actor TelemetrySampler {
    public typealias UpdateHandler = @Sendable (TelemetrySummarySnapshot) async -> Void

    private let source: any TelemetryReadingSource
    private let ticker: any SamplingTicker
    private let environment: any TelemetryEnvironment
    private let store: TimeSeriesStore

    private var selectedKeys: [SMCKey] = []
    private var samplingTask: Task<Void, Never>?
    private var runID: UUID?

    public init(
        source: any TelemetryReadingSource,
        ticker: any SamplingTicker = IntervalSamplingTicker(),
        environment: any TelemetryEnvironment = SystemTelemetryEnvironment(),
        store: TimeSeriesStore = TimeSeriesStore()
    ) {
        self.source = source
        self.ticker = ticker
        self.environment = environment
        self.store = store
    }

    @discardableResult
    public func prepare() async throws -> SMCProbeSnapshot {
        stop()
        await ticker.reset()
        await store.reset()

        let snapshot = try await source.scan()
        selectedKeys = Self.makeSamplingKeys(from: snapshot)
        return snapshot
    }

    @discardableResult
    public func start(onUpdate: @escaping UpdateHandler) async throws -> SMCProbeSnapshot {
        let snapshot = try await prepare()
        let newRunID = UUID()
        runID = newRunID
        samplingTask = Task { [weak self] in
            await self?.run(id: newRunID, onUpdate: onUpdate)
        }
        return snapshot
    }

    public func stop() {
        runID = nil
        samplingTask?.cancel()
        samplingTask = nil
    }

    public func isRunning() -> Bool {
        samplingTask != nil
    }

    public func samplingKeys() -> [SMCKey] {
        selectedKeys
    }

    public func sampleOnce() async -> TelemetrySummarySnapshot {
        let batch = await source.sample(keys: selectedKeys)
        let frame = TelemetryFrame(
            timestamp: await environment.currentTimestamp(),
            thermalState: await environment.currentThermalState(),
            readings: batch.readings,
            failedReadCount: batch.failedReadCount
        )
        await store.append(frame)
        return await store.summary()
    }

    public func history(for key: SMCKey) async -> [SensorSamplePoint] {
        await store.history(for: key)
    }

    public func histories(
        for keys: [SMCKey],
        since cutoff: Date? = nil
    ) async -> [SMCKey: [SensorSamplePoint]] {
        await store.histories(for: keys, since: cutoff)
    }

    private func run(id: UUID, onUpdate: @escaping UpdateHandler) async {
        do {
            while !Task.isCancelled {
                try await ticker.waitForNextTick()
                try Task.checkCancellation()
                let snapshot = await sampleOnce()
                await onUpdate(snapshot)
            }
        } catch is CancellationError {
            // Expected when monitoring stops or restarts.
        } catch {
            // A ticker failure stops monitoring. Per-sensor failures stay inside the frame.
        }

        if runID == id {
            runID = nil
            samplingTask = nil
        }
    }

    private static func makeSamplingKeys(from snapshot: SMCProbeSnapshot) -> [SMCKey] {
        snapshot.readings.compactMap { reading -> SMCKey? in
            guard reading.validity == .valid else { return nil }
            switch reading.descriptor.kind {
            case .fanActualSpeed, .temperatureCandidate:
                return reading.descriptor.key
            case .fanMaximumSpeed, .metadata, .raw:
                return nil
            }
        }.sorted()
    }
}
