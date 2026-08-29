import SwiftUI

@main
struct ThermalPulseApp: App {
    @StateObject private var monitor = ThermalMonitorViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("ThermalPulse", id: "monitor") {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 760, minHeight: 520)
        }

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                Text(monitor.menuBarSummary)
                    .font(.headline)
                Text(monitor.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Button("打开监控窗口") {
                    openWindow(id: "monitor")
                    NSApplication.shared.activate()
                }
                Button("重新枚举") {
                    monitor.refresh()
                }
                .disabled(monitor.isScanning)
                Button("退出 ThermalPulse") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 260)
        } label: {
            Label(monitor.menuBarSummary, systemImage: "thermometer.medium")
        }
        .menuBarExtraStyle(.window)
    }
}
