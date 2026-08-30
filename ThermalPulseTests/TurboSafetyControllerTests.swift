import Foundation
import XCTest
@testable import ThermalPulseCore

final class TurboSafetyControllerTests: XCTestCase {
    private let owner = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testStartPersistsOwnershipBeforeEveryWriteAndUsesAllDynamicFans() async {
        let recorder = TurboEventRecorder()
        let hardware = TurboFanHardwareSpy(recorder: recorder)
        let store = TurboLeaseStoreSpy(recorder: recorder)
        let clock = TurboClockSpy(now: Date(timeIntervalSince1970: 10_000))
        let controller = makeController(hardware: hardware, store: store, clock: clock)

        let first = await controller.startTurbo(ownerID: owner)
        let second = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(first.phase, .active)
        XCTAssertEqual(first.startedAt, Date(timeIntervalSince1970: 10_000))
        XCTAssertEqual(first.deadline, Date(timeIntervalSince1970: 10_600))
        XCTAssertEqual(second, first)
        XCTAssertEqual(hardware.manualWrites, [0, 1])
        XCTAssertEqual(hardware.maximumTargetWrites, [0, 1])
        XCTAssertEqual(store.saveCount, 3)
        XCTAssertEqual(
            recorder.events,
            [
                "save:0:false",
                "save:1:false",
                "manual:0",
                "target:0",
                "save:2:false",
                "manual:1",
                "target:1",
            ]
        )
    }

    func testExternalManualModeRefusesWithoutWritingOrTakingLease() async {
        let hardware = TurboFanHardwareSpy()
        hardware.modes[1] = .manual
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(status, .inactive(issue: .externalControllerDetected))
        XCTAssertTrue(hardware.manualWrites.isEmpty)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testSystemManagedFanModeCanProceedWithoutBeingMisclassifiedAsExternalControl() async {
        let hardware = TurboFanHardwareSpy()
        hardware.modes[1] = .system
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(status.phase, .active)
        XCTAssertEqual(hardware.manualWrites, [0, 1])
        XCTAssertEqual(store.saveCount, 4)
        XCTAssertEqual(hardware.unlockWrites, [true])
    }

    func testUnsupportedThermalManagerRefusesSystemModeWithoutWriting() async {
        let hardware = TurboFanHardwareSpy()
        hardware.modes[0] = .system
        hardware.unlockState = nil
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(status, .inactive(issue: .unsupportedHardware))
        XCTAssertTrue(hardware.manualWrites.isEmpty)
        XCTAssertTrue(hardware.unlockWrites.isEmpty)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testUnsupportedThermalManagerNeverWritesUnknownUnlockAfterBusyMode() async {
        let hardware = TurboFanHardwareSpy()
        hardware.unlockState = nil
        hardware.manualFailuresRemaining[0] = 1
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(
            status,
            TurboStatus(phase: .failedSafeAuto, issue: .smcWriteFailed)
        )
        XCTAssertTrue(hardware.unlockWrites.isEmpty)
        XCTAssertNil(store.persistedLease)
    }

    func testAppleSiliconModeValuesRejectUnknownRawStates() {
        XCTAssertEqual(TurboFanMode(appleSiliconSMCRawValue: 0), .automatic)
        XCTAssertEqual(TurboFanMode(appleSiliconSMCRawValue: 1), .manual)
        XCTAssertEqual(TurboFanMode(appleSiliconSMCRawValue: 3), .system)
        XCTAssertNil(TurboFanMode(appleSiliconSMCRawValue: 2))
        XCTAssertNil(TurboFanMode(appleSiliconSMCRawValue: 255))
        XCTAssertTrue(TurboFanMode.automatic.isAppleManaged)
        XCTAssertTrue(TurboFanMode.system.isAppleManaged)
        XCTAssertFalse(TurboFanMode.manual.isAppleManaged)
    }

    func testUnlockClaimIsPersistedBeforeThermalManagerIsReleased() async {
        let recorder = TurboEventRecorder()
        let hardware = TurboFanHardwareSpy(recorder: recorder)
        hardware.manualFailuresRemaining[0] = 1
        let store = TurboLeaseStoreSpy(recorder: recorder)
        let controller = makeController(hardware: hardware, store: store)

        let active = await controller.startTurbo(ownerID: owner)
        let stopped = await controller.stopTurbo()

        XCTAssertEqual(active.phase, .active)
        XCTAssertEqual(stopped, .inactive())
        let events = recorder.events
        XCTAssertLessThan(
            try XCTUnwrap(events.firstIndex(of: "save:1:true")),
            try XCTUnwrap(events.firstIndex(of: "unlock:true"))
        )
        XCTAssertTrue(events.contains("unlock:false"))
        XCTAssertFalse(hardware.unlockState ?? true)
    }

    func testThermalManagerClaimPollsUntilStableThenReleaseKeepsSettledReadback() async throws {
        let recorder = TurboEventRecorder()
        let hardware = TurboFanHardwareSpy(recorder: recorder)
        hardware.modes[0] = .system
        hardware.recordUnlockReads = true
        hardware.unlockReadSequence = [false, false, true, true]
        let store = TurboLeaseStoreSpy(recorder: recorder)
        let clock = TurboClockSpy(
            now: Date(timeIntervalSince1970: 10_000),
            recorder: recorder
        )
        let controller = TurboSafetyController(
            hardware: hardware,
            leaseStore: store,
            clock: clock,
            policy: TurboSafetyPolicy(
                unlockSettleDelay: 3,
                unlockClaimPollInterval: 0.1,
                unlockClaimStableReadCount: 2,
                manualModeRetryCount: 3,
                manualModeRetryDelay: 0,
                activeReconciliationRetryCount: 2,
                activeReconciliationRetryDelay: 0,
                restoreRetryCount: 2,
                restoreRetryDelay: 0,
                actualReadbackAttemptCount: 2,
                actualReadbackDelay: 0
            )
        )

        let active = await controller.startTurbo(ownerID: owner)
        let stopped = await controller.stopTurbo()

        XCTAssertEqual(active.phase, .active)
        XCTAssertEqual(stopped, .inactive())
        let events = recorder.events
        let claimWrite = try XCTUnwrap(events.firstIndex(of: "unlock:true"))
        let firstUnclaimedRead = try XCTUnwrap(
            events.indices.first { $0 > claimWrite && events[$0] == "read-unlock:false" }
        )
        let firstPoll = try XCTUnwrap(events.firstIndex(of: "sleep:0.1"))
        let claimedReads = events.indices.filter { events[$0] == "read-unlock:true" }
        XCTAssertEqual(claimedReads.count, 2)
        XCTAssertLessThan(claimWrite, firstUnclaimedRead)
        XCTAssertLessThan(firstUnclaimedRead, firstPoll)
        XCTAssertLessThan(firstPoll, claimedReads[0])
        XCTAssertEqual(events.filter { $0 == "sleep:0.1" }.count, 2)

        let releaseWrite = try XCTUnwrap(events.lastIndex(of: "unlock:false"))
        let releaseSleep = try XCTUnwrap(events.lastIndex(of: "sleep:3.0"))
        let releasedRead = try XCTUnwrap(events.lastIndex(of: "read-unlock:false"))
        XCTAssertLessThan(releaseWrite, releaseSleep)
        XCTAssertLessThan(releaseSleep, releasedRead)
    }

    func testThermalManagerClaimPollingTimesOutAndRestoresWithoutTouchingFans() async {
        let recorder = TurboEventRecorder()
        let hardware = TurboFanHardwareSpy(recorder: recorder)
        hardware.modes[0] = .system
        hardware.recordUnlockReads = true
        hardware.unlockReadSequence = [false, false, false, false, false]
        let store = TurboLeaseStoreSpy(recorder: recorder)
        let clock = TurboClockSpy(
            now: Date(timeIntervalSince1970: 10_000),
            recorder: recorder
        )
        let controller = TurboSafetyController(
            hardware: hardware,
            leaseStore: store,
            clock: clock,
            policy: TurboSafetyPolicy(
                unlockSettleDelay: 0.25,
                unlockClaimPollInterval: 0.1,
                unlockClaimStableReadCount: 2,
                manualModeRetryCount: 3,
                manualModeRetryDelay: 0,
                activeReconciliationRetryCount: 2,
                activeReconciliationRetryDelay: 0,
                restoreRetryCount: 2,
                restoreRetryDelay: 0,
                actualReadbackAttemptCount: 2,
                actualReadbackDelay: 0
            )
        )

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(
            status,
            TurboStatus(phase: .failedSafeAuto, issue: .modeReadbackMismatch)
        )
        XCTAssertTrue(hardware.manualWrites.isEmpty)
        XCTAssertEqual(hardware.unlockWrites, [true, false])
        XCTAssertNil(store.persistedLease)
        XCTAssertEqual(
            recorder.events.filter { $0.hasPrefix("read-unlock:") }.count,
            6
        )
    }

    func testPartialActivationFailureRestoresTouchedFansAndDoesNotClaimSuccess() async {
        let hardware = TurboFanHardwareSpy()
        hardware.targetWriteFailureIndex = 1
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(status, TurboStatus(phase: .failedSafeAuto, issue: .smcWriteFailed))
        XCTAssertEqual(hardware.modes[0], .automatic)
        XCTAssertEqual(hardware.modes[1], .automatic)
        XCTAssertEqual(hardware.automaticWrites, [1, 0])
        XCTAssertNil(store.persistedLease)
    }

    func testActualRPMMustRiseBeforeActiveIsReported() async {
        let hardware = TurboFanHardwareSpy()
        hardware.actualSequences = [
            0: [1_000, 1_020, 1_040],
            1: [1_100, 1_120, 1_140],
        ]
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(status, TurboStatus(phase: .failedSafeAuto, issue: .actualRPMReadbackMismatch))
        XCTAssertEqual(hardware.modes.values.filter { $0 == .manual }.count, 0)
        XCTAssertNil(store.persistedLease)
    }

    func testActualRPMPolicyAllowsSmallOvershootButRejectsImplausibleReadback() {
        let policy = TurboSafetyPolicy(maximumActualOvershootFraction: 0.05)

        XCTAssertTrue(policy.isActualRPMPlausible(5_854.90, maximumRPM: 5_777))
        XCTAssertTrue(policy.isActualRPMPlausible(5_777, maximumRPM: 5_777))
        XCTAssertFalse(policy.isActualRPMPlausible(6_100, maximumRPM: 5_777))
        XCTAssertFalse(policy.isActualRPMPlausible(.nan, maximumRPM: 5_777))
        XCTAssertFalse(policy.isActualRPMPlausible(1_000, maximumRPM: 0))
    }

    func testActiveWatchdogAllowsSmallOvershootButRestoresOnImplausibleActualRPM() async {
        let hardware = TurboFanHardwareSpy()
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let active = await controller.startTurbo(ownerID: owner)
        hardware.actualSequences = [0: [5_800], 1: [5_900]]
        let tolerated = await controller.watchdogTick()
        hardware.actualSequences = [0: [6_100], 1: [5_900]]
        let rejected = await controller.watchdogTick()

        XCTAssertEqual(active.phase, .active)
        XCTAssertEqual(tolerated.phase, .active)
        XCTAssertEqual(
            rejected,
            TurboStatus(phase: .failedSafeAuto, issue: .actualRPMReadbackMismatch)
        )
        XCTAssertEqual(hardware.modes.values.filter { $0 == .manual }.count, 0)
        XCTAssertNil(store.persistedLease)
    }

    func testModeTargetAndActualReadbackFailuresRemainDistinct() async {
        let modeHardware = TurboFanHardwareSpy()
        modeHardware.manualModeDoesNotStickIndex = 0
        let modeController = makeController(
            hardware: modeHardware,
            store: TurboLeaseStoreSpy()
        )
        let modeStatus = await modeController.startTurbo(ownerID: owner)
        XCTAssertEqual(modeStatus.issue, .modeReadbackMismatch)

        let targetHardware = TurboFanHardwareSpy()
        targetHardware.targetWriteDoesNotStickIndex = 1
        let targetController = makeController(
            hardware: targetHardware,
            store: TurboLeaseStoreSpy()
        )
        let targetStatus = await targetController.startTurbo(ownerID: owner)
        XCTAssertEqual(targetStatus.issue, .targetReadbackMismatch)

        let actualHardware = TurboFanHardwareSpy()
        actualHardware.actualSequences = [0: [1_000], 1: [1_100]]
        let actualController = makeController(
            hardware: actualHardware,
            store: TurboLeaseStoreSpy()
        )
        let actualStatus = await actualController.startTurbo(ownerID: owner)
        XCTAssertEqual(actualStatus.issue, .actualRPMReadbackMismatch)
    }

    func testActualReadbackDiagnosticContainsEveryDynamicFan() async {
        let hardware = TurboFanHardwareSpy()
        hardware.actualSequences = [0: [1_020], 1: [1_130]]
        let diagnostics = TurboDiagnosticRecorder()
        let controller = makeController(
            hardware: hardware,
            store: TurboLeaseStoreSpy(),
            diagnostics: diagnostics
        )

        _ = await controller.startTurbo(ownerID: owner)

        let failedSamples = try? XCTUnwrap(
            diagnostics.events.compactMap { event -> [TurboFanDiagnosticSample]? in
                guard case let .actualRPMReadbackFailed(samples) = event else { return nil }
                return samples
            }.last
        )
        XCTAssertEqual(failedSamples?.map(\.fanIndex), [0, 1])
        XCTAssertEqual(failedSamples?.map(\.actualRPM), [1_020, 1_130])
    }

    func testDeadlineDisconnectAndWakeEachRestoreAutomaticMode() async {
        let deadlineHardware = TurboFanHardwareSpy()
        let deadlineStore = TurboLeaseStoreSpy()
        let deadlineClock = TurboClockSpy(now: Date(timeIntervalSince1970: 20_000))
        let deadlineController = makeController(
            hardware: deadlineHardware,
            store: deadlineStore,
            clock: deadlineClock
        )
        _ = await deadlineController.startTurbo(ownerID: owner)
        deadlineClock.advance(by: 600)
        let expired = await deadlineController.watchdogTick()
        XCTAssertEqual(expired, .inactive())

        let disconnectHardware = TurboFanHardwareSpy()
        let disconnectController = makeController(
            hardware: disconnectHardware,
            store: TurboLeaseStoreSpy()
        )
        _ = await disconnectController.startTurbo(ownerID: owner)
        let unrelated = await disconnectController.connectionInvalidated(ownerID: UUID())
        XCTAssertEqual(unrelated.phase, .active)
        let disconnected = await disconnectController.connectionInvalidated(ownerID: owner)
        XCTAssertEqual(disconnected, .inactive())

        let wakeHardware = TurboFanHardwareSpy()
        let wakeController = makeController(hardware: wakeHardware, store: TurboLeaseStoreSpy())
        _ = await wakeController.startTurbo(ownerID: owner)
        let woke = await wakeController.systemDidWake()
        XCTAssertEqual(woke, .inactive())
    }

    func testActiveWatchdogReassertsMaximumAfterSystemReclaimsModeAndTarget() async {
        let hardware = TurboFanHardwareSpy()
        let controller = makeController(
            hardware: hardware,
            store: TurboLeaseStoreSpy()
        )
        let active = await controller.startTurbo(ownerID: owner)
        hardware.modes[0] = .system
        hardware.targets[0] = 0

        let reconciled = await controller.watchdogTick()

        XCTAssertEqual(active.phase, .active)
        XCTAssertEqual(reconciled.phase, .active)
        XCTAssertEqual(hardware.modes[0], .manual)
        XCTAssertEqual(hardware.targets[0], hardware.fans[0].maximumRPM)
        XCTAssertEqual(hardware.manualWrites.filter { $0 == 0 }.count, 2)
        XCTAssertEqual(hardware.maximumTargetWrites.filter { $0 == 0 }.count, 2)
    }

    func testActiveWatchdogRestoresWhenClaimedThermalManagerUnlockIsLost() async {
        let hardware = TurboFanHardwareSpy()
        hardware.modes = [0: .system, 1: .system]
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)
        let active = await controller.startTurbo(ownerID: owner)
        hardware.unlockState = false

        let status = await controller.watchdogTick()

        XCTAssertEqual(active.phase, .active)
        XCTAssertEqual(status, TurboStatus(phase: .failedSafeAuto, issue: .modeReadbackMismatch))
        XCTAssertEqual(hardware.modes[0], .automatic)
        XCTAssertEqual(hardware.modes[1], .automatic)
        XCTAssertNil(store.persistedLease)
    }

    func testMonotonicDeadlineStillExpiresAfterWallClockMovesBackward() async {
        let hardware = TurboFanHardwareSpy()
        let clock = TurboClockSpy(now: Date(timeIntervalSince1970: 40_000))
        let controller = makeController(
            hardware: hardware,
            store: TurboLeaseStoreSpy(),
            clock: clock
        )
        _ = await controller.startTurbo(ownerID: owner)

        clock.moveWallClock(by: -3_600)
        clock.advanceMonotonic(by: 600)
        let status = await controller.watchdogTick()

        XCTAssertEqual(status, .inactive())
        XCTAssertEqual(hardware.modes.values.filter { $0 == .manual }.count, 0)
    }

    func testHelperRestartRestoresOnlyPersistedThermalPulseFans() async {
        let persisted = TurboLease(
            startedAt: Date(timeIntervalSince1970: 30_000),
            deadline: Date(timeIntervalSince1970: 30_600),
            touchedFans: [TurboLeaseFan(index: 1, modeKey: "F1Md")],
            claimedThermalManagerUnlock: true
        )
        let hardware = TurboFanHardwareSpy()
        hardware.modes[1] = .manual
        hardware.unlockState = true
        let store = TurboLeaseStoreSpy(initialLease: persisted)
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.bootstrap()

        XCTAssertEqual(status, .inactive())
        XCTAssertEqual(hardware.automaticWrites, [1])
        XCTAssertEqual(hardware.modes[0], .automatic)
        XCTAssertFalse(hardware.unlockState ?? true)
        XCTAssertNil(store.persistedLease)
    }

    func testRestoreAcceptsThermalManagerReclaimingSystemMode() async {
        let hardware = TurboFanHardwareSpy()
        hardware.automaticModeAfterWrite = .system
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let active = await controller.startTurbo(ownerID: owner)
        let stopped = await controller.stopTurbo()

        XCTAssertEqual(active.phase, .active)
        XCTAssertEqual(stopped, .inactive())
        XCTAssertEqual(hardware.modes[0], .system)
        XCTAssertEqual(hardware.modes[1], .system)
        XCTAssertNil(store.persistedLease)
    }

    func testRestartReassertsThermalManagerReleaseBeforeClearingLease() async {
        let persisted = TurboLease(
            startedAt: Date(timeIntervalSince1970: 30_000),
            deadline: Date(timeIntervalSince1970: 30_600),
            touchedFans: [
                TurboLeaseFan(index: 0, modeKey: "F0Md"),
                TurboLeaseFan(index: 1, modeKey: "F1Md"),
            ],
            claimedThermalManagerUnlock: true
        )
        let hardware = TurboFanHardwareSpy()
        hardware.modes = [0: .system, 1: .system]
        hardware.unlockState = false
        let store = TurboLeaseStoreSpy(initialLease: persisted)
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.bootstrap()

        XCTAssertEqual(status, .inactive())
        XCTAssertTrue(hardware.automaticWrites.isEmpty)
        XCTAssertEqual(hardware.unlockWrites, [false])
        XCTAssertNil(store.persistedLease)
    }

    func testRecoveryFailureKeepsLeaseForWatchdogRetry() async {
        let hardware = TurboFanHardwareSpy()
        hardware.automaticWriteAlwaysFails = true
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        _ = await controller.startTurbo(ownerID: owner)
        let failed = await controller.stopTurbo()

        XCTAssertEqual(failed.phase, .failedSafeAuto)
        XCTAssertEqual(failed.issue, .recoveryFailed)
        XCTAssertNotNil(store.persistedLease)
        XCTAssertEqual(store.removeCount, 0)

        hardware.automaticWriteAlwaysFails = false
        let recovered = await controller.watchdogTick()

        XCTAssertEqual(recovered, .inactive())
        XCTAssertNil(store.persistedLease)
        XCTAssertEqual(store.removeCount, 1)
        XCTAssertTrue(hardware.modes.values.allSatisfy(\.isAppleManaged))
    }

    func testLeasePersistenceFailurePreventsAllSMCWrites() async {
        let hardware = TurboFanHardwareSpy()
        let store = TurboLeaseStoreSpy()
        store.saveAlwaysFails = true
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(status.phase, .failedSafeAuto)
        XCTAssertEqual(status.issue, .recoveryFailed)
        XCTAssertTrue(hardware.manualWrites.isEmpty)
        XCTAssertTrue(hardware.maximumTargetWrites.isEmpty)
    }

    private func makeController(
        hardware: TurboFanHardwareSpy,
        store: TurboLeaseStoreSpy,
        clock: TurboClockSpy = TurboClockSpy(now: Date(timeIntervalSince1970: 1_000)),
        diagnostics: any TurboDiagnosticSink = NoOpTurboDiagnosticSink()
    ) -> TurboSafetyController {
        TurboSafetyController(
            hardware: hardware,
            leaseStore: store,
            clock: clock,
            policy: TurboSafetyPolicy(
                unlockSettleDelay: 0,
                unlockClaimStableReadCount: 1,
                manualModeRetryCount: 3,
                manualModeRetryDelay: 0,
                activeReconciliationRetryCount: 2,
                activeReconciliationRetryDelay: 0,
                restoreRetryCount: 2,
                restoreRetryDelay: 0,
                actualReadbackAttemptCount: 2,
                actualReadbackDelay: 0,
                minimumActualRiseRPM: 100,
                maximumTargetToleranceRPM: 1,
                alreadyAtMaximumFraction: 0.9
            ),
            diagnosticSink: diagnostics
        )
    }
}

private final class TurboDiagnosticRecorder: TurboDiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TurboDiagnosticEvent] = []

    var events: [TurboDiagnosticEvent] { lock.withLock { storage } }

    func record(_ event: TurboDiagnosticEvent) {
        lock.withLock { storage.append(event) }
    }
}

private final class TurboEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] { lock.withLock { storage } }

    func append(_ event: String) {
        lock.withLock { storage.append(event) }
    }
}

private final class TurboLeaseStoreSpy: TurboLeaseStore, @unchecked Sendable {
    private let lock = NSLock()
    private let recorder: TurboEventRecorder?
    private var lease: TurboLease?
    private(set) var saveCount = 0
    private(set) var removeCount = 0
    var saveAlwaysFails = false

    var persistedLease: TurboLease? { lock.withLock { lease } }

    init(initialLease: TurboLease? = nil, recorder: TurboEventRecorder? = nil) {
        lease = initialLease
        self.recorder = recorder
    }

    func load() throws -> TurboLease? {
        lock.withLock { lease }
    }

    func save(_ lease: TurboLease) throws {
        try lock.withLock {
            if saveAlwaysFails { throw TurboFanHardwareError.writeFailed }
            self.lease = lease
            saveCount += 1
            recorder?.append("save:\(lease.touchedFans.count):\(lease.claimedThermalManagerUnlock)")
        }
    }

    func remove() throws {
        lock.withLock {
            lease = nil
            removeCount += 1
        }
    }
}

private final class TurboClockSpy: TurboSafetyClock, @unchecked Sendable {
    private let lock = NSLock()
    private let recorder: TurboEventRecorder?
    private var current: Date
    private var monotonic: TimeInterval = 1_000

    init(now: Date, recorder: TurboEventRecorder? = nil) {
        current = now
        self.recorder = recorder
    }

    func now() -> Date {
        lock.withLock { current }
    }

    func monotonicNow() -> TimeInterval {
        lock.withLock { monotonic }
    }

    func sleep(for duration: TimeInterval) async throws {
        recorder?.append("sleep:\(duration)")
        advance(by: duration)
    }

    func advance(by duration: TimeInterval) {
        lock.withLock {
            current = current.addingTimeInterval(duration)
            monotonic += duration
        }
    }

    func moveWallClock(by duration: TimeInterval) {
        lock.withLock {
            current = current.addingTimeInterval(duration)
        }
    }

    func advanceMonotonic(by duration: TimeInterval) {
        lock.withLock {
            monotonic += duration
        }
    }
}

private final class TurboFanHardwareSpy: TurboFanHardware, @unchecked Sendable {
    private let lock = NSLock()
    private let recorder: TurboEventRecorder?

    var fans = [
        TurboFanDescriptor(index: 0, modeKey: "F0Md", maximumRPM: 5_700, baselineActualRPM: 1_000),
        TurboFanDescriptor(index: 1, modeKey: "F1Md", maximumRPM: 5_800, baselineActualRPM: 1_100),
    ]
    var modes: [Int: TurboFanMode] = [0: .automatic, 1: .automatic]
    var targets: [Int: Double] = [:]
    var actualSequences: [Int: [Double]] = [0: [5_200], 1: [5_300]]
    var manualFailuresRemaining: [Int: Int] = [:]
    var targetWriteFailureIndex: Int?
    var manualModeDoesNotStickIndex: Int?
    var targetWriteDoesNotStickIndex: Int?
    var automaticWriteAlwaysFails = false
    var automaticModeAfterWrite: TurboFanMode = .automatic
    var unlockState: Bool? = false
    var unlockReadSequence: [Bool?] = []
    var recordUnlockReads = false
    private(set) var manualWrites: [Int] = []
    private(set) var automaticWrites: [Int] = []
    private(set) var maximumTargetWrites: [Int] = []
    private(set) var unlockWrites: [Bool] = []

    init(recorder: TurboEventRecorder? = nil) {
        self.recorder = recorder
    }

    func discoverFans() throws -> [TurboFanDescriptor] {
        lock.withLock { fans }
    }

    func readMode(of fan: TurboFanDescriptor) throws -> TurboFanMode {
        lock.withLock { modes[fan.index] ?? .automatic }
    }

    func writeManualMode(to fan: TurboFanDescriptor) throws {
        try lock.withLock {
            recorder?.append("manual:\(fan.index)")
            manualWrites.append(fan.index)
            if (manualFailuresRemaining[fan.index] ?? 0) > 0 {
                manualFailuresRemaining[fan.index, default: 0] -= 1
                throw TurboFanHardwareError.thermalManagerBusy
            }
            if manualModeDoesNotStickIndex != fan.index {
                modes[fan.index] = .manual
            }
        }
    }

    func writeAutomaticMode(to fan: TurboFanDescriptor) throws {
        try lock.withLock {
            recorder?.append("automatic:\(fan.index)")
            automaticWrites.append(fan.index)
            if automaticWriteAlwaysFails {
                throw TurboFanHardwareError.writeFailed
            }
            modes[fan.index] = automaticModeAfterWrite
        }
    }

    func writeMaximumTarget(to fan: TurboFanDescriptor) throws {
        try lock.withLock {
            recorder?.append("target:\(fan.index)")
            maximumTargetWrites.append(fan.index)
            if targetWriteFailureIndex == fan.index {
                throw TurboFanHardwareError.writeFailed
            }
            if targetWriteDoesNotStickIndex != fan.index {
                targets[fan.index] = fan.maximumRPM
            }
        }
    }

    func readTargetRPM(of fan: TurboFanDescriptor) throws -> Double {
        lock.withLock { targets[fan.index] ?? 0 }
    }

    func readActualRPM(of fan: TurboFanDescriptor) throws -> Double {
        lock.withLock {
            guard var values = actualSequences[fan.index], let first = values.first else { return 0 }
            if values.count > 1 {
                values.removeFirst()
                actualSequences[fan.index] = values
            }
            return first
        }
    }

    func readThermalManagerUnlock() throws -> Bool? {
        lock.withLock {
            let result: Bool?
            if !unlockReadSequence.isEmpty {
                result = unlockReadSequence.removeFirst()
            } else {
                result = unlockState
            }
            if recordUnlockReads {
                let value = result.map(String.init) ?? "nil"
                recorder?.append("read-unlock:\(value)")
            }
            return result
        }
    }

    func writeThermalManagerUnlock(_ enabled: Bool) throws {
        lock.withLock {
            recorder?.append("unlock:\(enabled)")
            unlockWrites.append(enabled)
            unlockState = enabled
        }
    }
}
