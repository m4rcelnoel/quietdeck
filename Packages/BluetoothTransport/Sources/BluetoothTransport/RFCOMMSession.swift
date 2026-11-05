import TransportInterface

/// A persistent connection that survives drops.
///
/// ```
/// idle -> opening -> open -> closing -> cooldown -> idle
///                     |
///                     +-- lost -> retry after each delay -> gave up
/// ```
///
/// The connection counts as up only because the channel is open and answering, never
/// because of what the system reports about the device.
public actor RFCOMMSession: ByteTransport {
    public struct Configuration: Sendable {
        public var openTimeout: Duration
        /// Reopening too soon after a close can leave the Bluetooth stack busy.
        public var cooldown: Duration
        public var reconnectDelays: [Duration]

        public init(
            openTimeout: Duration = .seconds(8),
            cooldown: Duration = .milliseconds(650),
            reconnectDelays: [Duration] = [.seconds(2), .seconds(10)]
        ) {
            self.openTimeout = openTimeout
            self.cooldown = cooldown
            self.reconnectDelays = reconnectDelays
        }
    }

    public nonisolated let incoming: AsyncStream<[UInt8]>
    public nonisolated let lifecycle: AsyncStream<TransportEvent>

    private let incomingContinuation: AsyncStream<[UInt8]>.Continuation
    private let lifecycleContinuation: AsyncStream<TransportEvent>.Continuation
    private let makeLink: @Sendable () -> any RFCOMMLink
    private let configuration: Configuration
    private let clock = ContinuousClock()

    private var link: (any RFCOMMLink)?
    /// Identifies the current link, so events from an old one are ignored.
    private var generation = 0
    private var openTask: Task<Void, Error>?
    private var reconnectTask: Task<Void, Never>?
    private var cooldownEnd: ContinuousClock.Instant?
    /// True from `open()` until `close()`. Reconnection only happens while this is set.
    private var wantsConnection = false

    public init(
        configuration: Configuration = Configuration(),
        makeLink: @escaping @Sendable () -> any RFCOMMLink
    ) {
        self.configuration = configuration
        self.makeLink = makeLink
        (incoming, incomingContinuation) = AsyncStream.makeStream(of: [UInt8].self)
        (lifecycle, lifecycleContinuation) = AsyncStream.makeStream(of: TransportEvent.self)
    }

    deinit {
        incomingContinuation.finish()
        lifecycleContinuation.finish()
    }

    public func open() async throws {
        wantsConnection = true
        try await establish()
    }

    public func close() async {
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil

        guard let current = link else { return }
        link = nil
        generation += 1
        await current.close()
        beginCooldown()
        lifecycleContinuation.yield(.closed)
    }

    public func send(_ bytes: [UInt8]) async throws {
        guard let link else { throw TransportError.notOpen }
        try await link.write(bytes)
    }

    /// Tells the session its device just appeared, for example after a power cycle.
    public func deviceAppeared() {
        guard wantsConnection, link == nil, openTask == nil else { return }
        startReconnecting()
    }

    private func establish() async throws {
        if link != nil { return }
        if let openTask {
            try await openTask.value
            return
        }
        let task = Task { try await self.performOpen() }
        openTask = task
        defer { openTask = nil }
        try await task.value
    }

    private func performOpen() async throws {
        if let cooldownEnd {
            try await clock.sleep(until: cooldownEnd)
        }

        let candidate = makeLink()
        try await open(candidate)

        guard wantsConnection else {
            await candidate.close()
            beginCooldown()
            throw TransportError.closed
        }

        generation += 1
        let current = generation
        link = candidate
        lifecycleContinuation.yield(.opened)
        Task { await self.pump(candidate, generation: current) }
    }

    private func open(_ candidate: any RFCOMMLink) async throws {
        // Closing a link fails its pending open, which is what ends the wait on timeout.
        let timeout = configuration.openTimeout
        let timer = Task {
            try await Task.sleep(for: timeout)
            await candidate.close()
        }
        do {
            try await candidate.open()
            timer.cancel()
        } catch {
            timer.cancel()
            let timedOut = (try? await timer.value) != nil
            await candidate.close()
            beginCooldown()
            throw timedOut ? TransportError.openTimedOut : error
        }
    }

    private func pump(_ source: any RFCOMMLink, generation pumped: Int) async {
        for await event in source.events {
            if case .data(let bytes) = event, pumped == generation {
                incomingContinuation.yield(bytes)
            }
        }
        await linkEnded(generation: pumped)
    }

    private func linkEnded(generation ended: Int) async {
        guard ended == generation, let current = link else { return }
        link = nil
        await current.close()
        beginCooldown()
        lifecycleContinuation.yield(.lost)
        if wantsConnection {
            startReconnecting()
        }
    }

    private func startReconnecting() {
        reconnectTask?.cancel()
        reconnectTask = Task { await self.reconnect() }
    }

    private func reconnect() async {
        for delay in configuration.reconnectDelays {
            do {
                try await Task.sleep(for: delay)
                try await establish()
                return
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
        if !Task.isCancelled {
            lifecycleContinuation.yield(.gaveUp)
        }
    }

    private func beginCooldown() {
        cooldownEnd = clock.now.advanced(by: configuration.cooldown)
    }
}
