import BMAPCodec
import QuietDeckCore

/// Decides which raw frames the Protocol Console may send.
///
/// This is a safety boundary, not a convenience. Authentication functions stay off
/// limits even for reading, because QuietDeck never touches manufacturer keys.
public enum BoseFramePolicy {
    private static let authenticationBlock: UInt8 = 18
    private static let firmwareUpdateBlock: UInt8 = 3
    private static let debugBlock: UInt8 = 8

    private static let destructive: Set<BMAPAddress> = [
        BMAPAddress(functionBlock: 4, function: 3),  // Remove device
        BMAPAddress(functionBlock: 4, function: 7),  // Clear device list
        BMAPAddress(functionBlock: 31, function: 9),  // Reset modes
    ]

    private static let knownSafeWrites: Set<BMAPAddress> = [
        BMAPAddress(functionBlock: 31, function: 3),  // Current mode
        BMAPAddress(functionBlock: 31, function: 10),  // Audio settings
        BMAPAddress(functionBlock: 1, function: 7),  // Equalizer
    ]

    private static let disruptive: [BMAPAddress: String] = [
        BMAPAddress(functionBlock: 7, function: 4): "This can power off the headphones.",
        BMAPAddress(functionBlock: 4, function: 8): "This changes pairing mode.",
        BMAPAddress(functionBlock: 4, function: 2): "This disconnects a device.",
    ]

    public static func evaluate(_ bytes: [UInt8]) -> RawFrameVerdict {
        guard let frame = singleFrame(in: bytes) else {
            return .deny(reason: "Not exactly one well-formed frame.")
        }
        return evaluate(frame)
    }

    public static func evaluate(_ frame: BMAPFrame) -> RawFrameVerdict {
        let address = frame.address
        switch address.functionBlock {
        case authenticationBlock:
            return .deny(reason: "Authentication functions are never accessed.")
        case firmwareUpdateBlock:
            return .deny(reason: "Firmware update functions are never accessed.")
        case debugBlock:
            return .deny(reason: "Debug functions are never accessed.")
        default:
            break
        }
        if destructive.contains(address) {
            return .deny(reason: "This function can erase data on the device.")
        }

        switch frame.operator {
        case .get:
            return .allow
        case .start, .setGet:
            if knownSafeWrites.contains(address) {
                return .allow
            }
            let reason = disruptive[address] ?? "This function's effect on the device isn't verified."
            return .confirm(reason: reason)
        case .set:
            return .deny(reason: "Pure SET needs manufacturer authentication.")
        case .status, .error, .result, .processing, nil:
            return .deny(reason: "Only GET, START and SETGET can be sent.")
        }
    }

    /// Parses bytes that must form one complete frame with nothing left over.
    static func singleFrame(in bytes: [UInt8]) -> BMAPFrame? {
        var decoder = BMAPFrameDecoder()
        let frames = decoder.append(bytes)
        guard frames.count == 1, decoder.pendingByteCount == 0 else { return nil }
        return frames[0]
    }
}
