import Foundation
import ThermalPulseCore

@MainActor
final class ThermalMonitorViewModel: ObservableObject {
    @Published private(set) var snapshot: SMCProbeSnapshot?
    @Published private(set) var telemetry: TelemetrySummarySnapshot?
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

    var thermalState: SystemThermalState {
        telemetry?.latestFrame?.thermalState ?? .unknown
    }

    func statistics(for key: SMCKey) -> SensorStatistics? {
        telemetry?.series[key]?.statistics
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
                snapshot = try await activeSampler.start { [weak self] telemetry in
                    await self?.apply(telemetry, generation: generation)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }

    private var currentReadings: [SensorReading] {
        telemetry?.latestFrame?.readings ?? snapshot?.readings ?? []
    }

    private func apply(_ telemetry: TelemetrySummarySnapshot, generation: UUID) {
        guard samplingGeneration == generation else { return }
        self.telemetry = telemetry
    }
}
