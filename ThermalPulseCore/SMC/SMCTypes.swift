import Foundation

enum SMCReadCommand: UInt8, CaseIterable {
    case readBytes = 5
    case readIndex = 8
    case readKeyInfo = 9
}

let smcUserClientSelector: UInt32 = 2
let maximumSMCDataSize = 32
