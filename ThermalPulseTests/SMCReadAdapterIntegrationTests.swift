import Foundation
import XCTest
@testable import ThermalPulseCore

final class SMCReadAdapterIntegrationTests: XCTestCase {
    func testCurrentMachineCoreTemperatureCharacterizationWhenExplicitlyEnabled() async throws {
        #if !THERMALPULSE_HARDWARE_TESTS
        guard ProcessInfo.processInfo.environment["THERMALPULSE_RUN_HARDWARE_TESTS"] == "1" else {
            throw XCTSkip("设置 THERMALPULSE_RUN_HARDWARE_TESTS=1 后才运行真实 AppleSMC 只读探测")
        }
        #endif

        let service = try SMCProbeService()
        let snapshot = try await service.scan()
        let performanceCandidateNames = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0Y", "Tp0b", "Tp0e"]
        let efficiencyCandidateNames = ["Te05", "Te06", "Te0S", "Te0T"]
        let performanceKeys = performanceCandidateNames.compactMap(SMCKey.init(rawValue:)).filter { key in
            snapshot.readings.contains { $0.descriptor.key == key && $0.validity == .valid }
        }
        let efficiencyKeys = efficiencyCandidateNames.compactMap(SMCKey.init(rawValue:)).filter { key in
            snapshot.readings.contains { $0.descriptor.key == key && $0.validity == .valid }
        }
        let broadPerformanceKeys = snapshot.readings.compactMap { reading -> SMCKey? in
            let key = reading.descriptor.key.rawValue
            guard reading.validity == .valid,
                  reading.descriptor.kind == .temperatureCandidate,
                  reading.descriptor.unit == .celsius,
                  reading.dataType.normalized.trimmingCharacters(in: .whitespacesAndNewlines) == "flt",
                  key.hasPrefix("Tp")
            else { return nil }
            return reading.descriptor.key
        }
        let samplingKeys = Array(Set(broadPerformanceKeys + efficiencyKeys)).sorted()

        XCTAssertFalse(performanceKeys.isEmpty, "当前 Mac16,7 应至少提供一个已知 M4 Pro P 核温度 key")
        XCTAssertFalse(efficiencyKeys.isEmpty, "当前 Mac16,7 应至少提供一个已知 M4 Pro E 核温度 key")

        var valuesByKey: [SMCKey: [Double]] = [:]
        for sampleIndex in 0..<12 {
            let batch = await service.sample(keys: samplingKeys)
            let values = Dictionary(uniqueKeysWithValues: batch.readings.compactMap { reading -> (SMCKey, Double)? in
                guard reading.validity == .valid, let value = reading.value, value.isFinite else { return nil }
                valuesByKey[reading.descriptor.key, default: []].append(value)
                return (reading.descriptor.key, value)
            })

            func summary(for keys: [SMCKey]) -> String {
                let selected = keys.compactMap { values[$0] }.sorted()
                guard let minimum = selected.first, let maximum = selected.last else { return "unavailable" }
                let average = selected.reduce(0, +) / Double(selected.count)
                let median = selected[selected.count / 2]
                return String(
                    format: "count=%d avg=%.1f median=%.1f min=%.1f max=%.1f",
                    selected.count,
                    average,
                    median,
                    minimum,
                    maximum
                )
            }

            print(
                "ThermalPulse temperature trace sample=\(sampleIndex + 1) "
                    + "broadP={\(summary(for: broadPerformanceKeys))} "
                    + "curatedP={\(summary(for: performanceKeys))} "
                    + "curatedE={\(summary(for: efficiencyKeys))}"
            )
            if sampleIndex < 11 {
                try await Task.sleep(for: .seconds(1))
            }
        }

        let volatility = valuesByKey.compactMap { key, values -> (SMCKey, Double, Double, Double)? in
            guard let minimum = values.min(), let maximum = values.max() else { return nil }
            return (key, maximum - minimum, minimum, maximum)
        }.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
            return lhs.1 > rhs.1
        }
        print(
            "ThermalPulse temperature volatility: "
                + volatility.prefix(24).map { key, range, minimum, maximum in
                    String(format: "%@=%.1fC(%.1f..%.1f)", key.rawValue, range, minimum, maximum)
                }.joined(separator: " ")
        )
        print(
            "ThermalPulse curated core keys: P=\(performanceKeys.map(\.rawValue).joined(separator: ",")) "
                + "E=\(efficiencyKeys.map(\.rawValue).joined(separator: ","))"
        )
    }

    func testCurrentMachineTurboActiveReadbackWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["THERMALPULSE_EXPECT_TURBO_ACTIVE"] == "1" else {
            throw XCTSkip("仅在用户已经显式启动 Turbo 后设置 THERMALPULSE_EXPECT_TURBO_ACTIVE=1")
        }

        let adapter = try SMCReadAdapter()
        let fanCountRaw = try adapter.read(.fanCount)
        let fanCountValue = try XCTUnwrap(SMCValueDecoder.decode(fanCountRaw).numericValue)
        let fanCount = Int(fanCountValue)
        XCTAssertGreaterThan(fanCount, 0)
        XCTAssertLessThanOrEqual(fanCount, 16)

        let thermalManagerKey = try XCTUnwrap(SMCKey(rawValue: "Ftst"))
        let thermalManager = try adapter.read(thermalManagerKey)
        XCTAssertEqual(thermalManager.metadata.dataType.rawValue, "ui8 ")
        XCTAssertEqual(thermalManager.metadata.dataSize, 1)
        XCTAssertEqual(thermalManager.bytes, [1], "active Turbo 必须仍持有 thermal manager")

        let safetyPolicy = TurboSafetyPolicy()
        for index in 0..<fanCount {
            let indexCode = String(index, radix: 16, uppercase: true)
            let modeKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Md"))
            let targetKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Tg"))
            let maximumKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Mx"))
            let actualKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Ac"))

            let mode = try adapter.read(modeKey)
            let target = try adapter.read(targetKey)
            let maximum = try adapter.read(maximumKey)
            XCTAssertEqual(mode.bytes, [1], "active Turbo 必须保持风扇 \(index) 为 manual 模式")
            XCTAssertEqual(target.metadata.dataType, maximum.metadata.dataType)
            XCTAssertEqual(target.metadata.dataSize, maximum.metadata.dataSize)
            XCTAssertEqual(target.bytes, maximum.bytes, "active Turbo 目标必须等于实时最大值")

            var actualSamples: [Double] = []
            for sampleIndex in 0..<3 {
                let actual = SensorClassifier.classify(try adapter.read(actualKey))
                XCTAssertEqual(actual.validity, .valid)
                actualSamples.append(try XCTUnwrap(actual.value))
                if sampleIndex < 2 {
                    try await Task.sleep(for: .seconds(1))
                }
            }

            let maximumRPM = try XCTUnwrap(SMCValueDecoder.decode(maximum).numericValue)
            let observedMaximumRPM = try XCTUnwrap(actualSamples.max())
            XCTAssertGreaterThanOrEqual(
                observedMaximumRPM,
                maximumRPM * 0.5,
                "active Turbo 的实际 RPM 必须持续提升到最大转速的至少一半"
            )
            XCTAssertTrue(
                actualSamples.allSatisfy {
                    safetyPolicy.isActualRPMPlausible($0, maximumRPM: maximumRPM)
                },
                "actual RPM 可以小幅超过标称最大值，但必须保持在安全容差内"
            )
            print(
                "ThermalPulse Turbo active readback: fan=\(index) mode=1 "
                    + "target=\(Int(maximumRPM))RPM actual="
                    + actualSamples.map { String(Int($0)) }.joined(separator: ",")
                    + "RPM"
            )
        }
    }

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
            let modeValue = try XCTUnwrap(mode.bytes.first)
            XCTAssertTrue(
                modeValue == 0 || modeValue == 3,
                "helper 注册或升级期间风扇 \(index) 必须处于 Apple automatic 或 system 模式"
            )
            print("ThermalPulse Turbo preflight: fan=\(index) mode=\(modeValue)")
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

        let safetyPolicy = TurboSafetyPolicy()
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
            let actualRPM = try XCTUnwrap(actual.value)
            let maximumRPM = try XCTUnwrap(maximum.value)
            XCTAssertGreaterThan(maximumRPM, 0)
            XCTAssertTrue(
                safetyPolicy.isActualRPMPlausible(actualRPM, maximumRPM: maximumRPM),
                "实际 RPM 可以小幅超过标称最大值，但必须保持在安全容差内"
            )
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

        let efficiencyCoreSummary = try XCTUnwrap(
            ComponentTemperaturePolicy.summary(for: .efficiencyCore, from: snapshot.readings),
            "当前机器应提供有效的 Te float 温度候选族"
        )
        let efficiencyCoreAverage = String(format: "%.1f", efficiencyCoreSummary.average)
        let efficiencyCoreMaximum = String(format: "%.1f", efficiencyCoreSummary.maximum)
        print(
            "ThermalPulse E-core family evidence: count=\(efficiencyCoreSummary.sensorCount) "
                + "average=\(efficiencyCoreAverage)C "
                + "maximum=\(efficiencyCoreMaximum)C "
                + "hottestKey=\(efficiencyCoreSummary.representativeKey.rawValue)"
        )

        let efficiencyLikeEvidence = snapshot.readings
            .filter { $0.descriptor.key.rawValue.hasPrefix("Te") }
            .map { reading in
                let value = reading.value.map { String(format: "%.1fC", $0) } ?? "nil"
                return "\(reading.descriptor.key.rawValue)[\(reading.dataType.rawValue)]=\(value),validity=\(reading.validity)"
            }
        print(
            "ThermalPulse E-core-like temperature candidates: "
                + (efficiencyLikeEvidence.isEmpty ? "none" : efficiencyLikeEvidence.joined(separator: " "))
        )

        let focusedTemperatureKeys: [(component: String, keys: [String])] = [
            ("memory-proximity", ["Tm0p", "Tm1p", "Tm2p"]),
            ("ssd-nand", ["TH0x"]),
            ("battery", ["TB1T", "TB2T"]),
        ]
        for candidate in focusedTemperatureKeys {
            var componentEvidence: [String] = []
            for rawKey in candidate.keys {
                let key = try XCTUnwrap(SMCKey(rawValue: rawKey))
                guard let reading = snapshot.readings.first(where: { $0.descriptor.key == key }) else {
                    componentEvidence.append("\(rawKey)=unavailable")
                    continue
                }
                let value = reading.value.map { String(format: "%.1fC", $0) } ?? "nil"
                componentEvidence.append(
                    "\(rawKey)[\(reading.dataType.rawValue)]=\(value),validity=\(reading.validity)"
                )
            }
            print(
                "ThermalPulse focused temperature evidence: component=\(candidate.component) "
                    + componentEvidence.joined(separator: " ")
            )
        }
        let memoryLikeEvidence = snapshot.readings
            .filter { $0.descriptor.key.rawValue.hasPrefix("Tm") }
            .map { reading in
                let value = reading.value.map { String(format: "%.1fC", $0) } ?? "nil"
                return "\(reading.descriptor.key.rawValue)[\(reading.dataType.rawValue)]=\(value)"
            }
        print(
            "ThermalPulse memory-like temperature candidates: "
                + (memoryLikeEvidence.isEmpty ? "none" : memoryLikeEvidence.joined(separator: " "))
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
