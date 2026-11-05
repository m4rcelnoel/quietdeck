import Foundation
import Testing

@testable import QuietDeckCore

private let entries = [
    FrameLogEntry(secondsSinceSessionStart: 1.5, direction: .sent, bytes: [2, 2, 1, 0], summary: "[2.2] GET"),
    FrameLogEntry(secondsSinceSessionStart: 1.52, direction: .received, bytes: [0xAB], summary: "reply"),
]

@Suite struct FrameLogExportTests {
    @Test func hexUsesTwoDigits() {
        #expect(FrameLogExport.hex([0x0A, 0xFF]) == "0a ff")
    }

    @Test func textHasOneLinePerFrame() {
        let lines = FrameLogExport.text(entries).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("→"))
        #expect(lines[0].contains("02 02 01 00"))
        #expect(lines[1].contains("←"))
    }

    @Test func jsonRoundTrips() throws {
        let rows = try JSONDecoder().decode(
            [[String: AnyDecodableValue]].self, from: FrameLogExport.json(entries)
        )
        #expect(rows.count == 2)
        #expect(rows[0]["direction"]?.text == "sent")
        #expect(rows[1]["hex"]?.text == "ab")
    }
}

private struct AnyDecodableValue: Decodable {
    var text: String?

    init(from decoder: any Decoder) throws {
        text = try? decoder.singleValueContainer().decode(String.self)
    }
}
