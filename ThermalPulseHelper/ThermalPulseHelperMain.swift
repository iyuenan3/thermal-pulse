import Dispatch
import Foundation
import OSLog
import ThermalPulseCore

@main
enum ThermalPulseHelperMain {
    private static let logger = Logger(
        subsystem: ThermalPulseIdentity.helperIdentifier,
        category: "lifecycle"
    )

    static func main() {
        guard let teamIdentifier = CurrentCodeSignature.teamIdentifier(),
              let appRequirement = try? PeerCodeSigningRequirement.app(
                  teamIdentifier: teamIdentifier
              )
        else {
            logger.fault("helper refused to start without a trusted Team ID")
            return
        }

        let hardware: any TurboFanHardware
        do {
            hardware = try SMCFanWriteAdapter()
        } catch {
            logger.fault("AppleSMC adapter unavailable; Turbo will remain disabled")
            hardware = UnavailableTurboFanHardware()
        }

        let controller = TurboSafetyController(
            hardware: hardware,
            leaseStore: TurboLeaseFileStore()
        )
        let runtime = TurboHelperRuntime(controller: controller)
        let delegate = TurboHelperListenerDelegate(runtime: runtime)
        let listener = NSXPCListener(
            machServiceName: ThermalPulseIdentity.machServiceName
        )
        listener.setConnectionCodeSigningRequirement(appRequirement)
        listener.delegate = delegate
        listener.activate()
        logger.notice("helper listener activated with fixed 600-second Turbo safety lease")
        dispatchMain()
    }
}
