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
                    title: "原始温度候选",
                    subtitle: "仅显示 SMC key，尚未确认部件语义",
                    unit: .celsius,
                    series: temperatureSeries,
                    window: window
                )
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
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
