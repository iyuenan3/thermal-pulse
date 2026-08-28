import Foundation

public enum SensorClassifier {
    public static func shouldSample(_ metadata: SMCKeyMetadata) -> Bool {
        metadata.key == .fanCount ||
            fanIndexAndKind(for: metadata.key) != nil ||
            isTemperatureCandidate(metadata)
    }

    public static func classify(_ rawValue: SMCRawValue) -> SensorReading {
        let decoded = SMCValueDecoder.decode(rawValue)
        let numericValue = decoded.numericValue

        if rawValue.key == .fanCount {
            return reading(
                rawValue,
                value: numericValue,
                kind: .metadata,
                unit: .count,
                evidence: .runtimeValidated,
                defaultVisible: false,
                displayName: "风扇数量",
                validRange: 0...16
            )
        }

        if let fan = fanIndexAndKind(for: rawValue.key) {
            let name = fan.isMaximum
                ? "风扇 \(fan.index + 1) 最大转速"
                : "风扇 \(fan.index + 1) 实际转速"
            return reading(
                rawValue,
                value: numericValue,
                kind: fan.isMaximum ? .fanMaximumSpeed : .fanActualSpeed,
                unit: .rpm,
                evidence: .runtimeValidated,
                defaultVisible: true,
                displayName: name,
                validRange: 0...30_000
            )
        }

        if isTemperatureCandidate(rawValue.metadata) {
            return reading(
                rawValue,
                value: numericValue,
                kind: .temperatureCandidate,
                unit: .celsius,
                evidence: .rawUnverified,
                defaultVisible: false,
                displayName: nil,
                validRange: -20...130
            )
        }

        let descriptor = SensorDescriptor(
            key: rawValue.key,
            kind: .raw,
            unit: .raw,
            evidence: .rawUnverified,
            defaultVisible: false,
            displayName: nil
        )
        return SensorReading(
            descriptor: descriptor,
            value: numericValue,
            validity: numericValue == nil ? .unavailable("未支持的数据类型") : .valid,
            dataType: rawValue.dataType
        )
    }

    private static func reading(
        _ rawValue: SMCRawValue,
        value: Double?,
        kind: SensorKind,
        unit: SensorUnit,
        evidence: SensorEvidence,
        defaultVisible: Bool,
        displayName: String?,
        validRange: ClosedRange<Double>
    ) -> SensorReading {
        let descriptor = SensorDescriptor(
            key: rawValue.key,
            kind: kind,
            unit: unit,
            evidence: evidence,
            defaultVisible: defaultVisible,
            displayName: displayName
        )

        guard let value, value.isFinite else {
            return SensorReading(
                descriptor: descriptor,
                value: nil,
                validity: .unavailable("无法解码为有限数值"),
                dataType: rawValue.dataType
            )
        }
        guard validRange.contains(value) else {
            return SensorReading(
                descriptor: descriptor,
                value: value,
                validity: .invalid("超出合理范围"),
                dataType: rawValue.dataType
            )
        }
        return SensorReading(
            descriptor: descriptor,
            value: value,
            validity: .valid,
            dataType: rawValue.dataType
        )
    }

    private static func isTemperatureCandidate(_ metadata: SMCKeyMetadata) -> Bool {
        metadata.key.rawValue.hasPrefix("T") && isTemperatureEncoding(metadata.dataType)
    }

    private static func isTemperatureEncoding(_ dataType: SMCDataType) -> Bool {
        let type = dataType.normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return type == "flt" || type.hasPrefix("sp") || type.hasPrefix("fp")
    }

    private static func fanIndexAndKind(for key: SMCKey) -> (index: Int, isMaximum: Bool)? {
        let characters = Array(key.rawValue)
        guard characters.count == 4,
              characters[0] == "F",
              let index = Int(String(characters[1]), radix: 16)
        else {
            return nil
        }

        let suffix = String(characters[2...3])
        switch suffix {
        case "Ac": return (index, false)
        case "Mx": return (index, true)
        default: return nil
        }
    }
}

