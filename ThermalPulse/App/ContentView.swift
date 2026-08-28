import SwiftUI
import ThermalPulseCore

struct ContentView: View {
    @EnvironmentObject private var monitor: ThermalMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            summary
            Divider()
            readings
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

    private var readings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前读数")
                .font(.title2.bold())

            if monitor.visibleFanReadings.isEmpty && monitor.temperatureCandidates.isEmpty {
                Text("还没有取得可展示的风扇或温度候选读数。未知项不会伪装成 0。")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !monitor.visibleFanReadings.isEmpty {
                            readingSection(
                                title: "已验证风扇读数",
                                readings: monitor.visibleFanReadings
                            )
                        }
                        if !monitor.temperatureCandidates.isEmpty {
                            readingSection(
                                title: "高级原始温度候选，尚未确认部件语义",
                                readings: monitor.temperatureCandidates
                            )
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
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
