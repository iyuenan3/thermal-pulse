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
            leaseStore: TurboLeaseFileStore(),
            diagnosticSink: TurboOSLogDiagnosticSink()
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

private struct TurboOSLogDiagnosticSink: TurboDiagnosticSink {
    private let logger = Logger(
        subsystem: ThermalPulseIdentity.helperIdentifier,
        category: "turbo"
    )

    func record(_ event: TurboDiagnosticEvent) {
        switch event {
        case let .activationStarted(fanCount):
            logger.notice("activation_started fan_count=\(fanCount, privacy: .public)")
        case let .thermalManagerUnlockClaimed(fanIndex):
            logger.notice("thermal_manager_unlock_claimed fan_index=\(fanIndex, privacy: .public)")
        case let .modeReadbackMismatch(fanIndex, observed):
            let mode = modeLabel(observed)
            logger.error(
                "mode_readback_mismatch fan_index=\(fanIndex, privacy: .public) observed=\(mode, privacy: .public)"
            )
        case let .targetReadbackMismatch(fanIndex, expectedRPM, observedRPM):
            let observed = observedRPM ?? -1
            logger.error(
                "target_readback_mismatch fan_index=\(fanIndex, privacy: .public) expected_rpm=\(expectedRPM, privacy: .public) observed_rpm=\(observed, privacy: .public)"
            )
        case let .actualRPMReadbackFailed(samples):
            log(samples: samples, outcome: "actual_rpm_readback_failed")
        case let .actualRPMRiseVerified(samples):
            log(samples: samples, outcome: "actual_rpm_rise_verified")
        case let .restorationCompleted(issue):
            let issueLabel = issue?.rawValue ?? "none"
            logger.notice("restoration_completed issue=\(issueLabel, privacy: .public)")
        case let .restorationFailed(stage, fanIndex):
            let index = fanIndex ?? -1
            logger.fault(
                "restoration_failed stage=\(stage.rawValue, privacy: .public) fan_index=\(index, privacy: .public)"
            )
        }
    }

    private func log(samples: [TurboFanDiagnosticSample], outcome: String) {
        for sample in samples {
            let actual = sample.actualRPM ?? -1
            logger.notice(
                "\(outcome, privacy: .public) fan_index=\(sample.fanIndex, privacy: .public) baseline_rpm=\(sample.baselineRPM, privacy: .public) maximum_rpm=\(sample.maximumRPM, privacy: .public) actual_rpm=\(actual, privacy: .public)"
            )
        }
    }

    private func modeLabel(_ mode: TurboFanMode?) -> String {
        switch mode {
        case .automatic: "automatic"
        case .manual: "manual"
        case .system: "system"
        case nil: "unavailable"
        }
    }
}
