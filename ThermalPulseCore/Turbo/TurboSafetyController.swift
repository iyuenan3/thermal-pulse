import Foundation

public enum TurboFanMode: Sendable, Equatable {
    case automatic
    case manual
    case system

    public init?(appleSiliconSMCRawValue value: UInt8) {
        switch value {
        case 0: self = .automatic
        case 1: self = .manual
        case 3: self = .system
        default: return nil
        }
    }

    public var isAppleManaged: Bool {
        switch self {
        case .automatic, .system: true
        case .manual: false
        }
    }
}

public struct TurboFanDiagnosticSample: Sendable, Equatable {
    public let fanIndex: Int
    public let baselineRPM: Double
    public let maximumRPM: Double
    public let actualRPM: Double?

    public init(
        fanIndex: Int,
        baselineRPM: Double,
        maximumRPM: Double,
        actualRPM: Double?
    ) {
        self.fanIndex = fanIndex
        self.baselineRPM = baselineRPM
        self.maximumRPM = maximumRPM
        self.actualRPM = actualRPM
    }
}

public enum TurboDiagnosticEvent: Sendable, Equatable {
    case activationStarted(fanCount: Int)
    case thermalManagerUnlockClaimed(fanIndex: Int)
    case modeReadbackMismatch(fanIndex: Int, observed: TurboFanMode?)
    case targetReadbackMismatch(fanIndex: Int, expectedRPM: Double, observedRPM: Double?)
    case actualRPMReadbackFailed(samples: [TurboFanDiagnosticSample])
    case actualRPMRiseVerified(samples: [TurboFanDiagnosticSample])
    case restorationCompleted(issue: TurboIssue?)
    case restorationFailed(stage: TurboRestorationStage, fanIndex: Int?)
}

public enum TurboRestorationStage: String, Sendable, Equatable {
    case fanMode
    case actualRPM
    case thermalManagerUnlock
    case leaseRemoval
}

public protocol TurboDiagnosticSink: Sendable {
    func record(_ event: TurboDiagnosticEvent)
}

public struct NoOpTurboDiagnosticSink: TurboDiagnosticSink {
    public init() {}

    public func record(_ event: TurboDiagnosticEvent) {}
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
    public let unlockClaimPollInterval: TimeInterval
    public let unlockClaimStableReadCount: Int
    public let manualModeRetryCount: Int
    public let manualModeRetryDelay: TimeInterval
    public let activeReconciliationRetryCount: Int
    public let activeReconciliationRetryDelay: TimeInterval
    public let restoreRetryCount: Int
    public let restoreRetryDelay: TimeInterval
    public let actualReadbackAttemptCount: Int
    public let actualReadbackDelay: TimeInterval
    public let minimumActualRiseRPM: Double
    public let maximumTargetToleranceRPM: Double
    public let alreadyAtMaximumFraction: Double
    public let maximumActualOvershootFraction: Double

    public init(
        unlockSettleDelay: TimeInterval = 3,
        unlockClaimPollInterval: TimeInterval = 0.1,
        unlockClaimStableReadCount: Int = 2,
        manualModeRetryCount: Int = 300,
        manualModeRetryDelay: TimeInterval = 0.1,
        activeReconciliationRetryCount: Int = 10,
        activeReconciliationRetryDelay: TimeInterval = 0.05,
        restoreRetryCount: Int = 20,
        restoreRetryDelay: TimeInterval = 0.05,
        actualReadbackAttemptCount: Int = 80,
        actualReadbackDelay: TimeInterval = 0.25,
        minimumActualRiseRPM: Double = 100,
        maximumTargetToleranceRPM: Double = 5,
        alreadyAtMaximumFraction: Double = 0.9,
        maximumActualOvershootFraction: Double = 0.05
    ) {
        self.unlockSettleDelay = max(0, unlockSettleDelay)
        self.unlockClaimPollInterval = max(0.01, unlockClaimPollInterval)
        self.unlockClaimStableReadCount = max(1, unlockClaimStableReadCount)
        self.manualModeRetryCount = max(1, manualModeRetryCount)
        self.manualModeRetryDelay = manualModeRetryDelay
        self.activeReconciliationRetryCount = max(1, activeReconciliationRetryCount)
        self.activeReconciliationRetryDelay = activeReconciliationRetryDelay
        self.restoreRetryCount = max(1, restoreRetryCount)
        self.restoreRetryDelay = restoreRetryDelay
        self.actualReadbackAttemptCount = max(1, actualReadbackAttemptCount)
        self.actualReadbackDelay = actualReadbackDelay
        self.minimumActualRiseRPM = minimumActualRiseRPM
        self.maximumTargetToleranceRPM = maximumTargetToleranceRPM
        self.alreadyAtMaximumFraction = alreadyAtMaximumFraction
        self.maximumActualOvershootFraction = maximumActualOvershootFraction.isFinite
            && maximumActualOvershootFraction >= 0
            ? maximumActualOvershootFraction
            : 0
    }

    public func isActualRPMPlausible(_ actualRPM: Double, maximumRPM: Double) -> Bool {
        guard actualRPM.isFinite,
              actualRPM >= 0,
              maximumRPM.isFinite,
              maximumRPM > 0
        else {
            return false
        }
        return actualRPM <= maximumRPM * (1 + maximumActualOvershootFraction)
    }
}

public actor TurboSafetyController {
    private let hardware: any TurboFanHardware
    private let leaseStore: any TurboLeaseStore
    private let clock: any TurboSafetyClock
    private let policy: TurboSafetyPolicy
    private let diagnosticSink: any TurboDiagnosticSink

    private var status: TurboStatus
    private var lease: TurboLease?
    private var ownerID: UUID?
    private var monotonicDeadline: TimeInterval?
    private var hasBootstrapped = false

    public init(
        hardware: any TurboFanHardware,
        leaseStore: any TurboLeaseStore,
        clock: any TurboSafetyClock = SystemTurboSafetyClock(),
        policy: TurboSafetyPolicy = TurboSafetyPolicy(),
        diagnosticSink: any TurboDiagnosticSink = NoOpTurboDiagnosticSink()
    ) {
        self.hardware = hardware
        self.leaseStore = leaseStore
        self.clock = clock
        self.policy = policy
        self.diagnosticSink = diagnosticSink

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
        diagnosticSink.record(.activationStarted(fanCount: fans.count))

        let systemManagedFanIndex: Int?
        let canClaimThermalManagerUnlock: Bool
        do {
            let thermalManagerUnlock = try hardware.readThermalManagerUnlock()
            if thermalManagerUnlock == true {
                status = .inactive(issue: .externalControllerDetected)
                return status
            }
            var firstSystemManagedFanIndex: Int?
            for fan in fans {
                let mode = try hardware.readMode(of: fan)
                if !mode.isAppleManaged {
                    status = .inactive(issue: .externalControllerDetected)
                    return status
                }
                if mode == .system, firstSystemManagedFanIndex == nil {
                    firstSystemManagedFanIndex = fan.index
                }
            }
            if thermalManagerUnlock == nil, firstSystemManagedFanIndex != nil {
                status = .inactive(issue: .unsupportedHardware)
                return status
            }
            canClaimThermalManagerUnlock = thermalManagerUnlock == false
            systemManagedFanIndex = canClaimThermalManagerUnlock
                ? firstSystemManagedFanIndex
                : nil
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
            if let systemManagedFanIndex {
                try await claimThermalManagerUnlock(
                    lease: &newLease,
                    fanIndex: systemManagedFanIndex,
                    ownerID: requestedOwnerID
                )
            }

            for fan in fans {
                try ensureLeaseIsOwned(by: requestedOwnerID)
                newLease.touchedFans.append(TurboLeaseFan(index: fan.index, modeKey: fan.modeKey))
                try leaseStore.save(newLease)
                lease = newLease

                do {
                    try hardware.writeManualMode(to: fan)
                    guard try hardware.readMode(of: fan) == .manual else {
                        throw TurboFanHardwareError.thermalManagerBusy
                    }
                } catch let error as TurboFanHardwareError where error == .thermalManagerBusy {
                    if !newLease.claimedThermalManagerUnlock {
                        guard canClaimThermalManagerUnlock else {
                            throw error
                        }
                        try await claimThermalManagerUnlock(
                            lease: &newLease,
                            fanIndex: fan.index,
                            ownerID: requestedOwnerID
                        )
                    }
                    try await retryManualMode(for: fan, ownerID: requestedOwnerID)
                }

                try ensureLeaseIsOwned(by: requestedOwnerID)
                try hardware.writeMaximumTarget(to: fan)
            }

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
            let issue: TurboIssue
            switch error as? TurboReadbackError {
            case .mode:
                issue = .modeReadbackMismatch
            case .target:
                issue = .targetReadbackMismatch
            case .actualRPM:
                issue = .actualRPMReadbackMismatch
            case nil:
                issue = .smcWriteFailed
            }
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
        if status.phase == .failedSafeAuto {
            return await restore(issueAfterConfirmedRestore: nil)
        }
        if hasExpired() {
            return await restore(issueAfterConfirmedRestore: nil)
        }

        guard status.phase == .active else { return status }
        do {
            try await reconcileActiveTurbo(lease)
            return status
        } catch {
            let issue: TurboIssue
            switch error as? TurboReadbackError {
            case .mode:
                issue = .modeReadbackMismatch
            case .target:
                issue = .targetReadbackMismatch
            case .actualRPM:
                issue = .actualRPMReadbackMismatch
            case nil:
                issue = .readbackMismatch
            }
            return await restore(issueAfterConfirmedRestore: issue)
        }
    }

    private func claimThermalManagerUnlock(
        lease newLease: inout TurboLease,
        fanIndex: Int,
        ownerID: UUID
    ) async throws {
        guard !newLease.claimedThermalManagerUnlock else { return }
        newLease.claimedThermalManagerUnlock = true
        try leaseStore.save(newLease)
        lease = newLease
        try hardware.writeThermalManagerUnlock(true)
        try await waitForClaimedThermalManagerUnlock(ownerID: ownerID)
        diagnosticSink.record(.thermalManagerUnlockClaimed(fanIndex: fanIndex))
    }

    private func waitForClaimedThermalManagerUnlock(ownerID: UUID) async throws {
        let deadline = clock.monotonicNow() + policy.unlockSettleDelay
        var consecutiveClaimedReads = 0

        while true {
            try ensureLeaseIsOwned(by: ownerID)
            if try hardware.readThermalManagerUnlock() == true {
                consecutiveClaimedReads += 1
                if consecutiveClaimedReads >= policy.unlockClaimStableReadCount {
                    return
                }
            } else {
                consecutiveClaimedReads = 0
            }

            let remaining = deadline - clock.monotonicNow()
            guard remaining > 0 else {
                throw TurboReadbackError.mode
            }
            try await clock.sleep(
                for: min(policy.unlockClaimPollInterval, remaining)
            )
        }
    }

    private func retryManualMode(for fan: TurboFanDescriptor, ownerID: UUID) async throws {
        var lastError: Error = TurboFanHardwareError.writeFailed
        for attempt in 0..<policy.manualModeRetryCount {
            try ensureLeaseIsOwned(by: ownerID)
            do {
                try hardware.writeManualMode(to: fan)
                if try hardware.readMode(of: fan) == .manual {
                    return
                }
                lastError = TurboReadbackError.mode
            } catch {
                lastError = error
            }
            if attempt + 1 < policy.manualModeRetryCount {
                try await clock.sleep(for: policy.manualModeRetryDelay)
            }
        }
        throw lastError
    }

    private func verifyActualRPMRise(_ fans: [TurboFanDescriptor], ownerID: UUID) async throws {
        var latestSamples: [TurboFanDiagnosticSample] = []
        for attempt in 0..<policy.actualReadbackAttemptCount {
            try ensureLeaseIsOwned(by: ownerID)
            var allVerified = true
            latestSamples.removeAll(keepingCapacity: true)
            for fan in fans {
                try await reconcileMaximumControl(
                    for: fan,
                    ownerID: ownerID,
                    retryCount: policy.activeReconciliationRetryCount,
                    retryDelay: policy.activeReconciliationRetryDelay
                )
                let actual: Double
                do {
                    actual = try hardware.readActualRPM(of: fan)
                } catch {
                    latestSamples.append(Self.diagnosticSample(for: fan, actualRPM: nil))
                    diagnosticSink.record(.actualRPMReadbackFailed(samples: latestSamples))
                    throw TurboReadbackError.actualRPM
                }
                latestSamples.append(Self.diagnosticSample(for: fan, actualRPM: actual))
                let isVerified = policy.isActualRPMPlausible(
                    actual,
                    maximumRPM: fan.maximumRPM
                )
                    && (actual >= fan.baselineActualRPM + policy.minimumActualRiseRPM
                        || actual >= fan.maximumRPM * policy.alreadyAtMaximumFraction)
                if !isVerified {
                    allVerified = false
                }
            }
            if allVerified {
                diagnosticSink.record(.actualRPMRiseVerified(samples: latestSamples))
                return
            }
            if attempt + 1 < policy.actualReadbackAttemptCount {
                try await clock.sleep(for: policy.actualReadbackDelay)
            }
        }
        diagnosticSink.record(.actualRPMReadbackFailed(samples: latestSamples))
        throw TurboReadbackError.actualRPM
    }

    private func reconcileActiveTurbo(_ lease: TurboLease) async throws {
        guard let ownerID else { throw TurboReadbackError.mode }
        if lease.claimedThermalManagerUnlock {
            guard try hardware.readThermalManagerUnlock() == true else {
                throw TurboReadbackError.mode
            }
        }

        let fans = try hardware.discoverFans()
        guard Self.hasValidDynamicFanSet(fans),
              fans.count == lease.touchedFans.count
        else {
            throw TurboFanHardwareError.invalidData
        }
        let persistedFans = Dictionary(uniqueKeysWithValues: lease.touchedFans.map { ($0.index, $0) })
        guard fans.allSatisfy({ fan in
            persistedFans[fan.index]?.modeKey == fan.modeKey
        }) else {
            throw TurboFanHardwareError.invalidData
        }

        for fan in fans.sorted(by: { $0.index < $1.index }) {
            try await reconcileMaximumControl(
                for: fan,
                ownerID: ownerID,
                retryCount: policy.activeReconciliationRetryCount,
                retryDelay: policy.activeReconciliationRetryDelay
            )
            let actual = try hardware.readActualRPM(of: fan)
            guard policy.isActualRPMPlausible(actual, maximumRPM: fan.maximumRPM) else {
                throw TurboReadbackError.actualRPM
            }
        }
    }

    private func reconcileMaximumControl(
        for fan: TurboFanDescriptor,
        ownerID: UUID,
        retryCount: Int,
        retryDelay: TimeInterval
    ) async throws {
        var lastError: Error = TurboReadbackError.mode
        for attempt in 0..<max(1, retryCount) {
            try ensureLeaseIsOwned(by: ownerID)
            do {
                let mode = try hardware.readMode(of: fan)
                if mode != .manual {
                    try hardware.writeManualMode(to: fan)
                    guard try hardware.readMode(of: fan) == .manual else {
                        throw TurboReadbackError.mode
                    }
                }

                var target = try hardware.readTargetRPM(of: fan)
                if !target.isFinite
                    || abs(target - fan.maximumRPM) > policy.maximumTargetToleranceRPM
                {
                    try hardware.writeMaximumTarget(to: fan)
                    target = try hardware.readTargetRPM(of: fan)
                }
                guard target.isFinite,
                      abs(target - fan.maximumRPM) <= policy.maximumTargetToleranceRPM
                else {
                    throw TurboReadbackError.target
                }
                return
            } catch let error as TurboFanHardwareError where error == .thermalManagerBusy {
                lastError = TurboReadbackError.mode
            } catch {
                lastError = error
            }

            if attempt + 1 < max(1, retryCount) {
                try await clock.sleep(for: retryDelay)
            }
        }

        switch lastError as? TurboReadbackError {
        case .mode:
            diagnosticSink.record(.modeReadbackMismatch(fanIndex: fan.index, observed: nil))
        case .target:
            let target = try? hardware.readTargetRPM(of: fan)
            diagnosticSink.record(
                .targetReadbackMismatch(
                    fanIndex: fan.index,
                    expectedRPM: fan.maximumRPM,
                    observedRPM: target
                )
            )
        case .actualRPM, nil:
            break
        }
        throw lastError
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
                    diagnosticSink.record(
                        .restorationFailed(stage: .fanMode, fanIndex: leaseFan.index)
                    )
                    throw TurboFanHardwareError.invalidData
                }
                let fan = Self.recoveryDescriptor(for: leaseFan)
                do {
                    try await retryAutomaticMode(for: fan)
                } catch {
                    diagnosticSink.record(
                        .restorationFailed(stage: .fanMode, fanIndex: fan.index)
                    )
                    throw error
                }
            }

            for leaseFan in lease.touchedFans {
                let fan = Self.recoveryDescriptor(for: leaseFan)
                do {
                    guard try hardware.readMode(of: fan).isAppleManaged else {
                        throw TurboReadbackError.mode
                    }
                } catch {
                    diagnosticSink.record(
                        .restorationFailed(stage: .fanMode, fanIndex: fan.index)
                    )
                    throw error
                }
                do {
                    let actual = try hardware.readActualRPM(of: fan)
                    guard actual.isFinite, actual >= 0 else {
                        throw TurboReadbackError.actualRPM
                    }
                } catch {
                    diagnosticSink.record(
                        .restorationFailed(stage: .actualRPM, fanIndex: fan.index)
                    )
                    throw error
                }
            }

            if lease.claimedThermalManagerUnlock {
                do {
                    // AppleSMC can apply Ftst asynchronously. Always enqueue the
                    // release after our persisted claim, then wait before readback.
                    try hardware.writeThermalManagerUnlock(false)
                    try await clock.sleep(for: policy.unlockSettleDelay)
                    guard try hardware.readThermalManagerUnlock() == false else {
                        throw TurboReadbackError.mode
                    }
                } catch {
                    diagnosticSink.record(
                        .restorationFailed(stage: .thermalManagerUnlock, fanIndex: nil)
                    )
                    throw error
                }
            }

            do {
                try leaseStore.remove()
            } catch {
                diagnosticSink.record(
                    .restorationFailed(stage: .leaseRemoval, fanIndex: nil)
                )
                throw error
            }
            self.lease = nil
            ownerID = nil
            monotonicDeadline = nil
            status = issueAfterConfirmedRestore.map {
                TurboStatus(phase: .failedSafeAuto, issue: $0)
            } ?? .inactive()
            diagnosticSink.record(.restorationCompleted(issue: issueAfterConfirmedRestore))
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
                if try hardware.readMode(of: fan).isAppleManaged {
                    return
                }
                try hardware.writeAutomaticMode(to: fan)
                if try hardware.readMode(of: fan).isAppleManaged {
                    return
                }
                lastError = TurboReadbackError.mode
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

    private static func diagnosticSample(
        for fan: TurboFanDescriptor,
        actualRPM: Double?
    ) -> TurboFanDiagnosticSample {
        TurboFanDiagnosticSample(
            fanIndex: fan.index,
            baselineRPM: fan.baselineActualRPM,
            maximumRPM: fan.maximumRPM,
            actualRPM: actualRPM
        )
    }
}

private enum TurboReadbackError: Error {
    case mode
    case target
    case actualRPM
}
