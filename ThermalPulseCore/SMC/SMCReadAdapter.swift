import Foundation
import IOKit

public struct SMCKeyMetadata: Equatable, Sendable {
    public let key: SMCKey
    public let dataSize: Int
    public let dataType: SMCDataType
    public let attributes: UInt8

    public init(key: SMCKey, dataSize: Int, dataType: SMCDataType, attributes: UInt8) {
        self.key = key
        self.dataSize = dataSize
        self.dataType = dataType
        self.attributes = attributes
    }
}

public struct SMCRawValue: Equatable, Sendable {
    public let metadata: SMCKeyMetadata
    public let bytes: [UInt8]

    public var key: SMCKey { metadata.key }
    public var dataType: SMCDataType { metadata.dataType }

    public init(metadata: SMCKeyMetadata, bytes: [UInt8]) {
        self.metadata = metadata
        self.bytes = bytes
    }
}

public enum SMCReadError: Error, Equatable, LocalizedError, Sendable {
    case serviceUnavailable
    case openFailed(Int32)
    case callFailed(operation: String, code: Int32)
    case controllerRejected(operation: String, result: UInt8, status: UInt8)
    case invalidDataSize(key: SMCKey, size: UInt32)
    case invalidKeyCount(UInt64)

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            "找不到 AppleSMC 服务"
        case let .openFailed(code):
            "无法以只读客户端打开 AppleSMC，IOReturn=\(code)"
        case let .callFailed(operation, code):
            "AppleSMC \(operation) 调用失败，IOReturn=\(code)"
        case let .controllerRejected(operation, result, status):
            "AppleSMC 拒绝 \(operation)，result=\(result)，status=\(status)"
        case let .invalidDataSize(key, size):
            "SMC key \(key) 返回无效长度 \(size)"
        case let .invalidKeyCount(count):
            "SMC key 数量不可信：\(count)"
        }
    }
}

public final class SMCReadAdapter {
    private var connection: io_connect_t

    public static var parameterStructSize: Int {
        MemoryLayout<TPSMCParamStruct>.stride
    }

    public init() throws {
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw SMCReadError.serviceUnavailable
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            throw SMCReadError.serviceUnavailable
        }
        defer { IOObjectRelease(service) }

        var openedConnection: io_connect_t = IO_OBJECT_NULL
        let result = IOServiceOpen(service, mach_task_self_, 0, &openedConnection)
        guard result == kIOReturnSuccess else {
            throw SMCReadError.openFailed(result)
        }
        connection = openedConnection
    }

    deinit {
        if connection != IO_OBJECT_NULL {
            IOServiceClose(connection)
        }
    }

    public func metadata(for key: SMCKey) throws -> SMCKeyMetadata {
        var input = TPSMCParamStruct()
        input.key = key.code
        input.data8 = SMCReadCommand.readKeyInfo.rawValue
        let output = try call(input, operation: "read-key-info \(key)")
        try validateController(output, operation: "read-key-info \(key)")

        let size = output.keyInfo.dataSize
        guard size > 0, size <= maximumSMCDataSize else {
            throw SMCReadError.invalidDataSize(key: key, size: size)
        }

        return SMCKeyMetadata(
            key: key,
            dataSize: Int(size),
            dataType: SMCDataType(code: output.keyInfo.dataType),
            attributes: output.keyInfo.dataAttributes
        )
    }

    public func read(_ key: SMCKey) throws -> SMCRawValue {
        let keyMetadata = try metadata(for: key)

        return try read(keyMetadata)
    }

    public func read(_ keyMetadata: SMCKeyMetadata) throws -> SMCRawValue {
        let key = keyMetadata.key

        var input = TPSMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(keyMetadata.dataSize)
        input.data8 = SMCReadCommand.readBytes.rawValue
        var output = try call(input, operation: "read-bytes \(key)")
        try validateController(output, operation: "read-bytes \(key)")

        let bytes = withUnsafeBytes(of: &output.bytes) { buffer in
            Array(buffer.prefix(keyMetadata.dataSize))
        }
        return SMCRawValue(metadata: keyMetadata, bytes: bytes)
    }

    public func keyCount() throws -> Int {
        let rawValue = try read(.keyCount)
        let decoded = SMCValueDecoder.decode(rawValue)
        let count: UInt64
        switch decoded {
        case let .unsigned(value):
            count = value
        default:
            count = rawValue.bytes.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }

        guard count > 0, count <= 16_384 else {
            throw SMCReadError.invalidKeyCount(count)
        }
        return Int(count)
    }

    public func enumerateKeys() throws -> [SMCKey] {
        let count = try keyCount()
        return try (0..<count).map(key(at:))
    }

    private func key(at index: Int) throws -> SMCKey {
        var input = TPSMCParamStruct()
        input.data8 = SMCReadCommand.readIndex.rawValue
        input.data32 = UInt32(index)
        let output = try call(input, operation: "read-index \(index)")
        try validateController(output, operation: "read-index \(index)")
        return SMCKey(code: output.key)
    }

    private func call(_ inputValue: TPSMCParamStruct, operation: String) throws -> TPSMCParamStruct {
        var input = inputValue
        var output = TPSMCParamStruct()
        var outputSize = MemoryLayout<TPSMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            smcUserClientSelector,
            &input,
            MemoryLayout<TPSMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else {
            throw SMCReadError.callFailed(operation: operation, code: result)
        }
        return output
    }

    private func validateController(_ output: TPSMCParamStruct, operation: String) throws {
        guard output.result == 0 else {
            throw SMCReadError.controllerRejected(
                operation: operation,
                result: output.result,
                status: output.status
            )
        }
    }
}
