import Foundation
import XCTest
@testable import ThermalPulseCore

final class SMCReadAdapterIntegrationTests: XCTestCase {
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

        var evidence: [String] = []
        for index in 0..<fanCount {
            let indexCode = String(index, radix: 16, uppercase: true)
            let actualKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Ac"))
            let maximumKey = try XCTUnwrap(SMCKey(rawValue: "F\(indexCode)Mx"))
            let actualRaw = try adapter.read(actualKey)
            let maximumRaw = try adapter.read(maximumKey)
            let actual = SensorClassifier.classify(actualRaw)
            let maximum = SensorClassifier.classify(maximumRaw)

            XCTAssertEqual(actual.validity, .valid)
            XCTAssertEqual(maximum.validity, .valid)
            XCTAssertGreaterThan(try XCTUnwrap(maximum.value), 0)
            XCTAssertLessThanOrEqual(try XCTUnwrap(actual.value), try XCTUnwrap(maximum.value))
            evidence.append(
                "\(actualKey)[\(actualRaw.metadata.dataType)]=\(Int(actual.value ?? -1))RPM "
                    + "\(maximumKey)[\(maximumRaw.metadata.dataType)]=\(Int(maximum.value ?? -1))RPM"
            )
        }

        print("ThermalPulse read-only evidence: keys=\(keyCount) fans=\(fanCount) \(evidence.joined(separator: " "))")

        let service = try SMCProbeService()
        let snapshot = try await service.scan()
        XCTAssertEqual(snapshot.advertisedKeyCount, keyCount)
        XCTAssertEqual(snapshot.enumeratedKeyCount, keyCount)
        XCTAssertEqual(snapshot.fanCount, fanCount)
        XCTAssertGreaterThanOrEqual(snapshot.metadataReadCount, snapshot.sampledKeyCount)

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
