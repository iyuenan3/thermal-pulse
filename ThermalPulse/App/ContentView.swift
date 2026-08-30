import SwiftUI
import ThermalPulseCore

struct ContentView: View {
    @EnvironmentObject private var monitor: ThermalMonitorViewModel
    @State private var showsSensorDetails = false
    @State private var showsPerformanceCoreCandidates = false

    private var otherTemperatureReadings: [SensorReading] {
        let performanceKeys = Set(monitor.performanceCoreTemperatureReadings.map(\.descriptor.key))
        return monitor.temperatureCandidates.filter { !performanceKeys.contains($0.descriptor.key) }
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    temperatureHero
                    liveReadingsCard
                    thermalStateBanner
                    TurboControlView(style: .full)
                    charts
                    sensorDetails
                }
                .frame(maxWidth: 980)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            monitor.setMonitorWindowVisible(true)
            monitor.startIfNeeded()
        }
        .onDisappear {
            monitor.setMonitorWindowVisible(false)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("ThermalPulse")
                    .font(.title2.bold())
                Text("实时热状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            ReadOnlyBadge()

            Button {
                monitor.refresh()
            } label: {
                if monitor.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(monitor.isScanning)
            .help("重新枚举 AppleSMC 只读传感器")
        }
    }

    private var temperatureHero: some View {
        HStack(spacing: 18) {
            Image(systemName: "cpu")
                .font(.system(size: 27, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("P 核热点温度")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(temperatureAverageText)
                        .font(.system(size: 35, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if monitor.performanceCoreTemperatureSummary != nil {
                        Text("°C")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("当前最高")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Text(temperatureMaximumText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(temperatureCandidateCountText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.72), Color.cyan.opacity(0.58)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .blue.opacity(0.16), radius: 18, y: 8)
    }

    private var liveReadingsCard: some View {
        VStack(spacing: 0) {
            LiveReadingRow(
                symbol: "cpu",
                title: "P 核热点温度",
                value: temperatureAverageWithUnit,
                tint: .orange
            )
            insetDivider
            LiveReadingRow(
                symbol: "thermometer.high",
                title: "P 核族最高温度",
                value: temperatureMaximumText,
                tint: .orange
            )
            insetDivider
            LiveReadingRow(
                symbol: "thermometer.medium",
                title: "系统热状态",
                value: thermalStateText,
                tint: thermalStateTint
            )

            Divider()

            if monitor.visibleFanReadings.isEmpty {
                LiveReadingRow(
                    symbol: "fan",
                    title: "风扇",
                    value: "未知",
                    tint: .cyan
                )
            } else {
                ForEach(Array(monitor.visibleFanReadings.enumerated()), id: \.element.id) { index, reading in
                    LiveReadingRow(
                        symbol: "fan",
                        title: "风扇 \(index + 1)",
                        value: fanValue(reading),
                        tint: .cyan
                    )
                    if index < monitor.visibleFanReadings.count - 1 {
                        insetDivider
                    }
                }
            }

            Divider()

            LiveReadingRow(
                symbol: "waveform.path.ecg",
                title: "采样状态",
                value: samplingStatusText,
                tint: monitor.errorMessage == nil ? .green : .red
            )
        }
        .glassCard(padding: 0)
    }

    private var insetDivider: some View {
        Divider()
            .padding(.leading, 52)
    }

    private var thermalStateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: thermalStateSymbol)
                .foregroundStyle(thermalStateTint)
            Text(thermalStateDetail)
                .font(.headline)
            Spacer()
            if let date = monitor.lastUpdatedAt {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .glassCard(padding: 0)
    }

    @ViewBuilder
    private var charts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("趋势")
                        .font(.title2.bold())
                    Text("最多同时显示 \(ThermalMonitorViewModel.maximumChartSeriesCount) 项，曲线保留原始 key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(
                    "时间范围",
                    selection: Binding(
                        get: { monitor.monitoringWindow },
                        set: { monitor.setMonitoringWindow($0) }
                    )
                ) {
                    ForEach(MonitoringWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            if monitor.selectedSensorKeys.isEmpty {
                ContentUnavailableView(
                    "尚未选择曲线",
                    systemImage: "chart.xyaxis.line",
                    description: Text("展开下方传感器明细，选择最多 6 项读数。")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .glassCard()
            } else if monitor.chartSeries.isEmpty {
                ProgressView("正在积累历史样本")
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .glassCard()
            } else {
                SensorHistoryCharts(
                    series: monitor.chartSeries,
                    window: monitor.monitoringWindow
                )
            }
        }
    }

    private var sensorDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsSensorDetails.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("传感器与曲线")
                            .font(.headline)
                        Text("已选择 \(monitor.selectedSensorKeys.count)/\(ThermalMonitorViewModel.maximumChartSeriesCount) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsSensorDetails ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsSensorDetails {
                Divider()

                if monitor.visibleFanReadings.isEmpty && monitor.temperatureCandidates.isEmpty {
                    Text("等待首次只读枚举完成。")
                        .foregroundStyle(.secondary)
                } else {
                    if !monitor.visibleFanReadings.isEmpty {
                        ReadingGroup(
                            title: "风扇",
                            subtitle: "当前机器运行时已验证的实际 RPM",
                            readings: monitor.visibleFanReadings
                        )
                    }

                    if !monitor.performanceCoreTemperatureReadings.isEmpty {
                        candidateGroup(
                            title: "P 核温度候选族",
                            subtitle: "\(monitor.performanceCoreTemperatureReadings.count) 项，按 Tp 前缀归组",
                            readings: monitor.performanceCoreTemperatureReadings,
                            isExpanded: $showsPerformanceCoreCandidates
                        )
                    }

                    if !otherTemperatureReadings.isEmpty {
                        candidateGroup(
                            title: "其他原始温度候选",
                            subtitle: "\(otherTemperatureReadings.count) 项，尚未确认部件语义",
                            readings: otherTemperatureReadings,
                            isExpanded: Binding(
                                get: { monitor.showsRawTemperatureCandidates },
                                set: { newValue in
                                    if newValue != monitor.showsRawTemperatureCandidates {
                                        monitor.toggleRawTemperatureCandidates()
                                    }
                                }
                            )
                        )
                    }
                }
            }
        }
        .glassCard()
    }

    private func candidateGroup(
        title: String,
        subtitle: String,
        readings: [SensorReading],
        isExpanded: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(isExpanded.wrappedValue ? "收起" : "展开")
                        .font(.caption.weight(.medium))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                ForEach(readings) { reading in
                    SensorReadingRow(reading: reading)
                    if reading.id != readings.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var temperatureAverageText: String {
        guard let summary = monitor.performanceCoreTemperatureSummary else { return "未知" }
        return summary.reportedValue.formatted(.number.precision(.fractionLength(1)))
    }

    private var temperatureAverageWithUnit: String {
        monitor.performanceCoreTemperatureSummary == nil ? "未知" : "\(temperatureAverageText) °C"
    }

    private var temperatureMaximumText: String {
        guard let summary = monitor.performanceCoreTemperatureSummary else { return "未知" }
        return summary.maximum.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    private var temperatureCandidateCountText: String {
        guard let summary = monitor.performanceCoreTemperatureSummary else { return "等待有效候选" }
        return "\(summary.sensorCount) 个 Tp 候选"
    }

    private func fanValue(_ reading: SensorReading) -> String {
        guard reading.validity == .valid, let value = reading.value else { return "未知" }
        return "\(Int(value.rounded())) RPM"
    }

    private var samplingStatusText: String {
        guard let snapshot = monitor.snapshot else {
            return monitor.isScanning ? "正在枚举" : "等待首次读取"
        }
        return "\(snapshot.sampledKeyCount) 项 · 1 Hz"
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
}

private struct LiveReadingRow: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct ReadingGroup: View {
    let title: String
    let subtitle: String
    let readings: [SensorReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(readings) { reading in
                SensorReadingRow(reading: reading)
                if reading.id != readings.last?.id {
                    Divider()
                }
            }
        }
    }
}

private struct SensorReadingRow: View {
    @EnvironmentObject private var monitor: ThermalMonitorViewModel
    let reading: SensorReading

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reading.descriptor.unit == .rpm ? "fan" : "thermometer.medium")
                .foregroundStyle(reading.descriptor.unit == .rpm ? Color.cyan : Color.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.descriptor.displayName ?? reading.descriptor.key.rawValue)
                    .font(.body.weight(.medium))
                Text(
                    "\(reading.descriptor.key.rawValue) · \(reading.dataType.description) · \(reading.descriptor.evidence.rawValue)"
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                if let statistics = monitor.statistics(for: reading.descriptor.key) {
                    Text(
                        "\(statistics.sampleCount) 点 · 最小 \(statistics.minimum, specifier: "%.1f") · 最大 \(statistics.maximum, specifier: "%.1f") · 平均 \(statistics.average, specifier: "%.1f")"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                monitor.toggleChartSelection(reading.descriptor.key)
            } label: {
                Image(
                    systemName: monitor.isSelectedForChart(reading.descriptor.key)
                        ? "checkmark.circle.fill"
                        : "plus.circle"
                )
                .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                monitor.isSelectedForChart(reading.descriptor.key) ? Color.accentColor : Color.secondary
            )
            .disabled(!monitor.canSelectForChart(reading.descriptor.key))
            .help(
                monitor.isSelectedForChart(reading.descriptor.key)
                    ? "从趋势图移除"
                    : "加入趋势图"
            )

            if let value = reading.value, reading.validity == .valid {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value, format: .number.precision(.fractionLength(0...1)))
                        .font(.body.weight(.semibold).monospacedDigit())
                    Text(reading.descriptor.unit.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 86, alignment: .trailing)
            } else {
                Text("未知")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 86, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReadOnlyBadge: View {
    var body: some View {
        Label("只读监控", systemImage: "lock.shield.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.12), in: Capsule())
    }
}

private struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Color.blue.opacity(0.035), .clear, Color.cyan.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private extension View {
    func glassCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }
}
