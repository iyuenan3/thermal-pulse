import Foundation
import OSLog
import ThermalPulseCore

private enum MonitoringPerformanceEvent: String {
    case monitorWindowAppeared = "monitor_window_appeared"
    case monitorWindowDisappeared = "monitor_window_disappeared"
    case menuBarWindowRequested = "menu_bar_window_requested"
    case rawCandidatesExpanded = "raw_candidates_expanded"
    case rawCandidatesCollapsed = "raw_candidates_collapsed"
    case chartSelectionChanged = "chart_selection_changed"
    case monitoringWindowChanged = "monitoring_window_changed"
    case refreshStarted = "refresh_started"
    case refreshCompleted = "refresh_completed"
    case refreshFailed = "refresh_failed"
    case minuteSnapshot = "minute_snapshot"
}

private let monitoringPerformanceLogger = Logger(
    subsystem: "ThermalPulse",
    category: "MonitoringPerformance"
)

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
    let label: String
}

@MainActor
final class ThermalMonitorViewModel: ObservableObject {
    static let maximumChartSeriesCount = 3

    @Published private(set) var snapshot: SMCProbeSnapshot?
    @Published private(set) var telemetry: TelemetrySummarySnapshot?
    @Published private(set) var selectedSensorKeys: Set<SMCKey> = []
    @Published private(set) var monitoringWindow: MonitoringWindow = .fiveMinutes
    @Published private(set) var chartHistories: [SMCKey: [SensorSamplePoint]] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var showsRawTemperatureCandidates = false
    @Published private(set) var turboStatus = TurboStatus.inactive(issue: .helperUnavailable)
    @Published private(set) var turboHelperRegistrationState = TurboHelperRegistrationState.checking

    private var sampler: TelemetrySampler?
    private let turboXPCClient: TurboXPCClient
    private let turboCoordinator: TurboCoordinator
    private let turboHelperRegistrationCoordinator = TurboHelperRegistrationCoordinator(
        client: AdaptiveTurboHelperRegistrationClient()
    )
    private var samplingGeneration = UUID()
    private var turboStatusPollingTask: Task<Void, Never>?
    private var hasStarted = false
    private var chartSensorCatalog: [SensorReading] = []
    private var chartSensorKeys: Set<SMCKey> = []
    private var chartSensorLabels: [SMCKey: String] = [:]
    private var chartSensorComponents: [SMCKey: ComponentTemperature] = [:]
    private var isMonitorWindowVisible = false
    private var lastLoggedMinute = 0

    init() {
        let turboXPCClient = TurboXPCClient()
        self.turboXPCClient = turboXPCClient
        turboCoordinator = TurboCoordinator(
            client: turboXPCClient,
            initialStatus: .inactive(issue: .helperUnavailable)
        )
    }

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

    var menuBarPerformanceCoreText: String {
        if let summary = performanceCoreTemperatureSummary {
            return "P \(Int(summary.reportedValue.rounded()))°"
        }
        return "P --°"
    }

    var menuBarEfficiencyCoreText: String {
        guard let summary = componentTemperatureSummary(for: .efficiencyCore) else {
            return "E --°"
        }
        return "E \(Int(summary.reportedValue.rounded()))°"
    }

    var menuBarFanTexts: [String] {
        let readings = visibleFanReadings
        guard !readings.isEmpty else { return ["F --"] }

        return readings.enumerated().map { index, reading in
            guard reading.validity == .valid, let value = reading.value else {
                return "F\(index + 1) --"
            }
            return "F\(index + 1) \(Int(value.rounded()))"
        }
    }

    var performanceCoreTemperatureSummary: TemperatureFamilySummary? {
        PerformanceCoreTemperaturePolicy.summary(from: currentReadings)
    }

    func componentTemperatureSummary(
        for component: ComponentTemperature
    ) -> ComponentTemperatureSummary? {
        ComponentTemperaturePolicy.summary(for: component, from: currentReadings)
    }

    var visibleFanReadings: [SensorReading] {
        currentReadings
            .filter { $0.descriptor.kind == .fanActualSpeed }
            .sorted { $0.descriptor.key < $1.descriptor.key }
    }

    var temperatureCandidates: [SensorReading] {
        currentReadings
            .filter { $0.descriptor.kind == .temperatureCandidate }
            .sorted { $0.descriptor.key < $1.descriptor.key }
    }

    var performanceCoreTemperatureReadings: [SensorReading] {
        PerformanceCoreTemperaturePolicy.matchingReadings(from: currentReadings)
    }

    var lastUpdatedAt: Date? {
        telemetry?.latestFrame?.timestamp ?? snapshot?.timestamp
    }

    var availableChartSensors: [SensorReading] {
        chartSensorCatalog
    }

    var chartSeries: [SensorChartSeries] {
        availableChartSensors.compactMap { reading in
            let key = reading.descriptor.key
            guard selectedSensorKeys.contains(key),
                  let points = chartHistories[key],
                  !points.isEmpty
            else { return nil }

            let displayPoints = chartSensorComponents[key].map {
                ComponentTemperaturePolicy.displayHistoryPoints(for: $0, from: points)
            } ?? points
            guard !displayPoints.isEmpty else { return nil }

            return SensorChartSeries(
                descriptor: reading.descriptor,
                points: displayPoints,
                label: chartSensorLabels[key] ?? reading.descriptor.key.rawValue
            )
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
            && chartSensorKeys.contains(key)
    }

    func toggleChartSelection(_ key: SMCKey) {
        selectedSensorKeys = SensorSelectionPolicy.toggled(
            key,
            in: selectedSensorKeys,
            availableKeys: chartSensorKeys,
            limit: Self.maximumChartSeriesCount
        )
        chartHistories = chartHistories.filter { selectedSensorKeys.contains($0.key) }
        recordPerformanceEvent(.chartSelectionChanged)
        Task { await loadChartHistories(expectedGeneration: samplingGeneration) }
    }

    func setMonitoringWindow(_ window: MonitoringWindow) {
        guard monitoringWindow != window else { return }
        monitoringWindow = window
        recordPerformanceEvent(.monitoringWindowChanged)
        Task { await loadChartHistories(expectedGeneration: samplingGeneration) }
    }

    func setMonitorWindowVisible(_ isVisible: Bool) {
        guard isMonitorWindowVisible != isVisible else { return }
        isMonitorWindowVisible = isVisible
        recordPerformanceEvent(isVisible ? .monitorWindowAppeared : .monitorWindowDisappeared)
    }

    func recordMenuBarWindowRequest() {
        recordPerformanceEvent(.menuBarWindowRequested)
    }

    func toggleRawTemperatureCandidates() {
        showsRawTemperatureCandidates.toggle()
        recordPerformanceEvent(
            showsRawTemperatureCandidates ? .rawCandidatesExpanded : .rawCandidatesCollapsed
        )
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshTurboHelperRegistration()
        refresh()
    }

    func refreshTurboHelperRegistration() {
        applyTurboHelperRegistrationState(turboHelperRegistrationCoordinator.refresh())
    }

    func registerTurboHelper() {
        guard turboHelperRegistrationState.canRegister else { return }
        turboHelperRegistrationState = .registering
        applyTurboHelperRegistrationState(turboHelperRegistrationCoordinator.register())
    }

    func openTurboHelperSystemSettings() {
        turboHelperRegistrationCoordinator.openSystemSettings()
    }

    func upgradeTurboHelper() {
        guard turboHelperRegistrationState == .enabled,
              turboStatus.phase == .inactive
        else { return }

        turboHelperRegistrationState = .registering
        turboStatus = .inactive(issue: .helperUnavailable)
        turboXPCClient.invalidate()
        Task {
            applyTurboHelperRegistrationState(
                await turboHelperRegistrationCoordinator.replaceRegistration()
            )
        }
    }

    func synchronizeTurboStatus() {
        guard turboHelperRegistrationState == .enabled else { return }
        Task {
            turboStatus = await turboCoordinator.synchronize()
            updateTurboStatusPolling()
        }
    }

    func startTurbo() {
        guard turboStatus.canStart else { return }
        Task {
            turboStatus = TurboStatus(phase: .activating)
            turboStatus = await turboCoordinator.startTurbo()
            updateTurboStatusPolling()
        }
    }

    func stopTurbo() {
        guard turboStatus.canStop else { return }
        Task {
            turboStatusPollingTask?.cancel()
            turboStatusPollingTask = nil
            turboStatus = TurboStatus(phase: .restoring)
            turboStatus = await turboCoordinator.stopTurbo()
        }
    }

    private func updateTurboStatusPolling() {
        turboStatusPollingTask?.cancel()
        turboStatusPollingTask = nil
        guard turboStatus.phase == .active else { return }

        turboStatusPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                let synchronized = await self.turboCoordinator.synchronize()
                guard !Task.isCancelled else { return }
                self.turboStatus = synchronized
                guard synchronized.phase == .active else {
                    self.turboStatusPollingTask = nil
                    return
                }
            }
        }
    }

    private func applyTurboHelperRegistrationState(_ state: TurboHelperRegistrationState) {
        turboHelperRegistrationState = state
        switch state {
        case .enabled:
            synchronizeTurboStatus()
        case .requiresApproval:
            turboStatus = .inactive(issue: .helperNotApproved)
        case .checking, .notRegistered, .registering, .notFound,
             .manualInstallationRequired, .installerOpened, .failed:
            turboStatus = .inactive(issue: .helperUnavailable)
        }
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        snapshot = nil
        telemetry = nil
        chartHistories = [:]
        chartSensorCatalog = []
        chartSensorKeys = []
        chartSensorLabels = [:]
        chartSensorComponents = [:]
        lastLoggedMinute = 0
        let generation = UUID()
        samplingGeneration = generation
        recordPerformanceEvent(.refreshStarted)

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
                reconcileChartSelection(with: catalog)
                snapshot = catalog
                await loadChartHistories(expectedGeneration: generation)
                recordPerformanceEvent(.refreshCompleted)
            } catch {
                errorMessage = error.localizedDescription
                recordPerformanceEvent(.refreshFailed)
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
        recordMinuteSnapshotIfNeeded()
        await loadChartHistories(expectedGeneration: generation)
    }

    private func recordMinuteSnapshotIfNeeded() {
        let sampleCount = longestSeriesSampleCount
        let completedMinute = sampleCount / 60
        guard completedMinute > lastLoggedMinute else { return }
        lastLoggedMinute = completedMinute
        recordPerformanceEvent(.minuteSnapshot)
    }

    private func recordPerformanceEvent(_ event: MonitoringPerformanceEvent) {
        monitoringPerformanceLogger.notice(
            "event=\(event.rawValue, privacy: .public) sampleCount=\(self.longestSeriesSampleCount) selectedSeries=\(self.selectedSensorKeys.count) windowSeconds=\(self.monitoringWindow.rawValue) rawCandidatesExpanded=\(self.showsRawTemperatureCandidates) monitorWindowVisible=\(self.isMonitorWindowVisible) thermalState=\(self.thermalState.rawValue, privacy: .public)"
        )
    }

    private var longestSeriesSampleCount: Int {
        telemetry?.series.values.map(\.statistics.sampleCount).max() ?? 0
    }

    private func reconcileChartSelection(with catalog: SMCProbeSnapshot) {
        let summaries = ComponentTemperaturePolicy.summaries(from: catalog.readings)
        let availableReadings = summaries.compactMap { summary in
            catalog.readings.first { $0.descriptor.key == summary.representativeKey }
        }
        let availableKeys = Set(availableReadings.map(\.descriptor.key))
        chartSensorCatalog = availableReadings
        chartSensorKeys = availableKeys
        chartSensorLabels = Dictionary(uniqueKeysWithValues: summaries.map { summary in
            (summary.representativeKey, Self.chartLabel(for: summary.component))
        })
        chartSensorComponents = Dictionary(uniqueKeysWithValues: summaries.map { summary in
            (summary.representativeKey, summary.component)
        })
        selectedSensorKeys = availableKeys
    }

    private static func chartLabel(for component: ComponentTemperature) -> String {
        switch component {
        case .performanceCore: "P 核"
        case .efficiencyCore: "E 核"
        case .battery: "电池"
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
