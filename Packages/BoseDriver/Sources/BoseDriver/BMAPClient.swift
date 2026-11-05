import BMAPCodec
import QuietDeckCore
import TransportInterface

/// One frame seen on the wire.
public struct BMAPTraffic: Sendable, Equatable {
    public enum Direction: Sendable, Equatable {
        case sent, received
    }

    public var direction: Direction
    public var frame: BMAPFrame
}

/// Sends one BMAP request at a time and matches it to its response.
///
/// A frame that doesn't answer the current request goes to `unsolicited`, so the
/// device can report changes on its own without confusing a transaction.
public actor BMAPClient {
    public nonisolated let unsolicited: AsyncStream<BMAPFrame>
    /// Every frame sent or received, for developer tooling.
    public nonisolated let traffic: AsyncStream<BMAPTraffic>
    /// Connection changes, forwarded after the client has acted on them.
    public nonisolated let connectionEvents: AsyncStream<TransportEvent>

    private struct Pending {
        let id: Int
        let address: BMAPAddress
        let acceptsProcessing: Bool
        let continuation: CheckedContinuation<BMAPFrame, Error>
        let timer: Task<Void, Never>
    }

    private let unsolicitedContinuation: AsyncStream<BMAPFrame>.Continuation
    private let trafficContinuation: AsyncStream<BMAPTraffic>.Continuation
    private let connectionContinuation: AsyncStream<TransportEvent>.Continuation
    private let transport: any ByteTransport
    private let timeout: Duration
    private let queue = TransactionQueue()

    private var decoder = BMAPFrameDecoder()
    private var pending: Pending?
    private var nextID = 0
    private var listeners: [Task<Void, Never>] = []

    public init(transport: any ByteTransport, timeout: Duration = .seconds(8)) {
        self.transport = transport
        self.timeout = timeout
        (unsolicited, unsolicitedContinuation) = AsyncStream.makeStream(of: BMAPFrame.self)
        (traffic, trafficContinuation) = AsyncStream.makeStream(of: BMAPTraffic.self)
        (connectionEvents, connectionContinuation) = AsyncStream.makeStream(of: TransportEvent.self)
    }

    /// Begins listening to the transport. Call once, before opening it.
    public func start() {
        guard listeners.isEmpty else { return }
        let transport = transport
        listeners = [
            Task { [weak self] in
                for await bytes in transport.incoming {
                    await self?.receive(bytes)
                }
            },
            Task { [weak self] in
                for await event in transport.lifecycle {
                    await self?.handle(event)
                }
            },
        ]
    }

    public func stop() {
        for listener in listeners {
            listener.cancel()
        }
        listeners = []
        finishPending(with: .failure(DriverError.notConnected))
    }

    /// Runs one request-response exchange. Calls are served strictly in order.
    ///
    /// - Parameter acceptsProcessing: For slow actions, "started" counts as the answer,
    ///   because the outcome can take many seconds and may never be reported.
    public nonisolated func transact(_ request: BMAPFrame, acceptsProcessing: Bool = false) async throws -> BMAPFrame {
        try await queue.run {
            try await self.exchange(request, acceptsProcessing: acceptsProcessing)
        }
    }

    private func exchange(_ request: BMAPFrame, acceptsProcessing: Bool) async throws -> BMAPFrame {
        nextID += 1
        let id = nextID
        let timeout = timeout
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self?.finishPending(id: id, with: .failure(DriverError.timeout))
            }
            pending = Pending(
                id: id, address: request.address, acceptsProcessing: acceptsProcessing,
                continuation: continuation, timer: timer
            )
            trafficContinuation.yield(BMAPTraffic(direction: .sent, frame: request))

            let transport = transport
            Task { [weak self] in
                do {
                    try await transport.send(request.encoded())
                } catch {
                    await self?.finishPending(id: id, with: .failure(Self.driverError(for: error)))
                }
            }
        }
    }

    private func receive(_ bytes: [UInt8]) {
        for frame in decoder.append(bytes) {
            trafficContinuation.yield(BMAPTraffic(direction: .received, frame: frame))
            route(frame)
        }
    }

    private func route(_ frame: BMAPFrame) {
        guard pending?.address == frame.address else {
            unsolicitedContinuation.yield(frame)
            return
        }
        switch frame.operator {
        case .status, .result:
            finishPending(with: .success(frame))
        case .error:
            finishPending(with: .failure(Self.driverError(for: frame)))
        case .processing:
            // The device accepted the request. Normally the final answer follows.
            if pending?.acceptsProcessing == true {
                finishPending(with: .success(frame))
            }
        case .set, .get, .setGet, .start, nil:
            unsolicitedContinuation.yield(frame)
        }
    }

    private func handle(_ event: TransportEvent) {
        switch event {
        case .opened:
            decoder.reset()
        case .lost, .gaveUp, .closed:
            decoder.reset()
            finishPending(with: .failure(DriverError.notConnected))
        }
        connectionContinuation.yield(event)
    }

    private func finishPending(id: Int, with result: Result<BMAPFrame, Error>) {
        guard pending?.id == id else { return }
        finishPending(with: result)
    }

    private func finishPending(with result: Result<BMAPFrame, Error>) {
        guard let finished = pending else { return }
        pending = nil
        finished.timer.cancel()
        finished.continuation.resume(with: result)
    }

    private static func driverError(for error: Error) -> DriverError {
        switch error {
        case TransportError.notOpen, TransportError.closed:
            return .notConnected
        default:
            return .transportFailed(String(describing: error))
        }
    }

    private static func driverError(for frame: BMAPFrame) -> DriverError {
        guard let code = frame.errorCode else { return .malformedResponse }
        if code == .operatorNotSupported {
            return .authenticationRequired
        }
        return .rejected(code: Int(frame.payload[0]), reason: String(describing: code))
    }
}
