import Foundation
import XCTest
@testable import ThermalPulseCore

final class SMCReadAdapterIntegrationTests: XCTestCase {
    func testCurrentMachineTurboUpgradePreflightWhenExplicitlyEnabled() throws {
        #if !THERMALPULSE_HARDWARE_TESTS
        guard ProcessInfo.processInfo.environment["THERMALPULSE_RUN_HARDWARE_TESTS"] == "1" else {
            throw XCTSkip("设置 THERMALPULSE_RUN_HARDWARE_TESTS=1 后才运行真实 AppleSMC 只读探测")
        }
        #endif

        let adapter = try SMCReadAdapter()
        let fanCountRaw = try adapter.read(.fanCount)
        let fanCountValue = try XCTUnwrap(SMCValueDecoder.decode(fanCountRaw).numericValue)
        let fanCount = Int(fanCountValue)
        XCTAssertGreaterThan(fanCount, 0)
        XCTAssertLessThanOrEqual(fanCount, 16)

        for index in 0..<fanCount {
            let indexCode = String(index, radix: 16, uppercase: true)
            var modeRaw: SMCRawValue?
            for suffix in ["Md", "md"] {
                let key = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)\(suffix)"))
                if let value = try? adapter.read(key) {
                    modeRaw = value
                    break
                }
            }

            let mode = try XCTUnwrap(modeRaw, "风扇 \(index) 必须提供可读的逐风扇模式 key")
            XCTAssertEqual(mode.metadata.dataType.rawValue, "ui8 ")
            XCTAssertEqual(mode.metadata.dataSize, 1)
            XCTAssertEqual(mode.bytes, [0], "helper 注册或升级期间风扇 \(index) 必须处于苹果自动模式")
        }

        let thermalManagerKey = try XCTUnwrap(SMCKey(rawValue: "Ftst"))
        let thermalManager = try adapter.read(thermalManagerKey)
        XCTAssertEqual(thermalManager.metadata.dataType.rawValue, "ui8 ")
        XCTAssertEqual(thermalManager.metadata.dataSize, 1)
        XCTAssertEqual(thermalManager.bytes, [0], "helper 注册或升级期间 ThermalPulse 不得接管 thermal manager")
    }

    func testCurrentMachineReadOnlyFanProbeWhenExplicitlyEnabled() async throws {
        #if !THERMALPULSE_HARDWARE_TESTS
        guard ProcessInfo.processInfo.environment["THERMALPULSE_RUN_HARDWARE_TESTS"] == "1" else {
            throw XCTSkip("设置 THERMALPULSE_RUN_HARDWARE_TESTS=1 后才运行真实 AppleSMC 只读探测")
        }
        #endif

        let adapter = try SMCReadAdapter()
        let keyCount = try adapter.keyCount()
        XCTAssertGreaterThan(keyCount, 0)

        let fanCountRaw = try adapter.read(.fanCount)
        let fanCountValue = try XCTUnwrap(SMCValueDecoder.decode(fanCountRaw).numericValue)
        let fanCount = Int(fanCountValue)
        XCTAssertGreaterThan(fanCount, 0)
        XCTAssertLessThanOrEqual(fanCount, 16)

        let enumeratedFanKeys = try adapter.enumerateKeys().filter { $0.rawValue.hasPrefix("F") }
        var fanKeyEvidence: [String] = []
        for key in enumeratedFanKeys {
            do {
                let raw = try adapter.read(key)
                let hex = raw.bytes.map { String(format: "%02X", $0) }.joined()
                let numeric = SMCValueDecoder.decode(raw).numericValue.map { String(format: "%.2f", $0) }
                let numericEvidence = numeric.map { ",numeric=\($0)" } ?? ""
                fanKeyEvidence.append(
                    "\(key)[\(raw.metadata.dataType),size=\(raw.metadata.dataSize),"
                        + "attr=\(raw.metadata.attributes)]=\(hex)"
                        + numericEvidence
                )
            } catch {
                fanKeyEvidence.append("\(key)=unreadable(\(error))")
            }
        }
        print("ThermalPulse enumerated fan-key evidence: \(fanKeyEvidence.joined(separator: " "))")

        let globalModeKey = try XCTUnwrap(SMCKey(rawValue: "FS! "))
        do {
            let globalModeRaw = try adapter.read(globalModeKey)
            let globalModeHex = globalModeRaw.bytes.map { String(format: "%02X", $0) }.joined()
            print(
                "ThermalPulse fan-control read-only evidence: "
                    + "\(globalModeKey)[\(globalModeRaw.metadata.dataType)]=\(globalModeHex)"
            )
        } catch {
            print("ThermalPulse fan-control read-only evidence: \(globalModeKey)=unavailable(\(error))")
        }

        var evidence: [String] = []
        for index in 0..<fanCount {
            let indexCode = String(index, radix: 16, uppercase: true)
            let actualKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Ac"))
            let maximumKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Mx"))
            let targetKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Tg"))
            let actualRaw = try adapter.read(actualKey)
            let maximumRaw = try adapter.read(maximumKey)
            let targetRaw = try adapter.read(targetKey)
            let actual = SensorClassifier.classify(actualRaw)
            let maximum = SensorClassifier.classify(maximumRaw)

            XCTAssertEqual(actual.validity, .valid)
            XCTAssertEqual(maximum.validity, .valid)
            XCTAssertEqual(targetRaw.metadata.dataType, maximumRaw.metadata.dataType)
            XCTAssertEqual(targetRaw.metadata.dataSize, maximumRaw.metadata.dataSize)
            XCTAssertGreaterThan(try XCTUnwrap(maximum.value), 0)
            XCTAssertLessThanOrEqual(try XCTUnwrap(actual.value), try XCTUnwrap(maximum.value))
            evidence.append(
                "\(actualKey)[\(actualRaw.metadata.dataType)]=\(Int(actual.value ?? -1))RPM "
                    + "\(maximumKey)[\(maximumRaw.metadata.dataType)]=\(Int(maximum.value ?? -1))RPM "
                    + "\(targetKey)[\(targetRaw.metadata.dataType)]="
                    + "\(Int(SMCValueDecoder.decode(targetRaw).numericValue ?? -1))RPM"
            )
        }

        print("ThermalPulse read-only evidence: keys=\(keyCount) fans=\(fanCount) \(evidence.joined(separator: " "))")

        let service = try SMCProbeService()
        let snapshot = try await service.scan()
        XCTAssertEqual(snapshot.advertisedKeyCount, keyCount)
        XCTAssertEqual(snapshot.enumeratedKeyCount, keyCount)
        XCTAssertEqual(snapshot.fanCount, fanCount)
        XCTAssertGreaterThanOrEqual(snapshot.metadataReadCount, snapshot.sampledKeyCount)

        let performanceCoreSummary = try XCTUnwrap(
            PerformanceCoreTemperaturePolicy.summary(from: snapshot.readings),
            "当前机器应提供有效的 Tp float 温度候选族"
        )
        XCTAssertGreaterThan(performanceCoreSummary.sensorCount, 0)
        let performanceCoreAverage = String(format: "%.1f", performanceCoreSummary.average)
        let performanceCoreMaximum = String(format: "%.1f", performanceCoreSummary.maximum)
        print(
            "ThermalPulse P-core family evidence: count=\(performanceCoreSummary.sensorCount) "
                + "average=\(performanceCoreAverage)C "
                + "maximum=\(performanceCoreMaximum)C "
                + "hottestKey=\(performanceCoreSummary.hottestKey.rawValue)"
        )

        for index in 0..<fanCount {
            let indexCode = String(index, radix: 16, uppercase: true)
            let actualKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Ac"))
            let reading = try XCTUnwrap(snapshot.readings.first { $0.descriptor.key == actualKey })
            XCTAssertEqual(reading.validity, .valid)
        }

        let samplingKeys = snapshot.readings.compactMap { reading -> SMCKey? in
            guard reading.validity == .valid else { return nil }
            switch reading.descriptor.kind {
            case .fanActualSpeed, .temperatureCandidate:
                return reading.descriptor.key
            case .fanMaximumSpeed, .metadata, .raw:
                return nil
            }
        }
        XCTAssertFalse(samplingKeys.isEmpty)

        let firstBatch = await service.sample(keys: samplingKeys)
        let secondBatch = await service.sample(keys: samplingKeys)
        XCTAssertEqual(firstBatch.readings.count, samplingKeys.count)
        XCTAssertEqual(secondBatch.readings.count, samplingKeys.count)

        for index in 0..<fanCount {
            let indexCode = String(index, radix: 16, uppercase: true)
            let actualKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Ac"))
            let firstReading = try XCTUnwrap(firstBatch.readings.first { $0.descriptor.key == actualKey })
            let secondReading = try XCTUnwrap(secondBatch.readings.first { $0.descriptor.key == actualKey })
            XCTAssertEqual(firstReading.validity, .valid)
            XCTAssertEqual(secondReading.validity, .valid)
        }

        print(
            "ThermalPulse scan evidence: enumerated=\(snapshot.enumeratedKeyCount) "
                + "metadata=\(snapshot.metadataReadCount) sampled=\(snapshot.sampledKeyCount) "
                + "failed=\(snapshot.failedReadCount) sampling=\(samplingKeys.count) "
                + "batchFailures=\(firstBatch.failedReadCount),\(secondBatch.failedReadCount)"
        )
    }
}
