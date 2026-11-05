import BMAPCodec
import QuietDeckCore
import TransportInterface

/// Driver for the QC Ultra Headphones (2nd Gen).
public actor BoseHeadphoneDriver: HeadphoneDriver {
    public static let descriptor = DriverDescriptor(
        id: "bose.qc-ultra-2",
        displayName: "QC Ultra Headphones (2nd Gen)"
    )

    public static func match(_ device: DiscoveredDevice) -> DriverMatch? {
        if device.productID == BoseDevices.qcUltra2ProductID {
            return .vendorAndProduct
        }
        return device.name.hasPrefix("Bose QC Ultra 2") ? .name : nil
    }

    /// Rename stays out until it has been verified on hardware.
    private static let allCapabilities = DeviceCapabilities(
        listeningModes: ListeningModesCapability(modes: BoseStateCodec.modes),
        noiseControl: LevelCapability(range: BoseStateCodec.noiseLevels),
        spatialAudio: OptionsCapability(options: SpatialAudioMode.allCases),
        windBlock: ToggleCapability(),
        equalizer: EqualizerCapability(bands: BoseStateCodec.bands, range: -10...10),
        battery: BatteryCapability(reportsCharging: false),
        // The routing command never succeeded on hardware, so sources can't be switched
        // from here. `DeviceController.bringAudioHere` moves audio to this Mac instead.
        audioSources: AudioSourcesCapability(canSwitch: false, listsRememberedDevices: true, canConnect: true),
        multipoint: ToggleCapability()
    )

    public nonisolated let events: AsyncStream<DeviceEvent>
    public nonisolated let client: BMAPClient
    public nonisolated var rawConsole: (any RawFrameConsole)? { console }

    private nonisolated let console: BoseRawConsole
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let transport: any ByteTransport

    private var storedCapabilities = BoseHeadphoneDriver.allCapabilities
    private var state = DeviceState()
    private var audio: BoseAudioSettings?
    private var listeners: [Task<Void, Never>] = []

    public init(device: DiscoveredDevice, transport: any ByteTransport) {
        self.transport = transport
        client = BMAPClient(transport: transport)
        console = BoseRawConsole(client: client)
        (events, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
    }

    public var capabilities: DeviceCapabilities {
        storedCapabilities
    }

    public func connect() async throws {
        await client.start()
        if listeners.isEmpty {
            startListening()
        }
        do {
            try await transport.open()
        } catch let error as TransportError {
            throw DriverError.transportFailed(String(describing: error))
        }
    }

    public func disconnect() async {
        await transport.close()
    }

    /// Reads everything. A function the device refuses is left unread, not fatal.
    public func refreshState() async throws -> DeviceState {
        var next = DeviceState()
        next.name = BoseStateCodec.name(try await read(BoseAddress.productName) ?? [])
        next.firmwareVersion = BoseStateCodec.firmware(try await read(BoseAddress.firmware) ?? [])
        next.battery = (try await read(BoseAddress.batteryLevel))
            .flatMap(BoseStateCodec.batteryPercent)
            .map { BatteryStatus(percent: $0) }
        next.mode = (try await read(BoseAddress.currentMode)).flatMap(BoseStateCodec.mode)
        next.equalizer = (try await read(BoseAddress.equalizer)).flatMap(BoseStateCodec.equalizer)
        next.multipoint = (try await read(BoseAddress.multipoint)).flatMap(BoseStateCodec.multipoint)
        next.sources = try await readSources()

        audio = (try await read(BoseAddress.audioSettings)).flatMap(BoseStateCodec.audioSettings)
        apply(audio, to: &next)

        state = next
        return next
    }

    public func perform(_ command: DeviceCommand) async throws {
        guard storedCapabilities.supports(command) else { throw DriverError.unsupported }
        do {
            try await execute(command)
        } catch DriverError.authenticationRequired {
            remove(capabilityFor: command)
            throw DriverError.authenticationRequired
        }
        continuation.yield(.stateChanged(state))
    }

    private func execute(_ command: DeviceCommand) async throws {
        switch command {
        case .setMode(let id):
            guard let index = BoseStateCodec.modeIndex(for: id) else { throw DriverError.unsupported }
            let response = try await request(BoseAddress.currentMode, .start, [index, 0])
            state.mode = BoseStateCodec.mode(response.payload) ?? .preset(id)
            // The device applies the mode's settings itself, so ask what they are.
            audio = (try await read(BoseAddress.audioSettings)).flatMap(BoseStateCodec.audioSettings)
            apply(audio, to: &state)

        case .setAudio(let noiseLevel, let spatial, let windBlock):
            if audio == nil {
                audio = (try await read(BoseAddress.audioSettings)).flatMap(BoseStateCodec.audioSettings)
            }
            guard var settings = audio else { throw DriverError.malformedResponse }
            if let noiseLevel {
                settings.cnc = BoseStateCodec.cnc(forNoiseLevel: noiseLevel)
            }
            if let spatial {
                settings.spatial = BoseStateCodec.spatialByte(spatial)
            }
            if let windBlock {
                settings.wind = windBlock ? 1 : 0
            }
            let response = try await request(BoseAddress.audioSettings, .setGet, settings.payload)
            guard let confirmed = BoseStateCodec.audioSettings(response.payload) else {
                throw DriverError.malformedResponse
            }
            audio = confirmed
            apply(confirmed, to: &state)
            state.mode = (try await read(BoseAddress.currentMode)).flatMap(BoseStateCodec.mode) ?? .custom

        case .setEqualizerBand(let id, let value):
            let payload = BoseStateCodec.equalizerPayload(band: id, value: value)
            let response = try await request(BoseAddress.equalizer, .setGet, payload)
            guard let bands = BoseStateCodec.equalizer(response.payload) else {
                throw DriverError.malformedResponse
            }
            state.equalizer = bands

        case .setMultipoint(let enabled):
            let response = try await request(BoseAddress.multipoint, .setGet, [enabled ? 1 : 0])
            guard let confirmed = BoseStateCodec.multipoint(response.payload) else {
                throw DriverError.malformedResponse
            }
            state.multipoint = confirmed
            state.sources = try await readSources()

        case .switchSource:
            throw DriverError.unsupported

        case .connectSource(let id):
            guard let address = BoseStateCodec.address(fromSourceID: id) else { throw DriverError.unsupported }
            // The result takes seconds and is only visible in the device list.
            _ = try await client.transact(
                BMAPFrame(address: BoseAddress.connectDevice, operator: .start, payload: [0] + address),
                acceptsProcessing: true
            )

        case .pausePlayback:
            // The device answers with an error if nothing is playing.
            _ = try await request(BoseAddress.audioControl, .start, [0x02])

        case .rename:
            throw DriverError.unsupported
        }
    }

    private func readSources() async throws -> AudioSourceList? {
        guard let list = try await read(BoseAddress.pairedDevices) else { return nil }
        var devices: [BoseDeviceInfo] = []
        for address in BoseStateCodec.addresses(inDeviceList: list) {
            if let payload = try await read(BoseAddress.deviceInfo, payload: address),
                let info = BoseStateCodec.deviceInfo(payload)
            {
                devices.append(info)
            }
        }
        let active = (try await read(BoseAddress.activeSource)).flatMap(BoseStateCodec.activeAddress)
        return BoseStateCodec.sourceList(
            devices: devices, activeAddress: active, isConnecting: BoseStateCodec.isConnecting(list)
        )
    }

    private func apply(_ settings: BoseAudioSettings?, to target: inout DeviceState) {
        guard let settings else { return }
        target.noiseLevel = BoseStateCodec.noiseLevel(settings)
        target.spatialAudio = BoseStateCodec.spatialMode(settings)
        target.windBlock = settings.wind != 0
    }

    /// Reads one function. Returns `nil` if the device refuses it or needs authentication.
    private func read(_ address: BMAPAddress, payload: [UInt8] = []) async throws -> [UInt8]? {
        do {
            return try await request(address, .get, payload).payload
        } catch DriverError.rejected, DriverError.authenticationRequired {
            return nil
        }
    }

    private func request(_ address: BMAPAddress, _ op: BMAPOperator, _ payload: [UInt8]) async throws -> BMAPFrame {
        try await client.transact(BMAPFrame(address: address, operator: op, payload: payload))
    }

    /// A firmware update can gate a feature. The UI then hides it instead of failing.
    private func remove(capabilityFor command: DeviceCommand) {
        switch command {
        case .setMultipoint:
            storedCapabilities.multipoint = nil
        case .switchSource:
            storedCapabilities.audioSources?.canSwitch = false
        case .setEqualizerBand:
            storedCapabilities.equalizer = nil
        case .setMode:
            storedCapabilities.listeningModes = nil
        case .setAudio(let noiseLevel, let spatial, let windBlock):
            if noiseLevel != nil { storedCapabilities.noiseControl = nil }
            if spatial != nil { storedCapabilities.spatialAudio = nil }
            if windBlock != nil { storedCapabilities.windBlock = nil }
        case .pausePlayback:
            storedCapabilities.audioSources = nil
        case .connectSource:
            storedCapabilities.audioSources?.canConnect = false
        case .rename:
            storedCapabilities.rename = nil
        }
        continuation.yield(.capabilitiesChanged(storedCapabilities))
    }

    private func startListening() {
        let client = client
        let continuation = continuation
        listeners = [
            Task {
                for await event in client.connectionEvents {
                    switch event {
                    case .opened:
                        continuation.yield(.connectionChanged(.connected))
                    case .lost:
                        continuation.yield(.connectionChanged(.connecting))
                    case .gaveUp, .closed:
                        continuation.yield(.connectionChanged(.disconnected))
                    }
                }
            },
            Task { [weak self] in
                for await frame in client.unsolicited {
                    await self?.handleUnsolicited(frame)
                }
            },
        ]
    }

    /// Applies changes the device reports by itself, such as a button press.
    private func handleUnsolicited(_ frame: BMAPFrame) {
        guard frame.operator == .status else { return }
        switch frame.address {
        case BoseAddress.currentMode:
            state.mode = BoseStateCodec.mode(frame.payload) ?? state.mode
        case BoseAddress.audioSettings:
            audio = BoseStateCodec.audioSettings(frame.payload) ?? audio
            apply(audio, to: &state)
        case BoseAddress.equalizer:
            state.equalizer = BoseStateCodec.equalizer(frame.payload) ?? state.equalizer
        case BoseAddress.batteryLevel:
            state.battery =
                BoseStateCodec.batteryPercent(frame.payload).map { BatteryStatus(percent: $0) } ?? state.battery
        case BoseAddress.multipoint:
            state.multipoint = BoseStateCodec.multipoint(frame.payload) ?? state.multipoint
        default:
            return
        }
        continuation.yield(.stateChanged(state))
    }
}
