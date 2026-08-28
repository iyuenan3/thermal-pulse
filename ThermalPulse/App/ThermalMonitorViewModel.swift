import Foundation
import ThermalPulseCore

enum MonitoringWindow: Int, CaseIterable, Identifiable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3_600

    var id: Int { rawValue }
    var duration: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .fiveMinutes: "5 分钟"
        case .fifteenMinutes: "15 分钟"
        case .oneHour: "1 小时"
        }
    }
}

struct SensorChartSeries: Identifiable {
    var id: SMCKey { descriptor.key }
    let descriptor: SensorDescriptor
    let points: [SensorSamplePoint]

    var label: String {
        descriptor.displayName ?? descriptor.key.rawValue
    }
}

@MainActor
final class ThermalMonitorViewModel: ObservableObject {
    static let maximumChartSeriesCount = 6

    @Published private(set) var snapshot: SMCProbeSnapshot?
    @Published private(set) var telemetry: TelemetrySummarySnapshot?
    @Published private(set) var selectedSensorKeys: Set<SMCKey> = []
    @Published private(set) var monitoringWindow: MonitoringWindow = .fiveMinutes
    @Published private(set) var chartHistories: [SMCKey: [SensorSamplePoint]] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?

    private var sampler: TelemetrySampler?
    private var samplingGeneration = UUID()
    private var hasStarted = false

    var statusText: String {
        if isScanning { return "正在以普通权限读取 AppleSMC" }
        if let errorMessage { return errorMessage }
        if let telemetry, let frame = telemetry.latestFrame {
            let longestSeries = telemetry.series.values.map(\.statistics.sampleCount).max() ?? 0
            let failureText = frame.failedReadCount == 0 ? "" : "，本轮 \(frame.failedReadCount) 项失败"
            return "每秒采样 \(frame.readings.count) 项，历史 \(longestSeries)/\(telemetry.capacityPerSeries) 点\(failureText)"
        }
        guard let snapshot else { return "等待首次只读探测" }
        return "已建立 \(snapshot.sampledKeyCount) 个候选项的只读目录"
    }

    var menuBarSummary: String {
        let parts: [String] = visibleFanReadings.compactMap { reading -> String? in
            guard reading.validity == .valid, let value = reading.value else { return nil }
            return "\(reading.descriptor.key.rawValue) \(Int(value.rounded())) RPM"
        }
        return parts.isEmpty ? "ThermalPulse" : parts.joined(separator: " · ")
    }

    var visibleFanReadings: [SensorReading] {
        currentReadings.filter { $0.descriptor.kind == .fanActualSpeed }
    }

    var temperatureCandidates: [SensorReading] {
        currentReadings.filter { $0.descriptor.kind == .temperatureCandidate }
    }

    var availableChartSensors: [SensorReading] {
        (snapshot?.readings ?? []).filter { reading in
            guard reading.validity == .valid else { return false }
            switch reading.descriptor.kind {
            case .fanActualSpeed, .temperatureCandidate:
                return true
            case .fanMaximumSpeed, .metadata, .raw:
                return false
            }
        }.sorted { $0.descriptor.key < $1.descriptor.key }
    }

    var chartSeries: [SensorChartSeries] {
        availableChartSensors.compactMap { reading in
            let key = reading.descriptor.key
            guard selectedSensorKeys.contains(key),
                  let points = chartHistories[key],
                  !points.isEmpty
            else { return nil }

            return SensorChartSeries(descriptor: reading.descriptor, points: points)
        }
    }

    var thermalState: SystemThermalState {
        telemetry?.latestFrame?.thermalState ?? .unknown
    }

    func statistics(for key: SMCKey) -> SensorStatistics? {
        telemetry?.series[key]?.statistics
    }

    func isSelectedForChart(_ key: SMCKey) -> Bool {
        selectedSensorKeys.contains(key)
    }

    func canSelectForChart(_ key: SMCKey) -> Bool {
        if selectedSensorKeys.contains(key) {
            return true
        }

        return selectedSensorKeys.count < Self.maximumChartSeriesCount
            && availableChartSensors.contains { $0.descriptor.key == key }
    }

    func toggleChartSelection(_ key: SMCKey) {
        let availableKeys = Set(availableChartSensors.map(\.descriptor.key))
        selectedSensorKeys = SensorSelectionPolicy.toggled(
            key,
            in: selectedSensorKeys,
            availableKeys: availableKeys,
            limit: Self.maximumChartSeriesCount
        )
        chartHistories = chartHistories.filter { selectedSensorKeys.contains($0.key) }
        Task { await loadChartHistories(expectedGeneration: samplingGeneration) }
    }

    func setMonitoringWindow(_ window: MonitoringWindow) {
        guard monitoringWindow != window else { return }
        monitoringWindow = window
        Task { await loadChartHistories(expectedGeneration: samplingGeneration) }
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        snapshot = nil
        telemetry = nil
        chartHistories = [:]
        let generation = UUID()
        samplingGeneration = generation

        Task {
            do {
                let activeSampler: TelemetrySampler
                if let sampler {
                    activeSampler = sampler
                } else {
                    let service = try SMCProbeService()
                    activeSampler = TelemetrySampler(source: service)
                    sampler = activeSampler
                }
                let catalog = try await activeSampler.start { [weak self] telemetry in
                    await self?.apply(telemetry, generation: generation)
                }
                guard samplingGeneration == generation else { return }
                snapshot = catalog
                reconcileChartSelection(with: catalog)
                await loadChartHistories(expectedGeneration: generation)
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }

    private var currentReadings: [SensorReading] {
        telemetry?.latestFrame?.readings ?? snapshot?.readings ?? []
    }

    private func apply(_ telemetry: TelemetrySummarySnapshot, generation: UUID) async {
        guard samplingGeneration == generation else { return }
        self.telemetry = telemetry
        await loadChartHistories(expectedGeneration: generation)
    }

    private func reconcileChartSelection(with catalog: SMCProbeSnapshot) {
        let availableReadings = catalog.readings.filter { reading in
            guard reading.validity == .valid else { return false }
            switch reading.descriptor.kind {
            case .fanActualSpeed, .temperatureCandidate:
                return true
            case .fanMaximumSpeed, .metadata, .raw:
                return false
            }
        }
        let availableKeys = Set(availableReadings.map(\.descriptor.key))
        selectedSensorKeys = selectedSensorKeys.intersection(availableKeys)

        if selectedSensorKeys.isEmpty {
            selectedSensorKeys = SensorSelectionPolicy.defaultKeys(
                from: availableReadings,
                limit: Self.maximumChartSeriesCount
            )
        }
    }

    private func loadChartHistories(expectedGeneration: UUID) async {
        guard let sampler else { return }
        let keys = selectedSensorKeys.sorted()
        guard !keys.isEmpty else {
            chartHistories = [:]
            return
        }

        let window = monitoringWindow
        let latestTimestamp = telemetry?.latestFrame?.timestamp ?? snapshot?.timestamp ?? Date()
        let cutoff = latestTimestamp.addingTimeInterval(-window.duration)
        let histories = await sampler.histories(for: keys, since: cutoff)

        guard samplingGeneration == expectedGeneration,
              monitoringWindow == window,
              selectedSensorKeys == Set(keys)
        else { return }
        chartHistories = histories
    }
}
