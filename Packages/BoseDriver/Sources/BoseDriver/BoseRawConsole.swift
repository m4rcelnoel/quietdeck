import BMAPCodec
import Foundation
import QuietDeckCore

/// Raw frame access for the Protocol Console.
public final class BoseRawConsole: RawFrameConsole {
    public let composer = FrameComposerSpec(fields: [
        .init(id: "fblock", label: "Function block"),
        .init(id: "function", label: "Function"),
        .init(id: "operator", label: "Operator", choices: ["GET", "START", "SETGET"]),
        .init(id: "payload", label: "Payload (hex)"),
    ])

    public let traffic: AsyncStream<FrameLogEntry>

    private let client: BMAPClient
    private let forwarder: Task<Void, Never>

    init(client: BMAPClient) {
        self.client = client
        let (stream, continuation) = AsyncStream.makeStream(of: FrameLogEntry.self)
        traffic = stream
        forwarder = Task {
            let clock = ContinuousClock()
            let start = clock.now
            for await item in client.traffic {
                let parts = (clock.now - start).components
                continuation.yield(
                    FrameLogEntry(
                        secondsSinceSessionStart: Double(parts.seconds) + Double(parts.attoseconds) / 1e18,
                        direction: item.direction == .sent ? .sent : .received,
                        bytes: item.frame.encoded(),
                        summary: Self.summary(of: item.frame)
                    )
                )
            }
            continuation.finish()
        }
    }

    deinit {
        forwarder.cancel()
    }

    public func evaluate(_ frame: RawFrame) -> RawFrameVerdict {
        BoseFramePolicy.evaluate(frame.bytes)
    }

    /// Sends a frame. The policy is enforced here too, so no caller can skip it.
    public func send(_ frame: RawFrame) async throws {
        if case .deny = evaluate(frame) {
            throw DriverError.unsupported
        }
        guard let parsed = BoseFramePolicy.singleFrame(in: frame.bytes) else {
            throw DriverError.unsupported
        }
        _ = try await client.transact(parsed)
    }

    public func frame(from values: [String: String]) -> RawFrame? {
        guard let block = values["fblock"].flatMap(Self.number),
            let function = values["function"].flatMap(Self.number),
            let op = values["operator"].flatMap(Self.composerOperator),
            let payload = Self.bytes(fromHex: values["payload"] ?? ""),
            let frame = try? BMAPFrame(
                address: BMAPAddress(functionBlock: block, function: function), operator: op, payload: payload
            )
        else { return nil }
        return RawFrame(bytes: frame.encoded())
    }

    public func redacted(_ entry: FrameLogEntry) -> FrameLogEntry {
        guard let frame = BoseFramePolicy.singleFrame(in: entry.bytes) else { return entry }
        var result = entry
        result.bytes = Self.masked(frame)
        return result
    }

    /// Payload bytes that identify a device or its owner are replaced with zeros.
    private static func masked(_ frame: BMAPFrame) -> [UInt8] {
        let keep: Int
        switch (frame.address.functionBlock, frame.address.function) {
        case (4, 4): keep = 1  // Count, then addresses.
        case (5, 1): keep = 3  // Supported sources and type, then an address.
        case (4, 5), (4, 12), (4, 1), (4, 2): keep = 0  // Addresses and names.
        case (1, 2): keep = 0  // Device name.
        default: return frame.encoded()
        }
        let payload = frame.payload.enumerated().map { $0.offset < keep ? $0.element : 0 }
        let header = Array(frame.encoded().prefix(BMAPFrame.headerLength))
        return header + payload
    }

    private static func number(_ text: String) -> UInt8? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt8(trimmed.dropFirst(2), radix: 16)
        }
        return UInt8(trimmed)
    }

    private static func composerOperator(_ name: String) -> BMAPOperator? {
        switch name {
        case "GET": return .get
        case "START": return .start
        case "SETGET": return .setGet
        default: return nil
        }
    }

    private static func bytes(fromHex text: String) -> [UInt8]? {
        let digits = text.filter { !$0.isWhitespace }
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    static func summary(of frame: BMAPFrame) -> String {
        let name = frame.operator.map { String(describing: $0).uppercased() } ?? "OP\(frame.operatorCode)"
        if let code = frame.errorCode {
            return "\(frame.address) \(name) \(code)"
        }
        return "\(frame.address) \(name)"
    }
}
