import SwiftUI
import ThermalPulseCore

struct TurboControlView: View {
    enum Style {
        case full
        case compact
    }

    private enum PendingConfirmation {
        case registerHelper
        case upgradeHelper

        var title: String {
            switch self {
            case .registerHelper: "注册 Turbo 系统 helper？"
            case .upgradeHelper: "升级 Turbo 系统 helper？"
            }
        }

        var message: String {
            switch self {
            case .registerHelper:
                "macOS 将登记一个仅服务 ThermalPulse 的 LaunchDaemon。注册后仍需由管理员在系统设置中明确允许，本操作不会立即写入 SMC。"
            case .upgradeHelper:
                "App 会先停止并注销旧 helper，再注册当前签名版本。升级不会启动 Turbo，也不会写入 SMC。"
            }
        }

        var actionTitle: String {
            switch self {
            case .registerHelper: "确认注册"
            case .upgradeHelper: "确认升级"
            }
        }

        var symbol: String {
            switch self {
            case .registerHelper: "person.badge.key.fill"
            case .upgradeHelper: "arrow.triangle.2.circlepath"
            }
        }
    }

    @EnvironmentObject private var monitor: ThermalMonitorViewModel
    @State private var pendingConfirmation: PendingConfirmation?
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: style == .compact ? 10 : 14) {
            header
            statusContent
        }
        .padding(style == .compact ? 12 : 18)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: style == .compact ? 14 : 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: style == .compact ? 14 : 18, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .orange.opacity(0.08), radius: 12, y: 5)
        .onAppear {
            monitor.refreshTurboHelperRegistration()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "fan.badge.automatic")
                .font(style == .compact ? .headline : .title3)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Turbo")
                    .font(style == .compact ? .headline : .title3.bold())
                Text("固定 10 分钟全速散热")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if let pendingConfirmation {
            confirmationContent(pendingConfirmation)
        } else {
            switch monitor.turboStatus.phase {
            case .inactive:
                inactiveContent
            case .activating:
                progressContent(title: "正在接管并等待风扇起转")
            case .active:
                activeContent
            case .restoring:
                progressContent(title: "正在恢复苹果自动风扇控制")
            case .failedSafeAuto:
                failureContent
            }
        }
    }

    private func confirmationContent(_ confirmation: PendingConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(confirmation.title, systemImage: confirmation.symbol)
                .font(.headline)
                .foregroundStyle(.orange)

            Text(confirmation.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("取消") {
                    pendingConfirmation = nil
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(confirmation.actionTitle) {
                    perform(confirmation)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("turbo.confirm.action")
            }
        }
    }

    private func perform(_ confirmation: PendingConfirmation) {
        pendingConfirmation = nil
        switch confirmation {
        case .registerHelper:
            monitor.registerTurboHelper()
        case .upgradeHelper:
            monitor.upgradeTurboHelper()
        }
    }

    @ViewBuilder
    private var inactiveContent: some View {
        switch monitor.turboHelperRegistrationState {
        case .checking:
            progressContent(title: monitor.turboHelperRegistrationState.userMessage)
        case .notRegistered, .notFound:
            notRegisteredContent
        case .registering:
            progressContent(title: monitor.turboHelperRegistrationState.userMessage)
        case .requiresApproval:
            approvalRequiredContent
        case .enabled:
            turboReadyInactiveContent
        case .failed:
            registrationFailureContent
        }
    }

    private var notRegisteredContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                monitor.turboHelperRegistrationState.userMessage,
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                pendingConfirmation = .registerHelper
            } label: {
                Label("注册 Turbo helper", systemImage: "person.badge.key.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: style == .compact ? 38 : 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .accessibilityIdentifier("turbo.helper.register")
        }
    }

    private var approvalRequiredContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                monitor.turboHelperRegistrationState.userMessage,
                systemImage: "gear.badge"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                monitor.openTurboHelperSystemSettings()
            } label: {
                Label("打开系统设置", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityIdentifier("turbo.helper.open-settings")

            Button("重新检查状态") {
                monitor.refreshTurboHelperRegistration()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }

    private var registrationFailureContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                monitor.turboHelperRegistrationState.userMessage,
                systemImage: "exclamationmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.red)

            Text("当前构建不会绕过 macOS 的签名、注册或管理员批准要求。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("重新检查状态") {
                monitor.refreshTurboHelperRegistration()
            }
            .buttonStyle(.bordered)
        }
    }

    private var turboReadyInactiveContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let issue = monitor.turboStatus.issue {
                Label(issue.userMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("启动前会确认所有风扇、最大转速、当前模式和外部控制冲突。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if monitor.turboStatus.issue == .writePathUnavailable
                || monitor.turboStatus.issue == .incompatibleProtocol
            {
                Button {
                    pendingConfirmation = .upgradeHelper
                } label: {
                    Label("升级 Turbo helper", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: style == .compact ? 38 : 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .accessibilityIdentifier("turbo.helper.upgrade")
            } else {
                Button {
                    monitor.startTurbo()
                } label: {
                    Label(startButtonTitle, systemImage: "bolt.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: style == .compact ? 38 : 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!monitor.turboStatus.canStart)
                .accessibilityIdentifier("turbo.start")
            }
        }
    }

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline) {
                    Text("剩余")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(remainingTimeText(at: context.date))
                        .font(.system(size: style == .compact ? 24 : 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text("所有已验证风扇")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive) {
                monitor.stopTurbo()
            } label: {
                Label("停止 Turbo，恢复自动", systemImage: "fan.badge.automatic")
                    .frame(maxWidth: .infinity)
                    .frame(height: style == .compact ? 36 : 40)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("turbo.stop")
        }
    }

    private func progressContent(title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var failureContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                monitor.turboStatus.issue?.userMessage ?? "Turbo 状态无法确认",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)

            Text("界面不会宣称已经恢复。请重新查询 helper 状态，真实恢复仍必须以风扇模式和实际 RPM 读回为准。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("重新查询状态") {
                monitor.synchronizeTurboStatus()
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusBadge: some View {
        Text(statusBadgeText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusBadgeTint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusBadgeTint.opacity(0.12), in: Capsule())
    }

    private var startButtonTitle: String {
        monitor.turboStatus.issue == nil ? "启动 10 分钟 Turbo" : "Turbo 暂不可用"
    }

    private var statusBadgeText: String {
        switch monitor.turboStatus.phase {
        case .inactive:
            if monitor.turboStatus.issue == nil {
                "苹果自动"
            } else if monitor.turboStatus.issue == .externalControllerDetected {
                "外部控制中"
            } else {
                "Turbo 不可用"
            }
        case .activating: "正在启动"
        case .active: "Turbo 运行中"
        case .restoring: "正在恢复"
        case .failedSafeAuto: "状态异常"
        }
    }

    private var statusBadgeTint: Color {
        switch monitor.turboStatus.phase {
        case .inactive:
            monitor.turboStatus.issue == nil ? .green : .orange
        case .activating, .active: .orange
        case .restoring: .blue
        case .failedSafeAuto: .red
        }
    }

    private func remainingTimeText(at date: Date) -> String {
        guard let remaining = monitor.turboStatus.remainingSeconds(at: date) else { return "--:--" }
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
}
