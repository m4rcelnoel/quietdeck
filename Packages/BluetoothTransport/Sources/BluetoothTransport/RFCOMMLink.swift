/// One attempt at a connection. A link is used once: after it closes, a new one is made.
public protocol RFCOMMLink: Sendable {
    var events: AsyncStream<RFCOMMLinkEvent> { get }

    /// Must fail promptly if `close()` is called while it is in progress.
    func open() async throws
    func write(_ bytes: [UInt8]) async throws
    func close() async
}

public enum RFCOMMLinkEvent: Sendable, Equatable {
    case data([UInt8])
    case closed
}
