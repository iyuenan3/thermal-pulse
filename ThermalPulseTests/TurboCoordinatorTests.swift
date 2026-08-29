import XCTest
@testable import ThermalPulseCore

final class TurboCoordinatorTests: XCTestCase {
    func testUnavailableClientKeepsAutomaticModeAndBlocksStart() async {
        let coordinator = TurboCoordinator(client: UnavailableTurboClient())

        let synchronized = await coordinator.synchronize()
        let started = await coordinator.startTurbo()

        XCTAssertEqual(synchronized, .inactive(issue: .helperUnavailable))
        XCTAssertEqual(started, synchronized)
        XCTAssertFalse(started.canStart)
    }

    func testStartAcceptsOnlyFixedBoundedActiveLeaseAndDoesNotRestart() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let active = TurboStatus(
            phase: .active,
            startedAt: now,
            deadline: now.addingTimeInterval(600)
        )
        let client = TurboClientSpy(startResponse: .success(active))
        let coordinator = TurboCoordinator(client: client)

        let first = await coordinator.startTurbo(now: now)
        let second = await coordinator.startTurbo(now: now.addingTimeInterval(1))
        let startCallCount = await client.startCallCount()

        XCTAssertEqual(first, active)
        XCTAssertEqual(second, active)
        XCTAssertEqual(startCallCount, 1)
        XCTAssertEqual(first.remainingSeconds(at: now), 600)
        XCTAssertEqual(first.remainingSeconds(at: now.addingTimeInterval(599.2)), 1)
    }

    func testStartRejectsLeaseLongerThanSixHundredSeconds() async {
        let now = Date(timeIntervalSince1970: 20_000)
        let unsafe = TurboStatus(
            phase: .active,
            startedAt: now,
            deadline: now.addingTimeInterval(601)
        )
        let client = TurboClientSpy(startResponse: .success(unsafe))
        let coordinator = TurboCoordinator(client: client)

        let status = await coordinator.startTurbo(now: now)

        XCTAssertEqual(
            status,
            TurboStatus(phase: .failedSafeAuto, issue: .invalidStatusResponse)
        )
    }

    func testActiveStatusQueryFailureNeverClaimsAutomaticMode() async {
        let now = Date(timeIntervalSince1970: 25_000)
        let active = TurboStatus(
            phase: .active,
            startedAt: now,
            deadline: now.addingTimeInterval(600)
        )
        let client = TurboClientSpy(
            startResponse: .success(active),
            statusResponse: .failure(.communicationFailure)
        )
        let coordinator = TurboCoordinator(client: client)

        _ = await coordinator.startTurbo(now: now)
        let synchronized = await coordinator.synchronize(now: now.addingTimeInterval(10))

        XCTAssertEqual(
            synchronized,
            TurboStatus(phase: .failedSafeAuto, issue: .communicationFailure)
        )
    }

    func testExternalControllerRefusalReturnsInactiveWithoutRetry() async {
        let client = TurboClientSpy(startResponse: .failure(.externalControllerDetected))
        let coordinator = TurboCoordinator(client: client)

        let first = await coordinator.startTurbo()
        let second = await coordinator.startTurbo()
        let startCallCount = await client.startCallCount()

        XCTAssertEqual(first, .inactive(issue: .externalControllerDetected))
        XCTAssertEqual(second, first)
        XCTAssertEqual(startCallCount, 1)
    }

    func testStartPreservesHelpersConfirmedSafetyFailure() async {
        let helperFailure = TurboStatus(phase: .failedSafeAuto, issue: .readbackMismatch)
        let client = TurboClientSpy(startResponse: .success(helperFailure))
        let coordinator = TurboCoordinator(client: client)

        let status = await coordinator.startTurbo()

        XCTAssertEqual(status, helperFailure)
    }

    func testStopRequiresConfirmedInactiveReadback() async {
        let now = Date(timeIntervalSince1970: 30_000)
        let active = TurboStatus(
            phase: .active,
            startedAt: now,
            deadline: now.addingTimeInterval(600)
        )
        let client = TurboClientSpy(
            startResponse: .success(active),
            stopResponse: .success(.inactive())
        )
        let coordinator = TurboCoordinator(client: client)

        _ = await coordinator.startTurbo(now: now)
        let stopped = await coordinator.stopTurbo()
        let stoppedAgain = await coordinator.stopTurbo()
        let stopCallCount = await client.stopCallCount()

        XCTAssertEqual(stopped, .inactive())
        XCTAssertEqual(stoppedAgain, stopped)
        XCTAssertEqual(stopCallCount, 1)
    }

    func testStopFailureDoesNotClaimAutomaticRecovery() async {
        let now = Date(timeIntervalSince1970: 40_000)
        let active = TurboStatus(
            phase: .active,
            startedAt: now,
            deadline: now.addingTimeInterval(600)
        )
        let client = TurboClientSpy(
            startResponse: .success(active),
            stopResponse: .failure(.recoveryFailed)
        )
        let coordinator = TurboCoordinator(client: client)

        _ = await coordinator.startTurbo(now: now)
        let stopped = await coordinator.stopTurbo()

        XCTAssertEqual(
            stopped,
            TurboStatus(phase: .failedSafeAuto, issue: .recoveryFailed)
        )
    }

    @MainActor
    func testHelperRegistrationRequiresExplicitRegisterThenApproval() {
        let client = TurboHelperRegistrationClientSpy(
            currentState: .notRegistered,
            registerState: .requiresApproval
        )
        let coordinator = TurboHelperRegistrationCoordinator(client: client)

        XCTAssertEqual(coordinator.refresh(), .notRegistered)
        XCTAssertEqual(coordinator.register(), .requiresApproval)
        XCTAssertEqual(client.registerCallCount, 1)
        XCTAssertFalse(coordinator.state.canRegister)
        XCTAssertTrue(coordinator.state.canOpenSystemSettings)
    }

    @MainActor
    func testHelperRegistrationNeverRegistersBeforeStatusIsKnown() {
        let client = TurboHelperRegistrationClientSpy(
            currentState: .notRegistered,
            registerState: .enabled
        )
        let coordinator = TurboHelperRegistrationCoordinator(client: client)

        XCTAssertEqual(coordinator.register(), .checking)
        XCTAssertEqual(client.registerCallCount, 0)
    }

    @MainActor
    func testUnknownSystemServiceCanBeRegisteredExplicitly() {
        let client = TurboHelperRegistrationClientSpy(
            currentState: .notFound,
            registerState: .requiresApproval
        )
        let coordinator = TurboHelperRegistrationCoordinator(client: client)

        XCTAssertEqual(coordinator.refresh(), .notFound)
        XCTAssertTrue(coordinator.state.canRegister)
        XCTAssertEqual(coordinator.register(), .requiresApproval)
        XCTAssertEqual(client.registerCallCount, 1)
    }

    @MainActor
    func testHelperSettingsOnlyOpenForApprovalState() {
        let client = TurboHelperRegistrationClientSpy(
            currentState: .notRegistered,
            registerState: .requiresApproval
        )
        let coordinator = TurboHelperRegistrationCoordinator(client: client)

        coordinator.openSystemSettings()
        XCTAssertEqual(client.openSettingsCallCount, 0)

        _ = coordinator.refresh()
        _ = coordinator.register()
        coordinator.openSystemSettings()
        XCTAssertEqual(client.openSettingsCallCount, 1)
    }

    @MainActor
    func testHelperUpgradeRequiresEnabledStateAndReplacesOnce() async {
        let client = TurboHelperRegistrationClientSpy(
            currentState: .enabled,
            registerState: .enabled,
            replaceState: .requiresApproval
        )
        let coordinator = TurboHelperRegistrationCoordinator(client: client)

        let ignoredReplacement = await coordinator.replaceRegistration()
        XCTAssertEqual(ignoredReplacement, .checking)
        XCTAssertEqual(client.replaceCallCount, 0)
        XCTAssertEqual(coordinator.refresh(), .enabled)
        let replacement = await coordinator.replaceRegistration()
        XCTAssertEqual(replacement, .requiresApproval)
        XCTAssertEqual(client.replaceCallCount, 1)
        XCTAssertFalse(coordinator.state.canRegister)
    }
}

@MainActor
private final class TurboHelperRegistrationClientSpy: TurboHelperRegistrationClient {
    let currentStateValue: TurboHelperRegistrationState
    let registerState: TurboHelperRegistrationState
    let replaceState: TurboHelperRegistrationState
    private(set) var registerCallCount = 0
    private(set) var replaceCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(
        currentState: TurboHelperRegistrationState,
        registerState: TurboHelperRegistrationState,
        replaceState: TurboHelperRegistrationState = .enabled
    ) {
        currentStateValue = currentState
        self.registerState = registerState
        self.replaceState = replaceState
    }

    func currentState() -> TurboHelperRegistrationState {
        currentStateValue
    }

    func register() -> TurboHelperRegistrationState {
        registerCallCount += 1
        return registerState
    }

    func replaceRegistration() async -> TurboHelperRegistrationState {
        replaceCallCount += 1
        return replaceState
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}

private actor TurboClientSpy: TurboClient {
    private let startResponse: Result<TurboStatus, TurboIssue>
    private let stopResponse: Result<TurboStatus, TurboIssue>
    private let statusResponse: Result<TurboStatus, TurboIssue>
    private var starts = 0
    private var stops = 0

    init(
        startResponse: Result<TurboStatus, TurboIssue>,
        stopResponse: Result<TurboStatus, TurboIssue> = .success(.inactive()),
        statusResponse: Result<TurboStatus, TurboIssue> = .success(.inactive())
    ) {
        self.startResponse = startResponse
        self.stopResponse = stopResponse
        self.statusResponse = statusResponse
    }

    func startTurbo() async throws -> TurboStatus {
        starts += 1
        return try startResponse.get()
    }

    func stopTurbo() async throws -> TurboStatus {
        stops += 1
        return try stopResponse.get()
    }

    func getTurboStatus() async throws -> TurboStatus {
        try statusResponse.get()
    }

    func startCallCount() -> Int {
        starts
    }

    func stopCallCount() -> Int {
        stops
    }
}
