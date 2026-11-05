import TransportInterface

/// A scriptable byte transport for driver tests.
public actor MockTransport: ByteTransport {
    public enum Failure: Error, Equatable {
        case closed
        case scripted
    }

    public nonisolated let incoming: AsyncStream<[UInt8]>
    public nonisolated let lifecycle: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private let lifecycleContinuation: AsyncStream<TransportEvent>.Continuation

    public private(set) var isOpen = false
    public private(set) var openCount = 0
    public private(set) var sent: [[UInt8]] = []

    private var failNextOpen = false
    private var failNextSend = false
    private var responder: (@Sendable ([UInt8]) -> [[UInt8]])?

    /// - Parameter responder: Returns the chunks to deliver after each send.
    public init(responder: (@Sendable ([UInt8]) -> [[UInt8]])? = nil) {
        (incoming, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        (lifecycle, lifecycleContinuation) = AsyncStream.makeStream(of: TransportEvent.self)
        self.responder = responder
    }

    public func open() async throws {
        openCount += 1
        if failNextOpen {
            failNextOpen = false
            throw Failure.scripted
        }
        isOpen = true
        lifecycleContinuation.yield(.opened)
    }

    public func close() async {
        isOpen = false
        lifecycleContinuation.yield(.closed)
    }

    public func send(_ bytes: [UInt8]) async throws {
        guard isOpen else { throw Failure.closed }
        if failNextSend {
            failNextSend = false
            throw Failure.scripted
        }
        sent.append(bytes)
        for chunk in responder?(bytes) ?? [] {
            continuation.yield(chunk)
        }
    }

    /// Delivers bytes as if the device sent them unprompted.
    public func deliver(_ bytes: [UInt8]) {
        continuation.yield(bytes)
    }

    /// Simulates a dropped connection.
    public func simulateLoss() {
        isOpen = false
        lifecycleContinuation.yield(.lost)
    }

    /// Ends the incoming stream.
    public func finishIncoming() {
        continuation.finish()
    }

    public func setResponder(_ responder: (@Sendable ([UInt8]) -> [[UInt8]])?) {
        self.responder = responder
    }

    public func failOpenOnce() {
        failNextOpen = true
    }

    public func failSendOnce() {
        failNextSend = true
    }
}
