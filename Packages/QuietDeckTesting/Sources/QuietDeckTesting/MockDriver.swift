import QuietDeckCore
import TransportInterface

/// An in-memory driver for model tests and previews. It applies commands to its state.
public actor MockDriver: HeadphoneDriver {
    public static let descriptor = DriverDescriptor(id: "mock", displayName: "Mock")

    public static func match(_ device: DiscoveredDevice) -> DriverMatch? {
        device.name.hasPrefix("Mock") ? .name : nil
    }

    public nonisolated let events: AsyncStream<DeviceEvent>
    public nonisolated var rawConsole: (any RawFrameConsole)? { nil }

    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private var storedCapabilities: DeviceCapabilities
    private var state: DeviceState
    private var nextError: DriverError?

    public private(set) var performed: [DeviceCommand] = []
    public private(set) var isConnected = false

    public init(capabilities: DeviceCapabilities, state: DeviceState) {
        (events, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
        storedCapabilities = capabilities
        self.state = state
    }

    public init(device: DiscoveredDevice, transport: any ByteTransport) {
        self.init(capabilities: Fixtures.fullCapabilities, state: Fixtures.fullState)
    }

    public var capabilities: DeviceCapabilities {
        storedCapabilities
    }

    public func connect() async throws {
        try throwScriptedError()
        isConnected = true
        continuation.yield(.connectionChanged(.connected))
    }

    public func disconnect() async {
        isConnected = false
        continuation.yield(.connectionChanged(.disconnected))
    }

    public func refreshState() async throws -> DeviceState {
        guard isConnected else { throw DriverError.notConnected }
        try throwScriptedError()
        return state
    }

    public func perform(_ command: DeviceCommand) async throws {
        guard isConnected else { throw DriverError.notConnected }
        guard storedCapabilities.supports(command) else { throw DriverError.unsupported }
        try throwScriptedError()
        performed.append(command)
        apply(command)
        continuation.yield(.stateChanged(state))
    }

    /// Makes the next connect, refresh or command fail.
    public func failNext(with error: DriverError) {
        nextError = error
    }

    /// Simulates a change made on the device itself.
    public func simulateDeviceChange(_ change: @Sendable (inout DeviceState) -> Void) {
        change(&state)
        continuation.yield(.stateChanged(state))
    }

    /// Simulates a change the device doesn't report, like a button press on real hardware.
    public func simulateSilentChange(_ change: @Sendable (inout DeviceState) -> Void) {
        change(&state)
    }

    public func simulateConnection(_ connection: ConnectionState) {
        isConnected = connection == .connected
        continuation.yield(.connectionChanged(connection))
    }

    /// Simulates a driver learning that firmware can't do something after all.
    public func simulateCapabilityChange(_ capabilities: DeviceCapabilities) {
        storedCapabilities = capabilities
        continuation.yield(.capabilitiesChanged(capabilities))
    }

    private func throwScriptedError() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    private func apply(_ command: DeviceCommand) {
        switch command {
        case .setMode(let id):
            state.mode = .preset(id)
        case .setAudio(let noiseLevel, let spatial, let windBlock):
            state.noiseLevel = noiseLevel ?? state.noiseLevel
            state.spatialAudio = spatial ?? state.spatialAudio
            state.windBlock = windBlock ?? state.windBlock
            state.mode = .custom
        case .setEqualizerBand(let id, let value):
            var bands = state.equalizer ?? []
            bands.removeAll { $0.id == id }
            bands.append(EqualizerBandValue(id: id, value: value))
            state.equalizer = bands.sorted { $0.id < $1.id }
        case .setMultipoint(let enabled):
            state.multipoint = enabled
        case .switchSource(let id):
            guard let sources = state.sources?.sources else { return }
            state.sources = AudioSourceList(
                sources: sources.map { source in
                    var source = source
                    if source.id == id {
                        source.status = .active
                    } else if source.status == .active {
                        source.status = .connected
                    }
                    return source
                }
            )
        case .pausePlayback:
            break
        case .connectSource(let id):
            guard let sources = state.sources?.sources else { return }
            state.sources = AudioSourceList(
                sources: sources.map { source in
                    var source = source
                    if source.id == id {
                        source.status = .connected
                    }
                    return source
                },
                isConnecting: state.sources?.isConnecting ?? false
            )
        case .rename(let name):
            state.name = name
        }
    }
}
