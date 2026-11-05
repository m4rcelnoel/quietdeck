/// Reassembles frames from a byte stream.
///
/// RFCOMM delivers bytes in arbitrary chunks: one read can hold part of a frame or
/// several frames. BMAP has no sync marker, so the decoder can't recover from lost
/// bytes by itself. The session calls `reset()` whenever it reopens the channel.
public struct BMAPFrameDecoder: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    /// The number of bytes waiting for the rest of their frame.
    public var pendingByteCount: Int {
        buffer.count
    }

    /// Adds received bytes and returns every frame they complete, in order.
    public mutating func append(_ bytes: some Sequence<UInt8>) -> [BMAPFrame] {
        buffer.append(contentsOf: bytes)

        var frames: [BMAPFrame] = []
        var offset = 0
        while buffer.count - offset >= BMAPFrame.headerLength {
            let payloadLength = Int(buffer[offset + 3])
            let frameLength = BMAPFrame.headerLength + payloadLength
            guard buffer.count - offset >= frameLength else { break }

            let address = BMAPAddress(functionBlock: buffer[offset], function: buffer[offset + 1])
            let payload = Array(buffer[(offset + BMAPFrame.headerLength)..<(offset + frameLength)])
            // A one-byte length can't exceed the maximum, so this can't fail.
            if let frame = try? BMAPFrame(address: address, flags: buffer[offset + 2], payload: payload) {
                frames.append(frame)
            }
            offset += frameLength
        }
        buffer.removeFirst(offset)
        return frames
    }

    /// Drops any partial frame.
    public mutating func reset() {
        buffer.removeAll()
    }
}
