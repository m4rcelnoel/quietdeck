import Foundation

/// Turns console logs into files that can be lined up with packet captures.
public enum FrameLogExport {
    private struct Row: Encodable {
        var seconds: Double
        var direction: String
        var hex: String
        var summary: String
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined(separator: " ")
    }

    public static func text(_ entries: [FrameLogEntry]) -> String {
        entries.map { entry in
            let time = String(format: "%10.3f", entry.secondsSinceSessionStart)
            return "\(time)  \(arrow(entry.direction))  \(hex(entry.bytes))  \(entry.summary)"
        }.joined(separator: "\n")
    }

    public static func json(_ entries: [FrameLogEntry]) throws -> Data {
        let rows = entries.map {
            Row(
                seconds: $0.secondsSinceSessionStart,
                direction: $0.direction == .sent ? "sent" : "received",
                hex: hex($0.bytes),
                summary: $0.summary
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rows)
    }

    public static func arrow(_ direction: FrameLogEntry.Direction) -> String {
        direction == .sent ? "→" : "←"
    }
}
