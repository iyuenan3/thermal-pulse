import Foundation
import OSLog
import ServiceManagement
import ThermalPulseCore

private let turboHelperRegistrationLogger = Logger(
    subsystem: "ThermalPulse",
    category: "TurboHelperRegistration"
)

@MainActor
final class SMAppServiceTurboHelperRegistrationClient: TurboHelperRegistrationClient {
    private static let unregisteredPollInterval = Duration.milliseconds(100)
    private static let requiredStableUnregisteredObservations = 10
    private static let unregistrationStabilizationTimeout = Duration.seconds(8)

    private let service = SMAppService.daemon(
        plistName: ThermalPulseIdentity.launchDaemonPlistName
    )

    func currentState() -> TurboHelperRegistrationState {
        mappedState(service.status)
    }

    func register() -> TurboHelperRegistrationState {
        do {
            try service.register()
            return mappedState(service.status)
        } catch {
            let stateAfterFailure = mappedState(service.status)
            if stateAfterFailure == .enabled || stateAfterFailure == .requiresApproval {
                return stateAfterFailure
            }

            let registrationError = error as NSError
            if registrationError.domain == SMAppServiceErrorDomain,
               registrationError.code == kSMErrorInvalidSignature {
                return .failed(.invalidSignature)
            }
            return .failed(.registrationFailed)
        }
    }

    func replaceRegistration() async -> TurboHelperRegistrationState {
        do {
            try await service.unregister()
            guard try await waitForStableUnregisteredState() else {
                turboHelperRegistrationLogger.error(
                    "helper unregistration did not stabilize status=\(self.service.status.rawValue, privacy: .public)"
                )
                return .failed(.upgradeFailed)
            }
            try service.register()
            return mappedState(service.status)
        } catch {
            let stateAfterFailure = mappedState(service.status)
            if stateAfterFailure == .enabled || stateAfterFailure == .requiresApproval {
                return stateAfterFailure
            }
            let registrationError = error as NSError
            turboHelperRegistrationLogger.error(
                "helper replacement failed domain=\(registrationError.domain, privacy: .public) code=\(registrationError.code, privacy: .public) status=\(self.service.status.rawValue, privacy: .public)"
            )
            return .failed(.upgradeFailed)
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func mappedState(_ status: SMAppService.Status) -> TurboHelperRegistrationState {
        switch status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .failed(.registrationFailed)
        }
    }

    private func waitForStableUnregisteredState() async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.unregistrationStabilizationTimeout)
        var stableObservationCount = 0

        while clock.now < deadline {
            switch service.status {
            case .notRegistered, .notFound:
                stableObservationCount += 1
                if stableObservationCount >= Self.requiredStableUnregisteredObservations {
                    return true
                }
            case .enabled, .requiresApproval:
                stableObservationCount = 0
            @unknown default:
                stableObservationCount = 0
            }

            try await Task.sleep(for: Self.unregisteredPollInterval)
        }

        return false
    }
}

final class TurboXPCClient: TurboClient, @unchecked Sendable {
    private static let startTimeout: TimeInterval = 70
    private static let stopTimeout: TimeInterval = 12
    private static let statusTimeout: TimeInterval = 3
    private let connectionState = TurboXPCConnectionState()

    private enum Request {
        case start
        case stop
        case status

        var timeout: TimeInterval {
            switch self {
            case .start: TurboXPCClient.startTimeout
            case .stop: TurboXPCClient.stopTimeout
            case .status: TurboXPCClient.statusTimeout
            }
        }
    }

    deinit {
        connectionState.invalidate()
    }

    func invalidate() {
        connectionState.invalidate()
    }

    func startTurbo() async throws -> TurboStatus {
        try await perform(.start)
    }

    func stopTurbo() async throws -> TurboStatus {
        try await perform(.stop)
    }

    func getTurboStatus() async throws -> TurboStatus {
        try await perform(.status)
    }

    private func perform(_ request: Request) async throws -> TurboStatus {
        guard let teamIdentifier = CurrentCodeSignature.teamIdentifier() else {
            throw TurboIssue.helperUnavailable
        }

        let requirement = try PeerCodeSigningRequirement.helper(
            teamIdentifier: teamIdentifier
        )

        return try await withCheckedThrowingContinuation { continuation in
            let pending = PendingTurboXPCRequest(continuation: continuation)
            guard let connection = connectionState.begin(
                request: pending,
                helperRequirement: requirement
            ) else {
                pending.resolve(.failure(TurboIssue.communicationFailure))
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + request.timeout
            ) { [connectionState] in
                connectionState.resolve(
                    pending,
                    with: .failure(TurboIssue.communicationFailure),
                    invalidateConnection: true
                )
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                self.connectionState.resolve(
                    pending,
                    with: .failure(TurboIssue.communicationFailure),
                    invalidateConnection: true
                )
            }) as? TurboXPCProtocol else {
                connectionState.resolve(
                    pending,
                    with: .failure(TurboIssue.communicationFailure),
                    invalidateConnection: true
                )
                return
            }

            let reply: (TurboXPCStatusPayload) -> Void = { payload in
                do {
                    self.connectionState.resolve(
                        pending,
                        with: .success(try payload.domainStatus()),
                        invalidateConnection: false
                    )
                } catch {
                    self.connectionState.resolve(
                        pending,
                        with: .failure(error),
                        invalidateConnection: true
                    )
                }
            }

            switch request {
            case .start:
                proxy.startTurbo(reply: reply)
            case .stop:
                proxy.stopTurbo(reply: reply)
            case .status:
                proxy.getTurboStatus(reply: reply)
            }
        }
    }
}

private final class PendingTurboXPCRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TurboStatus, any Error>?

    init(continuation: CheckedContinuation<TurboStatus, any Error>) {
        self.continuation = continuation
    }

    func resolve(_ result: Result<TurboStatus, any Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()

        continuation.resume(with: result)
    }
}

private final class TurboXPCConnectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var activeRequests: [ObjectIdentifier: PendingTurboXPCRequest] = [:]

    func begin(
        request: PendingTurboXPCRequest,
        helperRequirement: String
    ) -> NSXPCConnection? {
        lock.lock()
        let activeConnection: NSXPCConnection
        let shouldActivate: Bool
        if let connection {
            activeConnection = connection
            shouldActivate = false
        } else {
            let newConnection = NSXPCConnection(
                machServiceName: ThermalPulseIdentity.machServiceName,
                options: .privileged
            )
            newConnection.remoteObjectInterface = TurboXPCInterfaceFactory.makeInterface()
            newConnection.setCodeSigningRequirement(helperRequirement)
            newConnection.interruptionHandler = { [weak self] in
                self?.connectionFailed()
            }
            newConnection.invalidationHandler = { [weak self] in
                self?.connectionFailed()
            }
            connection = newConnection
            activeConnection = newConnection
            shouldActivate = true
        }
        activeRequests[ObjectIdentifier(request)] = request
        lock.unlock()

        if shouldActivate {
            activeConnection.activate()
        }
        return activeConnection
    }

    func resolve(
        _ request: PendingTurboXPCRequest,
        with result: Result<TurboStatus, any Error>,
        invalidateConnection: Bool
    ) {
        lock.lock()
        let requestID = ObjectIdentifier(request)
        guard activeRequests.removeValue(forKey: requestID) === request else {
            lock.unlock()
            return
        }
        let connectionToInvalidate: NSXPCConnection?
        let requestsToFail: [PendingTurboXPCRequest]
        if invalidateConnection {
            connectionToInvalidate = connection
            connection = nil
            requestsToFail = Array(activeRequests.values)
            activeRequests.removeAll()
        } else {
            connectionToInvalidate = nil
            requestsToFail = []
        }
        lock.unlock()

        if let connectionToInvalidate {
            connectionToInvalidate.interruptionHandler = nil
            connectionToInvalidate.invalidationHandler = nil
            connectionToInvalidate.invalidate()
        }
        request.resolve(result)
        requestsToFail.forEach {
            $0.resolve(.failure(TurboIssue.communicationFailure))
        }
    }

    func invalidate() {
        lock.lock()
        let requests = Array(activeRequests.values)
        activeRequests.removeAll()
        let connectionToInvalidate = connection
        connection = nil
        lock.unlock()

        connectionToInvalidate?.interruptionHandler = nil
        connectionToInvalidate?.invalidationHandler = nil
        connectionToInvalidate?.invalidate()
        requests.forEach {
            $0.resolve(.failure(TurboIssue.communicationFailure))
        }
    }

    private func connectionFailed() {
        invalidate()
    }
}
