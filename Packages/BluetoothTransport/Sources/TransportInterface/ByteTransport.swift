/// A bidirectional byte stream to a device. Drivers only ever see this protocol.
public protocol ByteTransport: Sendable {
    /// Bytes received from the device, in arrival order and in arbitrary chunks.
    /// The stream outlives reconnections.
    ///
    /// Like `lifecycle`, this allows one consumer only: with several, each value would
    /// reach just one of them. The driver consumes both and forwards what others need.
    var incoming: AsyncStream<[UInt8]> { get }

    /// Changes in the connection, so a driver can reset its parsers and fail pending work.
    var lifecycle: AsyncStream<TransportEvent> { get }

    func open() async throws
    func close() async
    func send(_ bytes: [UInt8]) async throws
}

public enum TransportEvent: Sendable, Equatable {
    case opened
    /// The connection dropped unexpectedly. The transport may reconnect by itself.
    case lost
    /// All automatic reconnection attempts failed.
    case gaveUp
    /// The connection was closed on request.
    case closed
}

public enum TransportError: Error, Sendable, Equatable {
    case notOpen
    case closed
    case openTimedOut
    /// Carries the platform status code.
    case openFailed(Int32)
    case writeFailed(Int32)
}
