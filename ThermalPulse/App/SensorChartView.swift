import Charts
import SwiftUI
import ThermalPulseCore

struct SensorHistoryCharts: View {
    let series: [SensorChartSeries]
    let window: MonitoringWindow

    private var fanSeries: [SensorChartSeries] {
        series.filter { $0.descriptor.unit == .rpm }
    }

    private var temperatureSeries: [SensorChartSeries] {
        series.filter { $0.descriptor.unit == .celsius }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !fanSeries.isEmpty {
                SensorHistoryChart(
                    title: "风扇转速",
                    subtitle: "运行时已验证的实际 RPM",
                    unit: .rpm,
                    series: fanSeries,
                    window: window
                )
            }

            if !temperatureSeries.isEmpty {
                SensorHistoryChart(
                    title: "温度趋势",
                    subtitle: "P 核、E 核与电池的只读温度趋势",
                    unit: .celsius,
                    series: temperatureSeries,
                    window: window
                )
            }
        }
    }
}

struct CompactTemperatureChart: View {
    let series: [SensorChartSeries]

    private let window: TimeInterval = 300

    private var temperatureSeries: [SensorChartSeries] {
        series.filter { $0.descriptor.unit == .celsius }
    }

    private var windowEnd: Date {
        temperatureSeries.flatMap(\.points).map(\.timestamp).max() ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("温度趋势")
                        .font(.headline)
                    Text("最近 5 分钟")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("°C")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if temperatureSeries.isEmpty {
                ContentUnavailableView(
                    "等待温度数据",
                    systemImage: "chart.xyaxis.line",
                    description: Text("首次采样后显示曲线")
                )
                .frame(height: 105)
            } else {
                GeometryReader { geometry in
                    let pointBudget = max(50, min(240, Int(geometry.size.width / 2)))
                    Chart(renderedPoints(pointBudget: pointBudget)) { point in
                        if point.isIsolated {
                            PointMark(
                                x: .value("时间", point.timestamp),
                                y: .value("温度", point.value)
                            )
                            .foregroundStyle(by: .value("部件", point.label))
                        } else {
                            LineMark(
                                x: .value("时间", point.timestamp),
                                y: .value("温度", point.value),
                                series: .value("连续段", point.segmentID)
                            )
                            .foregroundStyle(by: .value("部件", point.label))
                            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        }
                    }
                    .chartXScale(domain: windowEnd.addingTimeInterval(-window)...windowEnd)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour().minute())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                    }
                    .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
                    .accessibilityLabel("P 核、E 核与电池温度的最近五分钟曲线")
                }
                .frame(height: 130)
            }
        }
        .padding(12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private func renderedPoints(pointBudget: Int) -> [RenderedChartPoint] {
        temperatureSeries.flatMap { item in
            TelemetryDisplayReducer.reduceSegments(
                item.points,
                maximumPointCount: pointBudget,
                maximumGap: 1.75
            ).enumerated().flatMap { index, segment in
                segment.map { point in
                    RenderedChartPoint(
                        sensorKey: item.id,
                        label: item.label,
                        segmentIndex: index,
                        timestamp: point.timestamp,
                        value: point.value,
                        isIsolated: segment.count == 1
                    )
                }
            }
        }
    }
}

private struct SensorHistoryChart: View {
    let title: String
    let subtitle: String
    let unit: SensorUnit
    let series: [SensorChartSeries]
    let window: MonitoringWindow

    private var windowEnd: Date {
        series.flatMap(\.points).map(\.timestamp).max() ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let pointBudget = max(60, min(600, Int(geometry.size.width / 2)))
                let renderedPoints = makeRenderedPoints(pointBudget: pointBudget)

                Chart(renderedPoints) { point in
                    if point.isIsolated {
                        PointMark(
                            x: .value("时间", point.timestamp),
                            y: .value(unit.rawValue, point.value)
                        )
                        .foregroundStyle(by: .value("传感器", point.label))
                    } else {
                        LineMark(
                            x: .value("时间", point.timestamp),
                            y: .value(unit.rawValue, point.value),
                            series: .value("连续段", point.segmentID)
                        )
                        .foregroundStyle(by: .value("传感器", point.label))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartXScale(
                    domain: windowEnd.addingTimeInterval(-window.duration)...windowEnd
                )
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYAxisLabel(unit.rawValue)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .accessibilityLabel("\(title)，\(window.title)历史曲线")
            }
            .frame(height: 230)
        }
        .padding(16)
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

    private func makeRenderedPoints(pointBudget: Int) -> [RenderedChartPoint] {
        series.flatMap { item in
            let segments = TelemetryDisplayReducer.reduceSegments(
                item.points,
                maximumPointCount: pointBudget,
                maximumGap: 1.75
            )

            return segments.enumerated().flatMap { index, segment in
                segment.map { point in
                    RenderedChartPoint(
                        sensorKey: item.id,
                        label: item.label,
                        segmentIndex: index,
                        timestamp: point.timestamp,
                        value: point.value,
                        isIsolated: segment.count == 1
                    )
                }
            }
        }
    }
}

private struct RenderedChartPoint: Identifiable {
    let sensorKey: SMCKey
    let label: String
    let segmentIndex: Int
    let timestamp: Date
    let value: Double
    let isIsolated: Bool

    var id: String {
        "\(segmentID)-\(timestamp.timeIntervalSinceReferenceDate)"
    }

    var segmentID: String {
        "\(sensorKey.rawValue)-\(segmentIndex)"
    }
}
