import SwiftUI
import ThermalPulseCore

struct ContentView: View {
    @EnvironmentObject private var monitor: ThermalMonitorViewModel
    @State private var showsRawTemperatureCandidates = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            summary
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    charts
                    readings
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .onAppear {
            monitor.startIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ThermalPulse")
                    .font(.largeTitle.bold())
                Text("普通权限每秒只读采样，不会修改任何 SMC 值")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                monitor.refresh()
            } label: {
                if monitor.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("重新枚举", systemImage: "arrow.clockwise")
                }
            }
            .disabled(monitor.isScanning)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let snapshot = monitor.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                    GridRow {
                        metric("SMC keys", value: "\(snapshot.enumeratedKeyCount)")
                        metric("风扇", value: snapshot.fanCount.map(String.init) ?? "未知")
                        metric("候选温度", value: "\(monitor.temperatureCandidates.count)")
                        metric("系统 thermal state", value: thermalStateText)
                    }
                }
                Text(monitor.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(monitor.statusText)
                .foregroundStyle(monitor.errorMessage == nil ? Color.secondary : Color.red)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
        }
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("历史曲线")
                        .font(.title2.bold())
                    Text(
                        "已选择 \(monitor.selectedSensorKeys.count)/\(ThermalMonitorViewModel.maximumChartSeriesCount) 项，默认包含当前最高的原始温度候选"
                    )
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
                .pickerStyle(.segmented)
                .frame(width: 300)
            }

            if monitor.selectedSensorKeys.isEmpty {
                Text("从下方读数列表选择最多 6 个传感器。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else if monitor.chartSeries.isEmpty {
                ProgressView("正在积累所选传感器的历史样本")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                SensorHistoryCharts(
                    series: monitor.chartSeries,
                    window: monitor.monitoringWindow
                )
            }
        }
    }

    private var readings: some View {
        let fanReadings = monitor.visibleFanReadings
        let temperatureReadings = monitor.temperatureCandidates

        return VStack(alignment: .leading, spacing: 12) {
            Text("当前读数")
                .font(.title2.bold())

            if fanReadings.isEmpty && temperatureReadings.isEmpty {
                Text("还没有取得可展示的风扇或温度候选读数。未知项不会伪装成 0。")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !fanReadings.isEmpty {
                        readingSection(
                            title: "已验证风扇读数",
                            readings: fanReadings
                        )
                    }
                    if !temperatureReadings.isEmpty {
                        rawTemperatureSection(readings: temperatureReadings)
                    }
                }
            }
        }
    }

    private func rawTemperatureSection(readings: [SensorReading]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("高级原始温度候选")
                        .font(.headline)
                    Text("\(readings.count) 项，尚未确认部件语义")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(showsRawTemperatureCandidates ? "收起" : "展开") {
                    showsRawTemperatureCandidates.toggle()
                }
            }

            if showsRawTemperatureCandidates {
                ForEach(readings) { reading in
                    readingRow(reading)
                    if reading.id != readings.last?.id {
                        Divider()
                    }
                }
            } else {
                Text("默认收起原始候选，展开后可查看 key、数据类型、证据等级和历史统计。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func readingSection(title: String, readings: [SensorReading]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(readings) { reading in
                readingRow(reading)
                if reading.id != readings.last?.id {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func readingRow(_ reading: SensorReading) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(reading.descriptor.displayName ?? reading.descriptor.key.rawValue)
                Text("\(reading.descriptor.key.rawValue) · \(reading.dataType.description) · \(reading.descriptor.evidence.rawValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let statistics = monitor.statistics(for: reading.descriptor.key) {
                    Text(
                        "历史 \(statistics.sampleCount) 点 · 最小 \(statistics.minimum, specifier: "%.1f") · 最大 \(statistics.maximum, specifier: "%.1f") · 平均 \(statistics.average, specifier: "%.1f")"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                monitor.toggleChartSelection(reading.descriptor.key)
            } label: {
                Image(
                    systemName: monitor.isSelectedForChart(reading.descriptor.key)
                        ? "chart.xyaxis.line"
                        : "plus.circle"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                monitor.isSelectedForChart(reading.descriptor.key) ? Color.accentColor : Color.secondary
            )
            .disabled(!monitor.canSelectForChart(reading.descriptor.key))
            .help(
                monitor.isSelectedForChart(reading.descriptor.key)
                    ? "从历史曲线移除"
                    : "加入历史曲线"
            )
            if let value = reading.value, reading.validity == .valid {
                Text(value, format: .number.precision(.fractionLength(0...1)))
                    .font(.title3.monospacedDigit())
                Text(reading.descriptor.unit.rawValue)
                    .foregroundStyle(.secondary)
            } else {
                Text("未知")
                    .foregroundStyle(.secondary)
            }
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
}
