import SwiftUI
import ThermalPulseCore

@main
struct ThermalPulseApp: App {
    @StateObject private var monitor = ThermalMonitorViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("ThermalPulse", id: "monitor") {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 720, minHeight: 600)
        }

        MenuBarExtra {
            MenuBarPanel(openMonitorWindow: {
                monitor.recordMenuBarWindowRequest()
                openWindow(id: "monitor")
                NSApplication.shared.activate()
            })
            .environmentObject(monitor)
        } label: {
            Text(monitor.menuBarSummary)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarPanel: View {
    @EnvironmentObject private var monitor: ThermalMonitorViewModel
    let openMonitorWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader
            temperatureBand
            readingsCard
            thermalStateBanner
            TurboControlView(style: .compact)
            openWindowButton
        }
        .padding(14)
        .frame(width: 360)
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("ThermalPulse")
                    .font(.headline)
                Text(controlStateSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                monitor.refresh()
            } label: {
                if monitor.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(monitor.isScanning)
            .help("重新枚举")

            Menu {
                Button("退出 ThermalPulse") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var controlStateSummary: String {
        switch monitor.turboStatus.phase {
        case .inactive:
            if monitor.turboStatus.issue == nil {
                return "只读监控 · 苹果自动风扇控制"
            }
            if monitor.turboStatus.issue == .externalControllerDetected {
                return "只读监控 · 检测到外部风扇控制"
            }
            return "只读监控 · ThermalPulse 未接管风扇"
        case .activating:
            return "正在验证 Turbo 安全状态"
        case .active:
            return "Turbo 运行中 · 最长 10 分钟"
        case .restoring:
            return "正在恢复苹果自动风扇控制"
        case .failedSafeAuto:
            return "风扇控制状态待确认"
        }
    }

    private var temperatureBand: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("P 核平均温度")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(performanceCoreTemperatureText)
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("最高")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                Text(performanceCoreMaximumText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.72), Color.cyan.opacity(0.55)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .blue.opacity(0.14), radius: 12, y: 5)
    }

    private var readingsCard: some View {
        VStack(spacing: 0) {
            panelRow(
                title: "系统热状态",
                value: thermalStateText,
                symbol: "thermometer.medium",
                tint: thermalStateTint
            )
            insetDivider

            if monitor.visibleFanReadings.isEmpty {
                panelRow(title: "风扇", value: "未知", symbol: "fan", tint: .cyan)
            } else {
                ForEach(Array(monitor.visibleFanReadings.enumerated()), id: \.element.id) { index, reading in
                    panelRow(
                        title: "风扇 \(index + 1)",
                        value: fanValue(reading),
                        symbol: "fan",
                        tint: .cyan
                    )
                    if index < monitor.visibleFanReadings.count - 1 {
                        insetDivider
                    }
                }
            }

            Divider()

            panelRow(
                title: "采样",
                value: samplingText,
                symbol: "waveform.path.ecg",
                tint: monitor.errorMessage == nil ? .green : .red
            )
            insetDivider
            panelRow(
                title: "历史",
                value: historyText,
                symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tint: .secondary
            )
        }
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var insetDivider: some View {
        Divider()
            .padding(.leading, 46)
    }

    private var thermalStateBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: thermalStateSymbol)
                .foregroundStyle(thermalStateTint)
            Text(thermalStateDetail)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var openWindowButton: some View {
        Button(action: openMonitorWindow) {
            HStack {
                Image(systemName: "macwindow")
                Spacer()
                Text("打开监控窗口")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.accentColor.opacity(0.18),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
        .keyboardShortcut("o")
    }

    private var performanceCoreTemperatureText: String {
        guard let summary = monitor.performanceCoreTemperatureSummary else { return "未知" }
        return summary.average.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    private var performanceCoreMaximumText: String {
        guard let summary = monitor.performanceCoreTemperatureSummary else { return "未知" }
        return summary.maximum.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    private func fanValue(_ reading: SensorReading) -> String {
        guard reading.validity == .valid, let value = reading.value else { return "未知" }
        return "\(Int(value.rounded())) RPM"
    }

    private var samplingText: String {
        guard let snapshot = monitor.snapshot else {
            return monitor.isScanning ? "正在枚举" : "等待读取"
        }
        return "\(snapshot.sampledKeyCount) 项 · 1 Hz"
    }

    private var historyText: String {
        "\(monitor.monitoringWindow.title) · \(monitor.selectedSensorKeys.count) 条曲线"
    }

    private var thermalStateText: String {
        switch monitor.thermalState {
        case .nominal: "正常"
        case .fair: "注意"
        case .serious: "严重"
        case .critical: "危急"
        case .unknown: "未知"
        }
    }

    private var thermalStateDetail: String {
        switch monitor.thermalState {
        case .nominal: "当前没有系统热压力"
        case .fair: "系统已开始采取温控措施"
        case .serious: "系统热压力较高"
        case .critical: "系统热压力已达到危急状态"
        case .unknown: "正在等待系统热状态"
        }
    }

    private var thermalStateSymbol: String {
        switch monitor.thermalState {
        case .nominal: "checkmark.circle.fill"
        case .fair: "exclamationmark.circle.fill"
        case .serious: "exclamationmark.triangle.fill"
        case .critical: "flame.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var thermalStateTint: Color {
        switch monitor.thermalState {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }

    private func panelRow(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
