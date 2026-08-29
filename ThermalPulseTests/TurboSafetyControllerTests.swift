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

    func testUnknownFanModeRefusesWithoutWritingOrTakingLease() async {
        let hardware = TurboFanHardwareSpy()
        hardware.modes[1] = .system
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        let status = await controller.startTurbo(ownerID: owner)

        XCTAssertEqual(status, .inactive(issue: .externalControllerDetected))
        XCTAssertTrue(hardware.manualWrites.isEmpty)
        XCTAssertEqual(store.saveCount, 0)
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

        XCTAssertEqual(status, TurboStatus(phase: .failedSafeAuto, issue: .readbackMismatch))
        XCTAssertEqual(hardware.modes.values.filter { $0 == .manual }.count, 0)
        XCTAssertNil(store.persistedLease)
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

    func testRecoveryFailureKeepsLeaseForWatchdogRetry() async {
        let hardware = TurboFanHardwareSpy()
        hardware.automaticWriteAlwaysFails = true
        let store = TurboLeaseStoreSpy()
        let controller = makeController(hardware: hardware, store: store)

        _ = await controller.startTurbo(ownerID: owner)
        let status = await controller.stopTurbo()

        XCTAssertEqual(status.phase, .failedSafeAuto)
        XCTAssertEqual(status.issue, .recoveryFailed)
        XCTAssertNotNil(store.persistedLease)
        XCTAssertEqual(store.removeCount, 0)
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
        clock: TurboClockSpy = TurboClockSpy(now: Date(timeIntervalSince1970: 1_000))
    ) -> TurboSafetyController {
        TurboSafetyController(
            hardware: hardware,
            leaseStore: store,
            clock: clock,
            policy: TurboSafetyPolicy(
                unlockSettleDelay: 0,
                manualModeRetryCount: 3,
                manualModeRetryDelay: 0,
                restoreRetryCount: 2,
                restoreRetryDelay: 0,
                actualReadbackAttemptCount: 2,
                actualReadbackDelay: 0,
                minimumActualRiseRPM: 100,
                maximumTargetToleranceRPM: 1,
                alreadyAtMaximumFraction: 0.9
            )
        )
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
    private var current: Date
    private var monotonic: TimeInterval = 1_000

    init(now: Date) {
        current = now
    }

    func now() -> Date {
        lock.withLock { current }
    }

    func monotonicNow() -> TimeInterval {
        lock.withLock { monotonic }
    }

    func sleep(for duration: TimeInterval) async throws {
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
    var automaticWriteAlwaysFails = false
    var unlockState: Bool? = false
    private(set) var manualWrites: [Int] = []
    private(set) var automaticWrites: [Int] = []
    private(set) var maximumTargetWrites: [Int] = []

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
            modes[fan.index] = .manual
        }
    }

    func writeAutomaticMode(to fan: TurboFanDescriptor) throws {
        try lock.withLock {
            recorder?.append("automatic:\(fan.index)")
            automaticWrites.append(fan.index)
            if automaticWriteAlwaysFails {
                throw TurboFanHardwareError.writeFailed
            }
            modes[fan.index] = .automatic
        }
    }

    func writeMaximumTarget(to fan: TurboFanDescriptor) throws {
        try lock.withLock {
            recorder?.append("target:\(fan.index)")
            maximumTargetWrites.append(fan.index)
            if targetWriteFailureIndex == fan.index {
                throw TurboFanHardwareError.writeFailed
            }
            targets[fan.index] = fan.maximumRPM
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
        lock.withLock { unlockState }
    }

    func writeThermalManagerUnlock(_ enabled: Bool) throws {
        lock.withLock {
            recorder?.append("unlock:\(enabled)")
            unlockState = enabled
        }
    }
}
