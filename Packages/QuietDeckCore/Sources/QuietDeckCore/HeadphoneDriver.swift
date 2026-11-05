import TransportInterface

/// What is known about a device before any driver talks to it.
public struct DiscoveredDevice: Sendable, Equatable {
    public var name: String
    public var address: String
    public var vendorID: UInt16?
    public var productID: UInt16?
    public var serviceUUIDs: Set<String>

    public init(
        name: String,
        address: String,
        vendorID: UInt16? = nil,
        productID: UInt16? = nil,
        serviceUUIDs: Set<String> = []
    ) {
        self.name = name
        self.address = address
        self.vendorID = vendorID
        self.productID = productID
        self.serviceUUIDs = serviceUUIDs
    }
}

public struct DriverDescriptor: Sendable, Equatable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// How specifically a driver recognizes a device. Later cases win.
public enum DriverMatch: Int, Sendable, Comparable {
    case name
    case serviceUUID
    case vendorAndProduct

    public static func < (lhs: DriverMatch, rhs: DriverMatch) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A vendor driver. Adding a brand means adding one type that conforms to this.
public protocol HeadphoneDriver: Sendable {
    static var descriptor: DriverDescriptor { get }

    /// Returns how well this driver fits the device, or `nil` if it doesn't.
    static func match(_ device: DiscoveredDevice) -> DriverMatch?

    init(device: DiscoveredDevice, transport: any ByteTransport)

    /// Asynchronous so a driver can refine it after reading the device.
    var capabilities: DeviceCapabilities { get async }
    var events: AsyncStream<DeviceEvent> { get }

    func connect() async throws
    func disconnect() async
    func refreshState() async throws -> DeviceState
    func perform(_ command: DeviceCommand) async throws

    /// Developer access to raw frames, or `nil` if the driver offers none.
    var rawConsole: (any RawFrameConsole)? { get }
}

/// Developer tooling for a driver's wire protocol.
public protocol RawFrameConsole: Sendable {
    var composer: FrameComposerSpec { get }
    var traffic: AsyncStream<FrameLogEntry> { get }

    /// Decides what may be sent. Must deny by default for authentication,
    /// firmware and destructive functions.
    func evaluate(_ frame: RawFrame) -> RawFrameVerdict
    func send(_ frame: RawFrame) async throws

    /// Builds a frame from composer values keyed by field ID, or `nil` if they're invalid.
    func frame(from values: [String: String]) -> RawFrame?

    /// Removes device addresses and names, for logs that leave this Mac.
    func redacted(_ entry: FrameLogEntry) -> FrameLogEntry
}

public struct RawFrame: Sendable, Equatable {
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}

public enum RawFrameVerdict: Sendable, Equatable {
    case allow
    case confirm(reason: String)
    case deny(reason: String)
}

public struct FrameComposerSpec: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public var id: String
        public var label: String
        public var choices: [String]?

        public init(id: String, label: String, choices: [String]? = nil) {
            self.id = id
            self.label = label
            self.choices = choices
        }
    }

    public var fields: [Field]

    public init(fields: [Field]) {
        self.fields = fields
    }
}

public struct FrameLogEntry: Sendable, Equatable {
    public enum Direction: Sendable, Equatable {
        case sent, received
    }

    public var secondsSinceSessionStart: Double
    public var direction: Direction
    public var bytes: [UInt8]
    public var summary: String

    public init(secondsSinceSessionStart: Double, direction: Direction, bytes: [UInt8], summary: String) {
        self.secondsSinceSessionStart = secondsSinceSessionStart
        self.direction = direction
        self.bytes = bytes
        self.summary = summary
    }
}
