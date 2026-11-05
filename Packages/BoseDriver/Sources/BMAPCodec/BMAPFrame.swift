/// The operator carried in the low nibble of a frame's flags byte.
public enum BMAPOperator: UInt8, Sendable, CaseIterable {
    case set = 0
    case get = 1
    case setGet = 2
    case status = 3
    case error = 4
    case start = 5
    case result = 6
    case processing = 7
}

/// A function within a function block, written `[fblock.function]` in the protocol notes.
public struct BMAPAddress: Sendable, Hashable, CustomStringConvertible {
    public var functionBlock: UInt8
    public var function: UInt8

    public init(functionBlock: UInt8, function: UInt8) {
        self.functionBlock = functionBlock
        self.function = function
    }

    public var description: String {
        "[\(functionBlock).\(function)]"
    }
}

/// One BMAP frame: `fblock, function, flags, payload_length, payload...`.
public struct BMAPFrame: Sendable, Equatable {
    public static let headerLength = 4
    public static let maximumPayloadLength = 255

    private static let operatorMask: UInt8 = 0x0F

    public let address: BMAPAddress
    /// The whole flags byte. The upper bits hold device and port numbers and are preserved.
    public let flags: UInt8
    public let payload: [UInt8]

    /// Fails if the payload doesn't fit the one-byte length field.
    public init(address: BMAPAddress, flags: UInt8, payload: [UInt8] = []) throws(BMAPCodecError) {
        guard payload.count <= Self.maximumPayloadLength else {
            throw .payloadTooLong(payload.count)
        }
        self.address = address
        self.flags = flags
        self.payload = payload
    }

    public init(address: BMAPAddress, operator op: BMAPOperator, payload: [UInt8] = []) throws(BMAPCodecError) {
        try self.init(address: address, flags: op.rawValue, payload: payload)
    }

    /// The raw low nibble, available even if the value isn't a known operator.
    public var operatorCode: UInt8 {
        flags & Self.operatorMask
    }

    /// `nil` if the device sent an operator this codec doesn't know.
    public var `operator`: BMAPOperator? {
        BMAPOperator(rawValue: operatorCode)
    }

    /// The reason given by an ERROR frame. `nil` for any other frame or an empty payload.
    public var errorCode: BMAPErrorCode? {
        guard `operator` == .error, let first = payload.first else { return nil }
        return BMAPErrorCode(rawValue: first) ?? .unrecognized
    }

    public func encoded() -> [UInt8] {
        [address.functionBlock, address.function, flags, UInt8(payload.count)] + payload
    }
}

public enum BMAPCodecError: Error, Sendable, Equatable {
    case payloadTooLong(Int)
}

/// Reasons reported in the first payload byte of an ERROR frame.
public enum BMAPErrorCode: UInt8, Sendable, CaseIterable {
    case unknown = 0
    case length = 1
    case checksum = 2
    case functionBlockNotSupported = 3
    case functionNotSupported = 4
    /// Also what a device answers when an operation needs manufacturer authentication.
    case operatorNotSupported = 5
    case invalidData = 6
    case dataUnavailable = 7
    case runtime = 8
    case timeout = 9
    case invalidState = 10
    case insecureTransport = 20
    /// Not a protocol value: stands in for any code missing from this list.
    case unrecognized = 255
}
