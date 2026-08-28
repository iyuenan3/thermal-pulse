import SwiftUI

@main
struct ThermalPulseApp: App {
    @StateObject private var monitor = ThermalMonitorViewModel()

    var body: some Scene {
        WindowGroup("ThermalPulse") {
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
