import QuietDeckCore
import QuietDeckTesting
import Testing

@testable import BoseDriver

private let console = BoseRawConsole(client: BMAPClient(transport: MockTransport()))

private func entry(_ bytes: [UInt8]) -> FrameLogEntry {
    FrameLogEntry(secondsSinceSessionStart: 0, direction: .received, bytes: bytes, summary: "")
}

@Suite struct BoseRawConsoleTests {
    @Test func buildsFrameFromComposerValues() {
        let frame = console.frame(from: ["fblock": "31", "function": "3", "operator": "START", "payload": "01 00"])
        #expect(frame?.bytes == [0x1F, 0x03, 0x05, 0x02, 0x01, 0x00])
    }

    @Test func acceptsHexBlockNumbers() {
        let frame = console.frame(from: ["fblock": "0x1f", "function": "3", "operator": "GET"])
        #expect(frame?.bytes == [0x1F, 0x03, 0x01, 0x00])
    }

    @Test(arguments: [
        ["fblock": "300", "function": "3", "operator": "GET"],
        ["fblock": "x", "function": "3", "operator": "GET"],
        ["fblock": "1", "function": "3", "operator": "SET"],
        ["fblock": "1", "function": "3", "operator": "GET", "payload": "abc"],
        ["fblock": "1", "function": "3", "operator": "GET", "payload": "zz"],
    ])
    func rejectsInvalidValues(values: [String: String]) {
        #expect(console.frame(from: values) == nil)
    }

    @Test func redactsAddressesInActiveSource() {
        let frame: [UInt8] = [5, 1, 3, 9, 0, 0x0F, 1, 1, 2, 3, 4, 5, 6]
        #expect(console.redacted(entry(frame)).bytes == [5, 1, 3, 9, 0, 0x0F, 1, 0, 0, 0, 0, 0, 0])
    }

    @Test func redactsDeviceListButKeepsCount() {
        let frame: [UInt8] = [4, 4, 3, 7, 3, 1, 2, 3, 4, 5, 6]
        #expect(console.redacted(entry(frame)).bytes == [4, 4, 3, 7, 3, 0, 0, 0, 0, 0, 0])
    }

    @Test func redactsDeviceInfoAndName() {
        #expect(console.redacted(entry([4, 5, 3, 2, 8, 9])).bytes == [4, 5, 3, 2, 0, 0])
        #expect(console.redacted(entry([1, 2, 3, 2, 0, 65])).bytes == [1, 2, 3, 2, 0, 0])
    }

    @Test func leavesOrdinaryFramesAlone() {
        let frame: [UInt8] = [2, 2, 3, 1, 90]
        #expect(console.redacted(entry(frame)).bytes == frame)
    }
}
