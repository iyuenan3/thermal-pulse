import AppKit
import SwiftUI
import ThermalPulseCore

@main
struct ThermalPulseApp: App {
    @StateObject private var monitor = ThermalMonitorViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(monitor)
        } label: {
            MenuBarSummaryLabel(
                performanceCoreText: monitor.menuBarPerformanceCoreText,
                efficiencyCoreText: monitor.menuBarEfficiencyCoreText,
                fanTexts: monitor.menuBarFanTexts
            )
            .task {
                monitor.startIfNeeded()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarSummaryLabel: View {
    let performanceCoreText: String
    let efficiencyCoreText: String
    let fanTexts: [String]

    var body: some View {
        let cells = summaryCells
        Image(
            nsImage: MenuBarSummaryImageRenderer.makeImage(
                topLeft: cells.topLeft,
                bottomLeft: cells.bottomLeft,
                topRight: cells.topRight,
                bottomRight: cells.bottomRight
            )
        )
        .renderingMode(.template)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var summaryCells: (
        topLeft: String,
        bottomLeft: String,
        topRight: String,
        bottomRight: String
    ) {
        let compactFans = fanTexts.map(compactFanValue)
        let topFan = compactFans.first ?? "--"
        let bottomFan = compactFans.dropFirst().first ?? "--"

        let performance = performanceCoreText.replacingOccurrences(of: " ", with: "")
        let efficiency = efficiencyCoreText.replacingOccurrences(of: " ", with: "")
        return (performance, efficiency, topFan, bottomFan)
    }

    private func compactFanValue(_ text: String) -> String {
        text.split(separator: " ", maxSplits: 1).last.map(String.init) ?? "--"
    }

    private var accessibilitySummary: String {
        ([performanceCoreText, efficiencyCoreText] + fanTexts).joined(separator: "，")
    }
}

@MainActor
private enum MenuBarSummaryImageRenderer {
    private static let imageHeight: CGFloat = 23
    private static let rowHeight: CGFloat = 11.5
    private static let columnGap: CGFloat = 4
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: 10,
        weight: .semibold
    )

    static func makeImage(
        topLeft: String,
        bottomLeft: String,
        topRight: String,
        bottomRight: String
    ) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let leftWidth = ceil(
            max(
                textWidth(topLeft, attributes: attributes),
                textWidth(bottomLeft, attributes: attributes),
                textWidth("P100°", attributes: attributes)
            )
        )
        let rightWidth = ceil(
            max(
                textWidth(topRight, attributes: attributes),
                textWidth(bottomRight, attributes: attributes),
                textWidth("0000", attributes: attributes)
            )
        )
        let imageSize = NSSize(
            width: leftWidth + columnGap + rightWidth,
            height: imageHeight
        )
        let image = NSImage(size: imageSize, flipped: true) { _ in
            (topLeft as NSString).draw(
                at: NSPoint(x: 0, y: 0),
                withAttributes: attributes
            )
            (bottomLeft as NSString).draw(
                at: NSPoint(x: 0, y: rowHeight),
                withAttributes: attributes
            )
            (topRight as NSString).draw(
                at: NSPoint(x: leftWidth + columnGap, y: 0),
                withAttributes: attributes
            )
            (bottomRight as NSString).draw(
                at: NSPoint(x: leftWidth + columnGap, y: rowHeight),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func textWidth(
        _ text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }
}

private struct MenuBarPanel: View {
    @EnvironmentObject private var monitor: ThermalMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            panelHeader
            temperatureCard
            CompactTemperatureChart(series: monitor.chartSeries)
            fanAndSystemCard
            TurboControlView(style: .compact)
            panelFooter
        }
        .padding(12)
        .frame(width: 420)
        .onAppear {
            monitor.startIfNeeded()
        }
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
            .frame(width: 34, height: 34)

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
            .help("重新读取")

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

    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            temperatureRow(
                component: .performanceCore,
                title: "P 核温度",
                symbol: "cpu",
                tint: .orange
            )
            insetDivider
            temperatureRow(
                component: .efficiencyCore,
                title: "E 核温度",
                symbol: "cpu",
                tint: .yellow
            )
            insetDivider
            temperatureRow(
                component: .battery,
                title: "电池",
                symbol: "battery.100percent",
                tint: .green
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

    private var fanAndSystemCard: some View {
        VStack(spacing: 0) {
            panelRow(
                title: "系统热状态",
                value: thermalStateText,
                detail: thermalStateDetail,
                symbol: thermalStateSymbol,
                tint: thermalStateTint
            )

            if monitor.visibleFanReadings.isEmpty {
                insetDivider
                panelRow(
                    title: "风扇",
                    value: "不可用",
                    detail: "尚未读到实际 RPM",
                    symbol: "fan",
                    tint: .cyan
                )
            } else {
                ForEach(Array(monitor.visibleFanReadings.enumerated()), id: \.element.id) { index, reading in
                    insetDivider
                    panelRow(
                        title: "风扇 \(index + 1)",
                        value: fanValue(reading),
                        detail: monitor.turboStatus.fanControlUserMessage,
                        symbol: "fan",
                        tint: .cyan
                    )
                }
            }
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

    private var panelFooter: some View {
        HStack {
            if let errorMessage = monitor.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            } else if let updatedAt = monitor.lastUpdatedAt {
                Text("更新于 \(updatedAt.formatted(date: .omitted, time: .standard))")
                    .foregroundStyle(.secondary)
            } else {
                Text("正在读取温度")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("1 秒更新")
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .padding(.horizontal, 2)
    }

    private var insetDivider: some View {
        Divider()
            .padding(.leading, 48)
    }

    private func temperatureRow(
        component: ComponentTemperature,
        title: String,
        symbol: String,
        tint: Color
    ) -> some View {
        let summary = monitor.componentTemperatureSummary(for: component)
        return panelRow(
            title: title,
            value: temperatureText(summary),
            detail: temperatureDetail(component: component, summary: summary),
            symbol: symbol,
            tint: tint
        )
    }

    private func panelRow(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(value == "不可用" ? .secondary : .primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func temperatureText(_ summary: ComponentTemperatureSummary?) -> String {
        guard let summary else { return "不可用" }
        return summary.reportedValue.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    private func temperatureDetail(
        component: ComponentTemperature,
        summary: ComponentTemperatureSummary?
    ) -> String {
        guard let summary else { return "本机未提供可验证温度 key" }

        switch component {
        case .performanceCore:
            return "\(summary.sensorCount) 个 P 核候选中的当前热点"
        case .efficiencyCore:
            return "\(summary.sensorCount) 个 E 核候选中的当前热点"
        case .battery:
            return "\(summary.sensorCount) 个传感器平均"
        }
    }

    private func fanValue(_ reading: SensorReading) -> String {
        guard reading.validity == .valid, let value = reading.value else { return "不可用" }
        return "\(Int(value.rounded())) RPM"
    }

    private var controlStateSummary: String {
        switch monitor.turboStatus.phase {
        case .inactive:
            if monitor.turboStatus.issue == nil {
                return "观察温度，风扇由苹果自动控制"
            }
            if monitor.turboStatus.issue == .externalControllerDetected {
                return "检测到其他风扇控制工具"
            }
            return "温度监控可用，Turbo 暂不可用"
        case .activating:
            return "正在验证 Turbo"
        case .active:
            return "Turbo 运行中"
        case .restoring:
            return "正在恢复苹果自动控制"
        case .failedSafeAuto:
            return "风扇控制状态待确认"
        }
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
        case .nominal: "系统当前没有报告热压力"
        case .fair: "系统已开始采取温控措施"
        case .serious: "系统热压力较高"
        case .critical: "系统热压力已达到危急状态"
        case .unknown: "等待系统状态"
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
}
