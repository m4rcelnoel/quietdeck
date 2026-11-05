import Foundation
import Observation

/// The state of one device, shared by the menu bar panel and the main window.
///
/// Every control has two values: what the device last confirmed, and what the user just
/// asked for. `state` shows the request while it's pending. If the command fails, the
/// request is dropped, so the control falls back to the confirmed value by itself.
@MainActor
@Observable
public final class DeviceController {
    public enum Phase: Sendable, Equatable {
        case connecting
        case connected
        case disconnected
        /// Usually another app holds the control channel.
        case connectionFailed
    }

    public enum Control: Sendable, Equatable {
        case mode, noiseLevel, spatialAudio, windBlock, equalizer, multipoint, source, connection
    }

    public struct Problem: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// Trying again may work.
            case failed
            /// This firmware doesn't allow it. Trying again won't help.
            case notAvailable
        }

        public var control: Control
        public var kind: Kind

        public init(control: Control, kind: Kind) {
            self.control = control
            self.kind = kind
        }
    }

    private struct Requests {
        var mode: ListeningModeSelection?
        var noiseLevel: Int?
        var spatialAudio: SpatialAudioMode?
        var windBlock: Bool?
        var equalizer: [EqualizerBand.ID: Int] = [:]
        var multipoint: Bool?

        var isEmpty: Bool {
            mode == nil && noiseLevel == nil && spatialAudio == nil && windBlock == nil
                && equalizer.isEmpty && multipoint == nil
        }
    }

    /// Receives a line for each step, for diagnosing problems.
    public var trace: (@MainActor (String) -> Void)?

    /// Called with each new battery reading.
    public var onBatteryReading: (@MainActor (Int) -> Void)?
    /// Called whenever the connection phase changes.
    public var onPhaseChange: (@MainActor (Phase) -> Void)?

    public private(set) var phase: Phase = .disconnected {
        didSet {
            if phase != oldValue {
                onPhaseChange?(phase)
            }
        }
    }
    public private(set) var capabilities: DeviceCapabilities
    public private(set) var problem: Problem?
    /// The source that is this computer, if known.
    public var localSourceID: AudioSource.ID?
    /// Plays silence here, which is how this computer takes over from another source.
    public var localStream: (any LocalAudioStream)?
    /// The source a connection attempt is running for.
    public private(set) var connectingSource: AudioSource.ID?
    /// The source a switch is in progress for.
    public private(set) var switchingSource: AudioSource.ID?

    private var confirmed = DeviceState() {
        didSet {
            if let percent = confirmed.battery?.percent, percent != oldValue.battery?.percent {
                onBatteryReading?(percent)
            }
        }
    }
    private var requests = Requests()

    private let driver: any HeadphoneDriver
    private let refreshInterval: Duration
    private let takeoverPause: Duration
    private let takeoverAttempts = 6
    private let connectPollInterval: Duration
    private let connectAttempts = 20
    private let schedulerConfiguration: CommandScheduler.Configuration
    @ObservationIgnored private lazy var scheduler = CommandScheduler(configuration: schedulerConfiguration) {
        [weak self] command in
        await self?.execute(command)
    }
    private var listener: Task<Void, Never>?
    private var poller: Task<Void, Never>?
    private var isRefreshing = false

    /// - Parameter refreshInterval: Changes made on the device aren't reported, so the
    ///   state is read again this often.
    public init(
        driver: any HeadphoneDriver,
        schedulerConfiguration: CommandScheduler.Configuration = .init(),
        refreshInterval: Duration = .seconds(30),
        takeoverPause: Duration = .milliseconds(500),
        connectPollInterval: Duration = .seconds(1)
    ) {
        self.driver = driver
        self.refreshInterval = refreshInterval
        self.takeoverPause = takeoverPause
        self.connectPollInterval = connectPollInterval
        self.schedulerConfiguration = schedulerConfiguration
        capabilities = DeviceCapabilities()
    }

    /// The values to show: confirmed values with pending requests on top.
    public var state: DeviceState {
        var result = confirmed
        result.mode = requests.mode ?? result.mode
        result.noiseLevel = requests.noiseLevel ?? result.noiseLevel
        result.spatialAudio = requests.spatialAudio ?? result.spatialAudio
        result.windBlock = requests.windBlock ?? result.windBlock
        result.multipoint = requests.multipoint ?? result.multipoint
        if !requests.equalizer.isEmpty {
            result.equalizer = result.equalizer?.map { band in
                EqualizerBandValue(id: band.id, value: requests.equalizer[band.id] ?? band.value)
            }
        }
        return result
    }

    /// Wind Block masks noise control, so the level has no audible effect while it's on.
    public var isNoiseControlMasked: Bool {
        state.windBlock == true
    }

    public var rawConsole: (any RawFrameConsole)? {
        driver.rawConsole
    }

    public func connect() async {
        startListening()
        capabilities = await driver.capabilities
        phase = .connecting
        do {
            try await driver.connect()
            phase = .connected
            await refresh()
            startPolling()
        } catch {
            phase = .connectionFailed
        }
    }

    public func disconnect() async {
        stopPolling()
        discardPendingWork()
        await driver.disconnect()
        phase = .disconnected
    }

    /// Reads the device again. Skipped while the user is changing something, because the
    /// answer could briefly undo what's on screen.
    public func refresh() async {
        guard phase == .connected, !isRefreshing, requests.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let state = try? await driver.refreshState(), requests.isEmpty {
            confirmed = state
        }
    }

    public func selectMode(_ id: ListeningMode.ID) {
        requests.mode = .preset(id)
        // The device applies the mode's own values, which arrive with its answer.
        requests.noiseLevel = nil
        requests.spatialAudio = nil
        requests.windBlock = nil
        submit(.setMode(id))
    }

    public func setNoiseLevel(_ level: Int) {
        requests.noiseLevel = level
        requests.mode = .custom
        submit(.setAudio(noiseLevel: level, spatial: nil, windBlock: nil))
    }

    public func setSpatialAudio(_ mode: SpatialAudioMode) {
        requests.spatialAudio = mode
        requests.mode = .custom
        submit(.setAudio(noiseLevel: nil, spatial: mode, windBlock: nil))
    }

    public func setWindBlock(_ enabled: Bool) {
        requests.windBlock = enabled
        requests.mode = .custom
        submit(.setAudio(noiseLevel: nil, spatial: nil, windBlock: enabled))
    }

    public func setEqualizerBand(_ id: EqualizerBand.ID, value: Int) {
        requests.equalizer[id] = value
        submit(.setEqualizerBand(id: id, value: value))
    }

    public func setMultipoint(_ enabled: Bool) {
        requests.multipoint = enabled
        submit(.setMultipoint(enabled))
    }

    public func switchSource(to id: AudioSource.ID) {
        switchingSource = id
        submit(.switchSource(id))
    }

    /// Moves audio from the active source to this computer.
    ///
    /// Headphones keep a source that is playing, and hand over to a new stream once the
    /// line is free. So the source is paused through the headphones, then a stream starts
    /// here. The routing command isn't used, because it failed in every hardware test.
    public func bringAudioHere() async {
        guard let local = localSourceID, let localStream, switchingSource == nil else { return }
        trace?("bring audio here")
        problem = nil
        switchingSource = local
        defer { switchingSource = nil }

        do {
            try await driver.perform(.pausePlayback)
        } catch DriverError.rejected {
            // Nothing is playing, so the line is already free.
        } catch {
            trace?("pause failed: \(error)")
            problem = Problem(control: .source, kind: .failed)
            return
        }
        try? await Task.sleep(for: takeoverPause)

        await localStream.start()
        let arrived = await waitUntilActive(local)
        await localStream.stop()
        trace?("bring audio here finished: \(arrived)")
        if !arrived {
            problem = Problem(control: .source, kind: .failed)
        }
    }

    /// Asks the headphones to connect a remembered device, and waits for the outcome.
    /// With two devices connected already, the headphones drop one to make room.
    public func connectSource(_ id: AudioSource.ID) async {
        guard connectingSource == nil else { return }
        trace?("connect source")
        problem = nil
        connectingSource = id
        defer { connectingSource = nil }

        do {
            try await driver.perform(.connectSource(id))
        } catch DriverError.rejected {
            // The attempt can still be running, so the outcome below decides.
        } catch {
            trace?("connect failed: \(error)")
            problem = Problem(control: .connection, kind: .failed)
            return
        }

        for _ in 0..<connectAttempts {
            try? await Task.sleep(for: connectPollInterval)
            guard let state = try? await driver.refreshState() else { continue }
            confirmed = state
            if state.sources?.isConnecting == false {
                break
            }
        }
        let source = confirmed.sources?.sources.first { $0.id == id }
        trace?("connect finished: \(String(describing: source?.status))")
        if source == nil || source?.status == .remembered {
            problem = Problem(control: .connection, kind: .failed)
        }
    }

    private func waitUntilActive(_ id: AudioSource.ID) async -> Bool {
        for _ in 0..<takeoverAttempts {
            if let state = try? await driver.refreshState() {
                confirmed = state
                if state.sources?.active?.id == id { return true }
            }
            try? await Task.sleep(for: takeoverPause)
        }
        return false
    }

    private func submit(_ command: DeviceCommand) {
        trace?("submit \(command) phase \(phase)")
        problem = nil
        scheduler.submit(command)
    }

    private func execute(_ command: DeviceCommand) async {
        do {
            try await driver.perform(command)
            trace?("done \(command)")
            settle(command)
        } catch {
            trace?("failed \(command): \(error)")
            reject(command, error: error)
        }
    }

    /// Moves a successful request into the confirmed values, so nothing flickers while
    /// the device's own report is on its way.
    private func settle(_ command: DeviceCommand) {
        switch command {
        case .setMode(let id):
            confirmed.mode = .preset(id)
            requests.mode = nil
        case .setAudio(let noiseLevel, let spatial, let windBlock):
            confirmed.noiseLevel = noiseLevel ?? confirmed.noiseLevel
            confirmed.spatialAudio = spatial ?? confirmed.spatialAudio
            confirmed.windBlock = windBlock ?? confirmed.windBlock
            confirmed.mode = .custom
            requests.noiseLevel = nil
            requests.spatialAudio = nil
            requests.windBlock = nil
            requests.mode = nil
        case .setEqualizerBand(let id, let value):
            confirmed.equalizer = confirmed.equalizer?.map { band in
                band.id == id ? EqualizerBandValue(id: id, value: value) : band
            }
            requests.equalizer[id] = nil
        case .setMultipoint(let enabled):
            confirmed.multipoint = enabled
            requests.multipoint = nil
        case .switchSource:
            switchingSource = nil
        case .pausePlayback, .connectSource:
            break
        case .rename(let name):
            confirmed.name = name
        }
    }

    private func reject(_ command: DeviceCommand, error: Error) {
        let control: Control
        switch command {
        case .setMode:
            control = .mode
            requests.mode = nil
        case .setAudio(let noiseLevel, let spatial, _):
            control = noiseLevel != nil ? .noiseLevel : spatial != nil ? .spatialAudio : .windBlock
            requests.noiseLevel = nil
            requests.spatialAudio = nil
            requests.windBlock = nil
            requests.mode = nil
        case .setEqualizerBand(let id, _):
            control = .equalizer
            requests.equalizer[id] = nil
        case .setMultipoint:
            control = .multipoint
            requests.multipoint = nil
        case .switchSource:
            control = .source
            switchingSource = nil
        case .pausePlayback, .connectSource, .rename:
            return
        }
        let unavailable = error as? DriverError == .authenticationRequired
        problem = Problem(control: control, kind: unavailable ? .notAvailable : .failed)
    }

    private func startListening() {
        guard listener == nil else { return }
        let events = driver.events
        listener = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: DeviceEvent) async {
        switch event {
        case .stateChanged(let state):
            confirmed = state
        case .capabilitiesChanged(let capabilities):
            self.capabilities = capabilities
        case .connectionChanged(.connected):
            trace?("connection connected")
            let wasReconnecting = phase != .connected
            phase = .connected
            // A device that was off at launch connects here, without `connect()` finishing.
            startPolling()
            if wasReconnecting {
                await refresh()
            }
        case .connectionChanged(.connecting):
            trace?("connection lost")
            if phase == .connected {
                phase = .connecting
                discardPendingWork()
            }
        case .connectionChanged(.disconnected):
            trace?("connection disconnected")
            phase = .disconnected
            stopPolling()
            discardPendingWork()
        }
    }

    /// Forgets what wasn't sent. A pending request would otherwise block every refresh and
    /// keep showing a value the device never received.
    private func discardPendingWork() {
        scheduler.cancelAll()
        requests = Requests()
        switchingSource = nil
    }

    private func startPolling() {
        guard poller == nil else { return }
        let interval = refreshInterval
        poller = Task { [weak self] in
            while !Task.isCancelled {
                // The tolerance lets the system group this wake-up with others.
                try? await Task.sleep(for: interval, tolerance: interval / 10)
                await self?.refresh()
            }
        }
    }

    private func stopPolling() {
        poller?.cancel()
        poller = nil
    }
}
