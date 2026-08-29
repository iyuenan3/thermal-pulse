import Foundation

public enum TurboFanMode: Sendable, Equatable {
    case automatic
    case manual
    case system
}

public struct TurboFanDescriptor: Sendable, Equatable {
    public let index: Int
    public let modeKey: String
    public let maximumRPM: Double
    public let baselineActualRPM: Double

    public init(
        index: Int,
        modeKey: String,
        maximumRPM: Double,
        baselineActualRPM: Double
    ) {
        self.index = index
        self.modeKey = modeKey
        self.maximumRPM = maximumRPM
        self.baselineActualRPM = baselineActualRPM
    }
}

public enum TurboFanHardwareError: Error, Sendable, Equatable {
    case unavailable
    case unsupportedHardware
    case invalidData
    case thermalManagerBusy
    case readFailed
    case writeFailed
}

public protocol TurboFanHardware: Sendable {
    func discoverFans() throws -> [TurboFanDescriptor]
    func readMode(of fan: TurboFanDescriptor) throws -> TurboFanMode
    func writeManualMode(to fan: TurboFanDescriptor) throws
    func writeAutomaticMode(to fan: TurboFanDescriptor) throws
    func writeMaximumTarget(to fan: TurboFanDescriptor) throws
    func readTargetRPM(of fan: TurboFanDescriptor) throws -> Double
    func readActualRPM(of fan: TurboFanDescriptor) throws -> Double
    func readThermalManagerUnlock() throws -> Bool?
    func writeThermalManagerUnlock(_ enabled: Bool) throws
}

public struct TurboLeaseFan: Codable, Sendable, Equatable {
    public let index: Int
    public let modeKey: String

    public init(index: Int, modeKey: String) {
        self.index = index
        self.modeKey = modeKey
    }
}

public struct TurboLease: Codable, Sendable, Equatable {
    public let startedAt: Date
    public let deadline: Date
    public var touchedFans: [TurboLeaseFan]
    public var claimedThermalManagerUnlock: Bool

    public init(
        startedAt: Date,
        deadline: Date,
        touchedFans: [TurboLeaseFan] = [],
        claimedThermalManagerUnlock: Bool = false
    ) {
        self.startedAt = startedAt
        self.deadline = deadline
        self.touchedFans = touchedFans
        self.claimedThermalManagerUnlock = claimedThermalManagerUnlock
    }
}

public protocol TurboLeaseStore: Sendable {
    func load() throws -> TurboLease?
    func save(_ lease: TurboLease) throws
    func remove() throws
}

public protocol TurboSafetyClock: Sendable {
    func now() -> Date
    func monotonicNow() -> TimeInterval
    func sleep(for duration: TimeInterval) async throws
}

public struct SystemTurboSafetyClock: TurboSafetyClock {
    public init() {}

    public func now() -> Date {
        Date()
    }

    public func monotonicNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    public func sleep(for duration: TimeInterval) async throws {
        guard duration > 0 else { return }
        try await Task.sleep(for: .seconds(duration))
    }
}

public struct TurboSafetyPolicy: Sendable, Equatable {
    public let unlockSettleDelay: TimeInterval
    public let manualModeRetryCount: Int
    public let manualModeRetryDelay: TimeInterval
    public let restoreRetryCount: Int
    public let restoreRetryDelay: TimeInterval
    public let actualReadbackAttemptCount: Int
    public let actualReadbackDelay: TimeInterval
    public let minimumActualRiseRPM: Double
    public let maximumTargetToleranceRPM: Double
    public let alreadyAtMaximumFraction: Double

    public init(
        unlockSettleDelay: TimeInterval = 3,
        manualModeRetryCount: Int = 300,
        manualModeRetryDelay: TimeInterval = 0.1,
        restoreRetryCount: Int = 20,
        restoreRetryDelay: TimeInterval = 0.05,
        actualReadbackAttemptCount: Int = 80,
        actualReadbackDelay: TimeInterval = 0.25,
        minimumActualRiseRPM: Double = 100,
        maximumTargetToleranceRPM: Double = 5,
        alreadyAtMaximumFraction: Double = 0.9
    ) {
        self.unlockSettleDelay = unlockSettleDelay
        self.manualModeRetryCount = max(1, manualModeRetryCount)
        self.manualModeRetryDelay = manualModeRetryDelay
        self.restoreRetryCount = max(1, restoreRetryCount)
        self.restoreRetryDelay = restoreRetryDelay
        self.actualReadbackAttemptCount = max(1, actualReadbackAttemptCount)
        self.actualReadbackDelay = actualReadbackDelay
        self.minimumActualRiseRPM = minimumActualRiseRPM
        self.maximumTargetToleranceRPM = maximumTargetToleranceRPM
        self.alreadyAtMaximumFraction = alreadyAtMaximumFraction
    }
}

public actor TurboSafetyController {
    private let hardware: any TurboFanHardware
    private let leaseStore: any TurboLeaseStore
    private let clock: any TurboSafetyClock
    private let policy: TurboSafetyPolicy

    private var status: TurboStatus
    private var lease: TurboLease?
    private var ownerID: UUID?
    private var monotonicDeadline: TimeInterval?
    private var hasBootstrapped = false

    public init(
        hardware: any TurboFanHardware,
        leaseStore: any TurboLeaseStore,
        clock: any TurboSafetyClock = SystemTurboSafetyClock(),
        policy: TurboSafetyPolicy = TurboSafetyPolicy()
    ) {
        self.hardware = hardware
        self.leaseStore = leaseStore
        self.clock = clock
        self.policy = policy

        do {
            let persistedLease = try leaseStore.load()
            lease = persistedLease
            status = persistedLease == nil
                ? .inactive()
                : TurboStatus(phase: .restoring, issue: nil)
        } catch {
            lease = nil
            status = TurboStatus(phase: .failedSafeAuto, issue: .recoveryFailed)
        }
    }

    @discardableResult
    public func bootstrap() async -> TurboStatus {
        guard !hasBootstrapped else { return status }
        hasBootstrapped = true
        guard lease != nil else { return status }
        return await restore(issueAfterConfirmedRestore: nil)
    }

    public func currentStatus() async -> TurboStatus {
        if status.phase == .active, hasExpired() {
            return await restore(issueAfterConfirmedRestore: nil)
        }
        return status
    }

    @discardableResult
    public func startTurbo(ownerID requestedOwnerID: UUID) async -> TurboStatus {
        if !hasBootstrapped {
            _ = await bootstrap()
        }
        guard status.phase == .inactive, status.issue == nil, lease == nil else {
            return status
        }

        let fans: [TurboFanDescriptor]
        do {
            fans = try hardware.discoverFans()
        } catch let error as TurboFanHardwareError where error == .unsupportedHardware {
            status = .inactive(issue: .unsupportedHardware)
            return status
        } catch {
            status = .inactive(issue: .fanEnumerationFailed)
            return status
        }

        guard !fans.isEmpty else {
            status = .inactive(issue: .noFans)
            return status
        }
        guard Self.hasValidDynamicFanSet(fans) else {
            status = .inactive(issue: .fanEnumerationFailed)
            return status
        }

        do {
            if try hardware.readThermalManagerUnlock() == true {
                status = .inactive(issue: .externalControllerDetected)
                return status
            }
            for fan in fans {
                if try hardware.readMode(of: fan) != .automatic {
                    status = .inactive(issue: .externalControllerDetected)
                    return status
                }
            }
        } catch {
            status = .inactive(issue: .fanEnumerationFailed)
            return status
        }

        let startedAt = clock.now()
        var newLease = TurboLease(
            startedAt: startedAt,
            deadline: startedAt.addingTimeInterval(TurboStatus.maximumDuration)
        )
        do {
            try leaseStore.save(newLease)
        } catch {
            status = TurboStatus(phase: .failedSafeAuto, issue: .recoveryFailed)
            return status
        }

        lease = newLease
        ownerID = requestedOwnerID
        monotonicDeadline = clock.monotonicNow() + TurboStatus.maximumDuration
        status = TurboStatus(
            phase: .activating,
            startedAt: newLease.startedAt,
            deadline: newLease.deadline
        )

        do {
            for fan in fans {
                try ensureLeaseIsOwned(by: requestedOwnerID)
                newLease.touchedFans.append(TurboLeaseFan(index: fan.index, modeKey: fan.modeKey))
                try leaseStore.save(newLease)
                lease = newLease

                do {
                    try hardware.writeManualMode(to: fan)
                } catch let error as TurboFanHardwareError where error == .thermalManagerBusy {
                    if !newLease.claimedThermalManagerUnlock {
                        newLease.claimedThermalManagerUnlock = true
                        try leaseStore.save(newLease)
                        lease = newLease
                        try hardware.writeThermalManagerUnlock(true)
                        try await clock.sleep(for: policy.unlockSettleDelay)
                        try ensureLeaseIsOwned(by: requestedOwnerID)
                    }
                    try await retryManualMode(for: fan, ownerID: requestedOwnerID)
                }

                try ensureLeaseIsOwned(by: requestedOwnerID)
                try hardware.writeMaximumTarget(to: fan)
            }

            try verifyModesAndTargets(fans)
            try await verifyActualRPMRise(fans, ownerID: requestedOwnerID)
            try ensureLeaseIsOwned(by: requestedOwnerID)

            status = TurboStatus(
                phase: .active,
                startedAt: newLease.startedAt,
                deadline: newLease.deadline
            )
            return status
        } catch is CancellationError {
            return status
        } catch {
            guard lease != nil else { return status }
            let issue: TurboIssue = error is TurboReadbackError ? .readbackMismatch : .smcWriteFailed
            return await restore(issueAfterConfirmedRestore: issue)
        }
    }

    @discardableResult
    public func stopTurbo() async -> TurboStatus {
        guard lease != nil else {
            if status.phase == .inactive { return status }
            return TurboStatus(phase: .failedSafeAuto, issue: .recoveryFailed)
        }
        return await restore(issueAfterConfirmedRestore: nil)
    }

    @discardableResult
    public func connectionInvalidated(ownerID invalidatedOwnerID: UUID) async -> TurboStatus {
        guard ownerID == invalidatedOwnerID, lease != nil else { return status }
        return await restore(issueAfterConfirmedRestore: nil)
    }

    @discardableResult
    public func systemDidWake() async -> TurboStatus {
        guard lease != nil else { return status }
        return await restore(issueAfterConfirmedRestore: nil)
    }

    @discardableResult
    public func watchdogTick() async -> TurboStatus {
        guard let lease else { return status }
        if hasExpired() {
            return await restore(issueAfterConfirmedRestore: nil)
        }

        guard status.phase == .active else { return status }
        do {
            for leaseFan in lease.touchedFans {
                let fan = Self.recoveryDescriptor(for: leaseFan)
                guard try hardware.readMode(of: fan) == .manual else {
                    throw TurboReadbackError.mismatch
                }
                _ = try hardware.readActualRPM(of: fan)
            }
            return status
        } catch {
            return await restore(issueAfterConfirmedRestore: .readbackMismatch)
        }
    }

    private func retryManualMode(for fan: TurboFanDescriptor, ownerID: UUID) async throws {
        var lastError: Error = TurboFanHardwareError.writeFailed
        for attempt in 0..<policy.manualModeRetryCount {
            try ensureLeaseIsOwned(by: ownerID)
            do {
                try hardware.writeManualMode(to: fan)
                return
            } catch {
                lastError = error
            }
            if attempt + 1 < policy.manualModeRetryCount {
                try await clock.sleep(for: policy.manualModeRetryDelay)
            }
        }
        throw lastError
    }

    private func verifyModesAndTargets(_ fans: [TurboFanDescriptor]) throws {
        for fan in fans {
            guard try hardware.readMode(of: fan) == .manual else {
                throw TurboReadbackError.mismatch
            }
            let target = try hardware.readTargetRPM(of: fan)
            guard target.isFinite,
                  abs(target - fan.maximumRPM) <= policy.maximumTargetToleranceRPM
            else {
                throw TurboReadbackError.mismatch
            }
        }
    }

    private func verifyActualRPMRise(_ fans: [TurboFanDescriptor], ownerID: UUID) async throws {
        for attempt in 0..<policy.actualReadbackAttemptCount {
            try ensureLeaseIsOwned(by: ownerID)
            let allVerified = try fans.allSatisfy { fan in
                let actual = try hardware.readActualRPM(of: fan)
                guard actual.isFinite, actual >= 0 else { return false }
                return actual >= fan.baselineActualRPM + policy.minimumActualRiseRPM
                    || actual >= fan.maximumRPM * policy.alreadyAtMaximumFraction
            }
            if allVerified { return }
            if attempt + 1 < policy.actualReadbackAttemptCount {
                try await clock.sleep(for: policy.actualReadbackDelay)
            }
        }
        throw TurboReadbackError.mismatch
    }

    private func ensureLeaseIsOwned(by expectedOwnerID: UUID) throws {
        guard lease != nil, ownerID == expectedOwnerID else {
            throw CancellationError()
        }
    }

    private func restore(issueAfterConfirmedRestore: TurboIssue?) async -> TurboStatus {
        guard let lease else {
            status = issueAfterConfirmedRestore.map {
                TurboStatus(phase: .failedSafeAuto, issue: $0)
            } ?? .inactive()
            ownerID = nil
            return status
        }

        status = TurboStatus(
            phase: .restoring,
            startedAt: lease.startedAt,
            deadline: lease.deadline
        )

        do {
            for leaseFan in lease.touchedFans.reversed() {
                guard Self.isValidPersistedFan(leaseFan) else {
                    throw TurboFanHardwareError.invalidData
                }
                let fan = Self.recoveryDescriptor(for: leaseFan)
                try await retryAutomaticMode(for: fan)
            }

            for leaseFan in lease.touchedFans {
                let fan = Self.recoveryDescriptor(for: leaseFan)
                guard try hardware.readMode(of: fan) == .automatic else {
                    throw TurboReadbackError.mismatch
                }
                let actual = try hardware.readActualRPM(of: fan)
                guard actual.isFinite, actual >= 0 else {
                    throw TurboReadbackError.mismatch
                }
            }

            if lease.claimedThermalManagerUnlock {
                try hardware.writeThermalManagerUnlock(false)
                guard try hardware.readThermalManagerUnlock() == false else {
                    throw TurboReadbackError.mismatch
                }
            }

            try leaseStore.remove()
            self.lease = nil
            ownerID = nil
            monotonicDeadline = nil
            status = issueAfterConfirmedRestore.map {
                TurboStatus(phase: .failedSafeAuto, issue: $0)
            } ?? .inactive()
            return status
        } catch {
            status = TurboStatus(
                phase: .failedSafeAuto,
                startedAt: lease.startedAt,
                deadline: lease.deadline,
                issue: .recoveryFailed
            )
            return status
        }
    }

    private func retryAutomaticMode(for fan: TurboFanDescriptor) async throws {
        var lastError: Error = TurboFanHardwareError.writeFailed
        for attempt in 0..<policy.restoreRetryCount {
            do {
                try hardware.writeAutomaticMode(to: fan)
                return
            } catch {
                lastError = error
            }
            if attempt + 1 < policy.restoreRetryCount {
                try await clock.sleep(for: policy.restoreRetryDelay)
            }
        }
        throw lastError
    }

    private static func hasValidDynamicFanSet(_ fans: [TurboFanDescriptor]) -> Bool {
        guard fans.count <= 16,
              Set(fans.map(\.index)).count == fans.count
        else { return false }

        return fans.allSatisfy { fan in
            fan.index >= 0
                && fan.index < 16
                && fan.maximumRPM.isFinite
                && fan.maximumRPM > 0
                && fan.maximumRPM <= 20_000
                && fan.baselineActualRPM.isFinite
                && fan.baselineActualRPM >= 0
                && isValidPersistedFan(TurboLeaseFan(index: fan.index, modeKey: fan.modeKey))
        }
    }

    private func hasExpired() -> Bool {
        guard let lease else { return false }
        if clock.now() >= lease.deadline { return true }
        if let monotonicDeadline, clock.monotonicNow() >= monotonicDeadline { return true }
        return false
    }

    private static func isValidPersistedFan(_ fan: TurboLeaseFan) -> Bool {
        guard fan.index >= 0, fan.index < 16 else { return false }
        let digit = String(fan.index, radix: 16, uppercase: true)
        return fan.modeKey == "F\(digit)Md" || fan.modeKey == "F\(digit)md"
    }

    private static func recoveryDescriptor(for fan: TurboLeaseFan) -> TurboFanDescriptor {
        TurboFanDescriptor(
            index: fan.index,
            modeKey: fan.modeKey,
            maximumRPM: 0,
            baselineActualRPM: 0
        )
    }
}

private enum TurboReadbackError: Error {
    case mismatch
}
