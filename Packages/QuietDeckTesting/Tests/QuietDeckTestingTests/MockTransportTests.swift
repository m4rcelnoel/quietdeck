import Testing

@testable import QuietDeckTesting

@Suite struct MockTransportTests {
    @Test func sendFailsWhileClosed() async {
        let transport = MockTransport()
        await #expect(throws: MockTransport.Failure.closed) {
            try await transport.send([1])
        }
    }

    @Test func recordsSentBytesAndDeliversReplyChunks() async throws {
        let transport = MockTransport { _ in [[1, 2], [3]] }
        try await transport.open()
        try await transport.send([9])
        await transport.finishIncoming()

        var received: [[UInt8]] = []
        for await chunk in transport.incoming {
            received.append(chunk)
        }
        #expect(await transport.sent == [[9]])
        #expect(received == [[1, 2], [3]])
    }

    @Test func scriptedOpenFailureHappensOnce() async throws {
        let transport = MockTransport()
        await transport.failOpenOnce()
        await #expect(throws: MockTransport.Failure.scripted) {
            try await transport.open()
        }
        try await transport.open()
        #expect(await transport.isOpen)
        #expect(await transport.openCount == 2)
    }

    @Test func scriptedSendFailureHappensOnce() async throws {
        let transport = MockTransport()
        try await transport.open()
        await transport.failSendOnce()
        await #expect(throws: MockTransport.Failure.scripted) {
            try await transport.send([1])
        }
        try await transport.send([2])
        #expect(await transport.sent == [[2]])
    }
}
