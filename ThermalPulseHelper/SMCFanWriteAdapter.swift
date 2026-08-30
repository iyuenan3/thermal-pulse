import Foundation
import IOKit
import ThermalPulseCore

final class SMCFanWriteAdapter: TurboFanHardware, @unchecked Sendable {
    private static let maximumFanCount = 16
    private static let writeBytesCommand: UInt8 = 6
    private static let userClientSelector: UInt32 = 2

    private let reader: SMCReadAdapter
    private var writeConnection: io_connect_t

    init() throws {
        reader = try SMCReadAdapter()

        guard let matching = IOServiceMatching("AppleSMC") else {
            throw TurboFanHardwareError.unavailable
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            throw TurboFanHardwareError.unavailable
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = IO_OBJECT_NULL
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            throw TurboFanHardwareError.unavailable
        }
        writeConnection = connection
    }

    deinit {
        if writeConnection != IO_OBJECT_NULL {
            IOServiceClose(writeConnection)
        }
    }

    func discoverFans() throws -> [TurboFanDescriptor] {
        do {
            let countRaw = try reader.read(.fanCount)
            guard let countValue = SMCValueDecoder.decode(countRaw).numericValue,
                  countValue.rounded() == countValue,
                  countValue >= 0,
                  countValue <= Double(Self.maximumFanCount)
            else {
                throw TurboFanHardwareError.invalidData
            }

            let count = Int(countValue)
            return try (0..<count).map { index in
                let actualKey = try requiredKey(index: index, suffix: "Ac")
                let maximumKey = try requiredKey(index: index, suffix: "Mx")
                let targetKey = try requiredKey(index: index, suffix: "Tg")
                let modeKey = try resolvedModeKey(index: index)

                let actualRaw = try reader.read(actualKey)
                let maximumRaw = try reader.read(maximumKey)
                let targetMetadata = try reader.metadata(for: targetKey)
                let modeMetadata = try reader.metadata(for: modeKey)

                guard actualRaw.metadata.dataType.rawValue == "flt ",
                      maximumRaw.metadata.dataType.rawValue == "flt ",
                      targetMetadata.dataType.rawValue == "flt ",
                      actualRaw.metadata.dataSize == 4,
                      maximumRaw.metadata.dataSize == 4,
                      targetMetadata.dataSize == 4,
                      modeMetadata.dataType.rawValue == "ui8 ",
                      modeMetadata.dataSize == 1,
                      let actual = SMCValueDecoder.decode(actualRaw).numericValue,
                      let maximum = SMCValueDecoder.decode(maximumRaw).numericValue,
                      actual.isFinite,
                      maximum.isFinite,
                      actual >= 0,
                      maximum > 0,
                      maximum <= 20_000
                else {
                    throw TurboFanHardwareError.unsupportedHardware
                }

                return TurboFanDescriptor(
                    index: index,
                    modeKey: modeKey.rawValue,
                    maximumRPM: maximum,
                    baselineActualRPM: actual
                )
            }
        } catch let error as TurboFanHardwareError {
            throw error
        } catch {
            throw TurboFanHardwareError.readFailed
        }
    }

    func readMode(of fan: TurboFanDescriptor) throws -> TurboFanMode {
        do {
            let key = try validatedModeKey(for: fan)
            let raw = try reader.read(key)
            guard raw.metadata.dataType.rawValue == "ui8 ",
                  raw.metadata.dataSize == 1,
                  let value = raw.bytes.first,
                  let mode = TurboFanMode(appleSiliconSMCRawValue: value)
            else {
                throw TurboFanHardwareError.unsupportedHardware
            }
            return mode
        } catch let error as TurboFanHardwareError {
            throw error
        } catch {
            throw TurboFanHardwareError.readFailed
        }
    }

    func writeManualMode(to fan: TurboFanDescriptor) throws {
        try write(try validatedModeKey(for: fan), bytes: [1])
    }

    func writeAutomaticMode(to fan: TurboFanDescriptor) throws {
        try write(try validatedModeKey(for: fan), bytes: [0])
    }

    func writeMaximumTarget(to fan: TurboFanDescriptor) throws {
        do {
            let maximumKey = try requiredKey(index: fan.index, suffix: "Mx")
            let targetKey = try requiredKey(index: fan.index, suffix: "Tg")
            let maximum = try reader.read(maximumKey)
            let targetMetadata = try reader.metadata(for: targetKey)

            guard maximum.metadata.dataType.rawValue == "flt ",
                  maximum.metadata.dataSize == 4,
                  targetMetadata.dataType == maximum.metadata.dataType,
                  targetMetadata.dataSize == maximum.metadata.dataSize,
                  let liveMaximum = SMCValueDecoder.decode(maximum).numericValue,
                  liveMaximum.isFinite,
                  liveMaximum > 0,
                  abs(liveMaximum - fan.maximumRPM) <= 5
            else {
                throw TurboFanHardwareError.invalidData
            }
            try write(targetKey, bytes: maximum.bytes)
        } catch let error as TurboFanHardwareError {
            throw error
        } catch {
            throw TurboFanHardwareError.writeFailed
        }
    }

    func readTargetRPM(of fan: TurboFanDescriptor) throws -> Double {
        try readRPM(index: fan.index, suffix: "Tg")
    }

    func readActualRPM(of fan: TurboFanDescriptor) throws -> Double {
        try readRPM(index: fan.index, suffix: "Ac")
    }

    func readThermalManagerUnlock() throws -> Bool? {
        guard let key = SMCKey(rawValue: "Ftst") else {
            throw TurboFanHardwareError.invalidData
        }
        do {
            let raw = try reader.read(key)
            guard raw.metadata.dataType.rawValue == "ui8 ",
                  raw.metadata.dataSize == 1,
                  let value = raw.bytes.first,
                  value == 0 || value == 1
            else {
                throw TurboFanHardwareError.unsupportedHardware
            }
            return value == 1
        } catch let error as SMCReadError {
            if case let .controllerRejected(_, result, _) = error, result == 0x84 {
                return nil
            }
            throw TurboFanHardwareError.readFailed
        }
    }

    func writeThermalManagerUnlock(_ enabled: Bool) throws {
        guard let key = SMCKey(rawValue: "Ftst") else {
            throw TurboFanHardwareError.invalidData
        }
        do {
            let metadata = try reader.metadata(for: key)
            guard metadata.dataType.rawValue == "ui8 ", metadata.dataSize == 1 else {
                throw TurboFanHardwareError.unsupportedHardware
            }
            try write(key, bytes: [enabled ? 1 : 0])
        } catch let error as TurboFanHardwareError {
            throw error
        } catch {
            throw TurboFanHardwareError.writeFailed
        }
    }

    private func readRPM(index: Int, suffix: String) throws -> Double {
        do {
            let key = try requiredKey(index: index, suffix: suffix)
            let raw = try reader.read(key)
            guard raw.metadata.dataType.rawValue == "flt ",
                  raw.metadata.dataSize == 4,
                  let value = SMCValueDecoder.decode(raw).numericValue,
                  value.isFinite,
                  value >= 0,
                  value <= 20_000
            else {
                throw TurboFanHardwareError.invalidData
            }
            return value
        } catch let error as TurboFanHardwareError {
            throw error
        } catch {
            throw TurboFanHardwareError.readFailed
        }
    }

    private func resolvedModeKey(index: Int) throws -> SMCKey {
        for suffix in ["Md", "md"] {
            let key = try requiredKey(index: index, suffix: suffix)
            if let metadata = try? reader.metadata(for: key),
               metadata.dataType.rawValue == "ui8 ",
               metadata.dataSize == 1 {
                return key
            }
        }
        throw TurboFanHardwareError.unsupportedHardware
    }

    private func validatedModeKey(for fan: TurboFanDescriptor) throws -> SMCKey {
        guard fan.index >= 0, fan.index < Self.maximumFanCount else {
            throw TurboFanHardwareError.invalidData
        }
        let digit = String(fan.index, radix: 16, uppercase: true)
        guard fan.modeKey == "F\(digit)Md" || fan.modeKey == "F\(digit)md",
              let key = SMCKey(rawValue: fan.modeKey)
        else {
            throw TurboFanHardwareError.invalidData
        }
        return key
    }

    private func requiredKey(index: Int, suffix: String) throws -> SMCKey {
        guard index >= 0, index < Self.maximumFanCount else {
            throw TurboFanHardwareError.invalidData
        }
        let digit = String(index, radix: 16, uppercase: true)
        guard let key = SMCKey(rawValue: "F\(digit)\(suffix)") else {
            throw TurboFanHardwareError.invalidData
        }
        return key
    }

    private func write(_ key: SMCKey, bytes: [UInt8]) throws {
        let metadata: SMCKeyMetadata
        do {
            metadata = try reader.metadata(for: key)
        } catch {
            throw TurboFanHardwareError.writeFailed
        }
        guard metadata.dataSize == bytes.count, !bytes.isEmpty, bytes.count <= 32 else {
            throw TurboFanHardwareError.invalidData
        }

        var input = TPSMCParamStruct()
        input.key = Self.fourCharacterCode(key.rawValue)
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.data8 = Self.writeBytesCommand
        withUnsafeMutableBytes(of: &input.bytes) { destination in
            destination.copyBytes(from: bytes)
        }

        var output = TPSMCParamStruct()
        var outputSize = MemoryLayout<TPSMCParamStruct>.stride
        let callResult = IOConnectCallStructMethod(
            writeConnection,
            Self.userClientSelector,
            &input,
            MemoryLayout<TPSMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard callResult == kIOReturnSuccess else {
            throw TurboFanHardwareError.writeFailed
        }
        guard output.result == 0 else {
            if output.result == 0x82 {
                throw TurboFanHardwareError.thermalManagerBusy
            }
            throw TurboFanHardwareError.writeFailed
        }
    }

    private static func fourCharacterCode(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}

struct UnavailableTurboFanHardware: TurboFanHardware {
    func discoverFans() throws -> [TurboFanDescriptor] { throw TurboFanHardwareError.unavailable }
    func readMode(of fan: TurboFanDescriptor) throws -> TurboFanMode { throw TurboFanHardwareError.unavailable }
    func writeManualMode(to fan: TurboFanDescriptor) throws { throw TurboFanHardwareError.unavailable }
    func writeAutomaticMode(to fan: TurboFanDescriptor) throws { throw TurboFanHardwareError.unavailable }
    func writeMaximumTarget(to fan: TurboFanDescriptor) throws { throw TurboFanHardwareError.unavailable }
    func readTargetRPM(of fan: TurboFanDescriptor) throws -> Double { throw TurboFanHardwareError.unavailable }
    func readActualRPM(of fan: TurboFanDescriptor) throws -> Double { throw TurboFanHardwareError.unavailable }
    func readThermalManagerUnlock() throws -> Bool? { throw TurboFanHardwareError.unavailable }
    func writeThermalManagerUnlock(_ enabled: Bool) throws { throw TurboFanHardwareError.unavailable }
}
