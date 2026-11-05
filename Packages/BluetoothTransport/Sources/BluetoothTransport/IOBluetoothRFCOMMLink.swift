import Foundation
import RFCOMMBridge
import TransportInterface

/// The real link, on top of the Objective-C bridge. Lives on the main actor because
/// IOBluetooth delivers its callbacks on the run loop that opened the channel.
@MainActor
public final class IOBluetoothRFCOMMLink: RFCOMMLink {
    public nonisolated let events: AsyncStream<RFCOMMLinkEvent>

    private nonisolated let continuation: AsyncStream<RFCOMMLinkEvent>.Continuation
    private nonisolated let address: String
    private nonisolated let channelID: UInt8

    private var channel: QDRFCOMMChannel?
    private var pendingOpen: CheckedContinuation<Void, Error>?

    public nonisolated init(address: String, channelID: UInt8) {
        self.address = address
        self.channelID = channelID
        (events, continuation) = AsyncStream.makeStream(of: RFCOMMLinkEvent.self)
    }

    public func open() async throws {
        try await withCheckedThrowingContinuation { (pending: CheckedContinuation<Void, Error>) in
            pendingOpen = pending

            let channel = QDRFCOMMChannel(address: address, channelID: channelID)
            self.channel = channel
            let continuation = continuation
            channel.onData = { @Sendable data in
                continuation.yield(.data([UInt8](data)))
            }
            channel.onClosed = { @Sendable in
                continuation.yield(.closed)
                continuation.finish()
            }
            channel.open { @Sendable [weak self] status in
                MainActor.assumeIsolated {
                    self?.finishOpen(status: status)
                }
            }
        }
    }

    private func finishOpen(status: Int32) {
        guard let pending = pendingOpen else { return }
        pendingOpen = nil
        if status == 0 {
            pending.resume()
        } else {
            pending.resume(throwing: TransportError.openFailed(status))
        }
    }

    public func write(_ bytes: [UInt8]) async throws {
        guard let channel else { throw TransportError.notOpen }
        let status = channel.write(Data(bytes))
        guard status == 0 else { throw TransportError.writeFailed(status) }
    }

    public func close() async {
        channel?.onData = nil
        channel?.onClosed = nil
        channel?.close()
        channel = nil
        continuation.finish()
    }
}
