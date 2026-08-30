import AppKit
import Dispatch
import Foundation
import ThermalPulseCore

final class TurboHelperRuntime: @unchecked Sendable {
    let controller: TurboSafetyController

    private let watchdog: DispatchSourceTimer
    private var wakeObserver: NSObjectProtocol?

    init(controller: TurboSafetyController) {
        self.controller = controller

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + .milliseconds(300),
            repeating: .milliseconds(300),
            leeway: .milliseconds(50)
        )
        timer.setEventHandler { [controller] in
            Task {
                _ = await controller.watchdogTick()
            }
        }
        watchdog = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [controller] _ in
            Task {
                _ = await controller.systemDidWake()
            }
        }

        Task {
            _ = await controller.bootstrap()
        }
        timer.activate()
    }

    deinit {
        watchdog.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}

final class TurboHelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let runtime: TurboHelperRuntime
    private let lock = NSLock()
    private var sessions: [UUID: TurboHelperSession] = [:]

    init(runtime: TurboHelperRuntime) {
        self.runtime = runtime
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let sessionID = UUID()
        let session = TurboHelperSession(
            id: sessionID,
            controller: runtime.controller
        )
        lock.withLock {
            sessions[sessionID] = session
        }

        connection.exportedInterface = TurboXPCInterfaceFactory.makeInterface()
        connection.exportedObject = session
        connection.interruptionHandler = { [weak self] in
            self?.endSession(sessionID)
        }
        connection.invalidationHandler = { [weak self] in
            self?.endSession(sessionID)
        }
        connection.activate()
        return true
    }

    private func endSession(_ sessionID: UUID) {
        let removed = lock.withLock {
            sessions.removeValue(forKey: sessionID) != nil
        }
        guard removed else { return }
        Task { [controller = runtime.controller] in
            _ = await controller.connectionInvalidated(ownerID: sessionID)
        }
    }
}

final class TurboHelperSession: NSObject, TurboXPCProtocol, @unchecked Sendable {
    private let id: UUID
    private let controller: TurboSafetyController

    init(id: UUID, controller: TurboSafetyController) {
        self.id = id
        self.controller = controller
    }

    func startTurbo(reply: @escaping (TurboXPCStatusPayload) -> Void) {
        let replyBox = TurboReplyBox(reply)
        Task { [controller, id] in
            let status = await controller.startTurbo(ownerID: id)
            replyBox.send(TurboXPCStatusPayload(status: status))
        }
    }

    func stopTurbo(reply: @escaping (TurboXPCStatusPayload) -> Void) {
        let replyBox = TurboReplyBox(reply)
        Task { [controller] in
            let status = await controller.stopTurbo()
            replyBox.send(TurboXPCStatusPayload(status: status))
        }
    }

    func getTurboStatus(reply: @escaping (TurboXPCStatusPayload) -> Void) {
        let replyBox = TurboReplyBox(reply)
        Task { [controller] in
            let status = await controller.currentStatus()
            replyBox.send(TurboXPCStatusPayload(status: status))
        }
    }
}

private final class TurboReplyBox: @unchecked Sendable {
    private let reply: (TurboXPCStatusPayload) -> Void

    init(_ reply: @escaping (TurboXPCStatusPayload) -> Void) {
        self.reply = reply
    }

    func send(_ payload: TurboXPCStatusPayload) {
        reply(payload)
    }
}
