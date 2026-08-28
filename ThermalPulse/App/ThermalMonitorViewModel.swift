import Foundation
import ThermalPulseCore

@MainActor
final class ThermalMonitorViewModel: ObservableObject {
    @Published private(set) var snapshot: SMCProbeSnapshot?
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?

    private var probeService: SMCProbeService?
    private var hasStarted = false

    var statusText: String {
        if isScanning { return "正在以普通权限读取 AppleSMC" }
        if let errorMessage { return errorMessage }
        guard let snapshot else { return "等待首次只读探测" }
        return "读取了 \(snapshot.sampledKeyCount) 个候选项，\(snapshot.failedReadCount) 个 key 读取失败"
    }

    var menuBarSummary: String {
        let actualFans = visibleFanReadings
        guard !actualFans.isEmpty else { return "ThermalPulse" }
        return actualFans.compactMap { reading in
            reading.value.map { "\(reading.descriptor.key.rawValue) \(Int($0.rounded())) RPM" }
        }.joined(separator: " · ")
    }

    var visibleFanReadings: [SensorReading] {
        snapshot?.readings.filter {
            $0.descriptor.kind == .fanActualSpeed && $0.validity == .valid
        } ?? []
    }

    var temperatureCandidates: [SensorReading] {
        snapshot?.readings.filter {
            $0.descriptor.kind == .temperatureCandidate
        } ?? []
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

        Task {
            do {
                let service: SMCProbeService
                if let probeService {
                    service = probeService
                } else {
                    service = try SMCProbeService()
                    probeService = service
                }
                snapshot = try await service.scan()
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }
}

