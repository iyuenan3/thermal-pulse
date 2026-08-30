import Foundation

public enum TurboPhase: String, Sendable, Equatable {
    case inactive
    case activating
    case active
    case restoring
    case failedSafeAuto
}

public enum TurboIssue: String, Error, Sendable, Equatable {
    case unsupportedHardware
    case noFans
    case fanEnumerationFailed
    case externalControllerDetected
    case helperUnavailable
    case helperNotApproved
    case writePathUnavailable
    case callerUnauthorized
    case incompatibleProtocol
    case smcWriteFailed
    case readbackMismatch
    case modeReadbackMismatch
    case targetReadbackMismatch
    case actualRPMReadbackMismatch
    case recoveryFailed
    case invalidStatusResponse
    case communicationFailure

    public var userMessage: String {
        switch self {
        case .unsupportedHardware:
            "当前硬件尚未通过 Turbo 验证"
        case .noFans:
            "没有发现可验证的风扇"
        case .fanEnumerationFailed:
            "无法确认全部风扇状态"
        case .externalControllerDetected:
            "其他工具正在手动控制风扇"
        case .helperUnavailable:
            "当前构建尚未连接 privileged helper"
        case .helperNotApproved:
            "需要先在系统设置中批准 helper"
        case .writePathUnavailable:
            "当前构建尚未启用 Turbo 写入链路"
        case .callerUnauthorized:
            "App 身份未通过 helper 校验"
        case .incompatibleProtocol:
            "App 与 helper 版本不兼容"
        case .smcWriteFailed:
            "无法确认风扇控制写入"
        case .readbackMismatch:
            "风扇模式或实际转速读回不一致"
        case .modeReadbackMismatch:
            "风扇手动模式读回不一致"
        case .targetReadbackMismatch:
            "风扇最大目标转速读回不一致"
        case .actualRPMReadbackMismatch:
            "风扇实际转速读回不在可信范围"
        case .recoveryFailed:
            "无法确认风扇已经恢复自动模式"
        case .invalidStatusResponse:
            "helper 返回了不符合安全契约的状态"
        case .communicationFailure:
            "无法连接 Turbo helper"
        }
    }
}

public struct TurboStatus: Sendable, Equatable {
    public static let maximumDuration: TimeInterval = 600

    public let phase: TurboPhase
    public let startedAt: Date?
    public let deadline: Date?
    public let issue: TurboIssue?

    public init(
        phase: TurboPhase,
        startedAt: Date? = nil,
        deadline: Date? = nil,
        issue: TurboIssue? = nil
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.deadline = deadline
        self.issue = issue
    }

    public static func inactive(issue: TurboIssue? = nil) -> Self {
        Self(phase: .inactive, issue: issue)
    }

    public var canStart: Bool {
        phase == .inactive && issue == nil
    }

    public var canStop: Bool {
        phase == .activating || phase == .active
    }

    public var fanControlUserMessage: String {
        switch phase {
        case .inactive:
            if issue == nil {
                "苹果自动控制"
            } else if issue == .externalControllerDetected {
                "其他工具手动控制"
            } else {
                "控制状态待确认"
            }
        case .activating:
            "正在切换到 Turbo"
        case .active:
            "Turbo 全速控制"
        case .restoring:
            "正在恢复苹果自动控制"
        case .failedSafeAuto:
            "控制状态待确认"
        }
    }

    public func remainingSeconds(at date: Date) -> Int? {
        guard phase == .active, let deadline else { return nil }
        return max(0, Int(ceil(deadline.timeIntervalSince(date))))
    }
}

public protocol TurboClient: Sendable {
    func startTurbo() async throws -> TurboStatus
    func stopTurbo() async throws -> TurboStatus
    func getTurboStatus() async throws -> TurboStatus
}

public enum TurboHelperRegistrationIssue: String, Sendable, Equatable {
    case invalidSignature
    case invalidInstallation
    case installerUnavailable
    case registrationFailed
    case upgradeFailed

    public var userMessage: String {
        switch self {
        case .invalidSignature:
            "当前签名不满足系统 helper 注册要求"
        case .invalidInstallation:
            "Turbo helper 安装身份无效或已变化"
        case .installerUnavailable:
            "当前 App 缺少 Turbo helper 安装器"
        case .registrationFailed:
            "系统没有接受 Turbo helper 注册"
        case .upgradeFailed:
            "系统没有完成 Turbo helper 升级"
        }
    }
}

public enum TurboHelperRegistrationState: Sendable, Equatable {
    case checking
    case notRegistered
    case registering
    case requiresApproval
    case manualInstallationRequired
    case installerOpened
    case enabled
    case notFound
    case failed(TurboHelperRegistrationIssue)

    public var canRegister: Bool {
        self == .notRegistered || self == .notFound || self == .manualInstallationRequired
    }

    public var canOpenSystemSettings: Bool {
        self == .requiresApproval
    }

    public var userMessage: String {
        switch self {
        case .checking:
            "正在检查 Turbo helper"
        case .notRegistered:
            "Turbo helper 尚未注册"
        case .registering:
            "正在向 macOS 注册 Turbo helper"
        case .requiresApproval:
            "需要在系统设置中允许 ThermalPulse 后台项目"
        case .manualInstallationRequired:
            "需要管理员安装当前版本的 Turbo helper"
        case .installerOpened:
            "安装器已在 Terminal 中打开，完成后请重新检查"
        case .enabled:
            "Turbo helper 已获系统允许"
        case .notFound:
            "系统尚未登记 Turbo helper"
        case let .failed(issue):
            issue.userMessage
        }
    }
}

@MainActor
public protocol TurboHelperRegistrationClient: AnyObject {
    func currentState() -> TurboHelperRegistrationState
    func register() -> TurboHelperRegistrationState
    func replaceRegistration() async -> TurboHelperRegistrationState
    func openSystemSettings()
}

@MainActor
public final class TurboHelperRegistrationCoordinator {
    private let client: any TurboHelperRegistrationClient
    public private(set) var state: TurboHelperRegistrationState

    public init(
        client: any TurboHelperRegistrationClient,
        initialState: TurboHelperRegistrationState = .checking
    ) {
        self.client = client
        state = initialState
    }

    @discardableResult
    public func refresh() -> TurboHelperRegistrationState {
        state = client.currentState()
        return state
    }

    @discardableResult
    public func register() -> TurboHelperRegistrationState {
        guard state.canRegister else { return state }
        state = .registering
        state = client.register()
        return state
    }

    @discardableResult
    public func replaceRegistration() async -> TurboHelperRegistrationState {
        guard state == .enabled else { return state }
        state = .registering
        state = await client.replaceRegistration()
        return state
    }

    public func openSystemSettings() {
        guard state.canOpenSystemSettings else { return }
        client.openSystemSettings()
    }
}

public struct UnavailableTurboClient: TurboClient {
    public init() {}

    public func startTurbo() async throws -> TurboStatus {
        throw TurboIssue.helperUnavailable
    }

    public func stopTurbo() async throws -> TurboStatus {
        TurboStatus.inactive(issue: .helperUnavailable)
    }

    public func getTurboStatus() async throws -> TurboStatus {
        TurboStatus.inactive(issue: .helperUnavailable)
    }
}

public actor TurboCoordinator {
    private let client: any TurboClient
    private var status: TurboStatus

    public init(
        client: any TurboClient,
        initialStatus: TurboStatus = .inactive()
    ) {
        self.client = client
        status = initialStatus
    }

    public func currentStatus() -> TurboStatus {
        status
    }

    @discardableResult
    public func synchronize(now: Date = Date()) async -> TurboStatus {
        do {
            status = validatedStatus(try await client.getTurboStatus(), now: now)
        } catch {
            status = failureStatus(for: issue(from: error))
        }
        return status
    }

    @discardableResult
    public func startTurbo(now: Date = Date()) async -> TurboStatus {
        guard status.canStart else { return status }
        status = TurboStatus(phase: .activating)

        do {
            let response = try await client.startTurbo()
            status = validatedStartResponse(response, now: now)
        } catch {
            let issue = issue(from: error)
            status = failureStatus(for: issue)
        }
        return status
    }

    @discardableResult
    public func stopTurbo() async -> TurboStatus {
        guard status.canStop else { return status }
        status = TurboStatus(phase: .restoring)

        do {
            let response = try await client.stopTurbo()
            if response.phase == .inactive, response.issue == nil {
                status = response
            } else if response.phase == .failedSafeAuto, response.issue != nil {
                status = response
            } else {
                status = TurboStatus(phase: .failedSafeAuto, issue: .invalidStatusResponse)
            }
        } catch {
            status = TurboStatus(phase: .failedSafeAuto, issue: issue(from: error))
        }
        return status
    }

    private func validatedStartResponse(_ response: TurboStatus, now: Date) -> TurboStatus {
        if response.phase == .inactive, response.issue != nil,
           response.startedAt == nil, response.deadline == nil {
            return response
        }
        if response.phase == .failedSafeAuto, response.issue != nil {
            return response
        }
        guard response.phase == .active,
              response.issue == nil,
              let startedAt = response.startedAt,
              let deadline = response.deadline
        else {
            return TurboStatus(phase: .failedSafeAuto, issue: .invalidStatusResponse)
        }

        let duration = deadline.timeIntervalSince(startedAt)
        guard deadline > now,
              duration > 0,
              duration <= TurboStatus.maximumDuration
        else {
            return TurboStatus(phase: .failedSafeAuto, issue: .invalidStatusResponse)
        }
        return response
    }

    private func validatedStatus(_ response: TurboStatus, now: Date) -> TurboStatus {
        switch response.phase {
        case .active:
            return validatedStartResponse(response, now: now)
        case .inactive:
            guard response.startedAt == nil, response.deadline == nil else {
                return TurboStatus(phase: .failedSafeAuto, issue: .invalidStatusResponse)
            }
            return response
        case .failedSafeAuto:
            guard response.issue != nil else {
                return TurboStatus(phase: .failedSafeAuto, issue: .invalidStatusResponse)
            }
            return response
        case .activating, .restoring:
            guard let startedAt = response.startedAt,
                  let deadline = response.deadline,
                  deadline.timeIntervalSince(startedAt) > 0,
                  deadline.timeIntervalSince(startedAt) <= TurboStatus.maximumDuration
            else {
                return TurboStatus(phase: .failedSafeAuto, issue: .invalidStatusResponse)
            }
            return response
        }
    }

    private func issue(from error: Error) -> TurboIssue {
        error as? TurboIssue ?? .communicationFailure
    }

    private func failureStatus(for issue: TurboIssue) -> TurboStatus {
        switch issue {
        case .unsupportedHardware,
             .noFans,
             .fanEnumerationFailed,
             .externalControllerDetected,
             .helperUnavailable,
             .helperNotApproved,
             .writePathUnavailable,
             .callerUnauthorized,
             .incompatibleProtocol:
            .inactive(issue: issue)
        case .smcWriteFailed,
             .readbackMismatch,
             .modeReadbackMismatch,
             .targetReadbackMismatch,
             .actualRPMReadbackMismatch,
             .recoveryFailed,
             .invalidStatusResponse,
             .communicationFailure:
            TurboStatus(phase: .failedSafeAuto, issue: issue)
        }
    }
}
