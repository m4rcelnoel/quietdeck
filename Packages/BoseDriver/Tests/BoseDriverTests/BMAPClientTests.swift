import BMAPCodec
import QuietDeckCore
import QuietDeckTesting
import Testing
import TransportInterface

@testable import BoseDriver

private let batteryRequest: [UInt8] = [0x02, 0x02, 0x01, 0x00]
private let batteryReply: [UInt8] = [0x02, 0x02, 0x03, 0x04, 0x50, 0xFF, 0xFF, 0x00]

private func makeClient(
    timeout: Duration = .seconds(5),
    responder: (@Sendable ([UInt8]) -> [[UInt8]])? = nil
) async throws -> (BMAPClient, MockTransport) {
    let transport = MockTransport(responder: responder)
    let client = BMAPClient(transport: transport, timeout: timeout)
    await client.start()
    try await transport.open()
    return (client, transport)
}

private func request(_ address: BMAPAddress, _ op: BMAPOperator = .get) throws -> BMAPFrame {
    try BMAPFrame(address: address, operator: op)
}

private let battery = BMAPAddress(functionBlock: 2, function: 2)

@Suite(.timeLimit(.minutes(1))) struct BMAPClientTests {
    @Test func readsBattery() async throws {
        let (client, transport) = try await makeClient { _ in [batteryReply] }
        #expect(try await client.readBatteryPercent() == 80)
        #expect(await transport.sent == [batteryRequest])
    }

    @Test func assemblesFragmentedResponses() async throws {
        let (client, _) = try await makeClient { _ in
            [Array(batteryReply.prefix(2)), Array(batteryReply[2..<5]), Array(batteryReply.suffix(3))]
        }
        #expect(try await client.readBatteryPercent() == 80)
    }

    @Test func rejectsImpossibleBatteryValue() async throws {
        let (client, _) = try await makeClient { _ in [[0x02, 0x02, 0x03, 0x01, 0xC8]] }
        await #expect(throws: DriverError.malformedResponse) {
            try await client.readBatteryPercent()
        }
    }

    @Test func rejectsEmptyBatteryPayload() async throws {
        let (client, _) = try await makeClient { _ in [[0x02, 0x02, 0x03, 0x00]] }
        await #expect(throws: DriverError.malformedResponse) {
            try await client.readBatteryPercent()
        }
    }

    @Test func mapsOperatorNotSupportedToAuthenticationRequired() async throws {
        let (client, _) = try await makeClient { _ in [[0x02, 0x02, 0x04, 0x01, 0x05]] }
        await #expect(throws: DriverError.authenticationRequired) {
            try await client.transact(request(battery))
        }
    }

    @Test func mapsOtherErrorsToRejected() async throws {
        let (client, _) = try await makeClient { _ in [[0x02, 0x02, 0x04, 0x01, 0x06]] }
        await #expect(throws: DriverError.rejected(code: 6, reason: "invalidData")) {
            try await client.transact(request(battery))
        }
    }

    @Test func errorFrameWithoutCodeIsMalformed() async throws {
        let (client, _) = try await makeClient { _ in [[0x02, 0x02, 0x04, 0x00]] }
        await #expect(throws: DriverError.malformedResponse) {
            try await client.transact(request(battery))
        }
    }

    @Test func waitsThroughProcessingForTheResult() async throws {
        let (client, _) = try await makeClient { _ in
            [[0x02, 0x02, 0x07, 0x00], [0x02, 0x02, 0x06, 0x01, 0x09]]
        }
        let reply = try await client.transact(request(battery, .start))
        #expect(reply.operator == .result)
        #expect(reply.payload == [9])
    }

    @Test func timesOutWithoutAnAnswer() async throws {
        let (client, _) = try await makeClient(timeout: .milliseconds(30))
        await #expect(throws: DriverError.timeout) {
            try await client.transact(request(battery))
        }
    }

    @Test func aTimeoutDoesNotBlockTheNextRequest() async throws {
        let (client, transport) = try await makeClient(timeout: .milliseconds(30))
        await #expect(throws: DriverError.timeout) {
            try await client.transact(request(battery))
        }
        await transport.setResponder { _ in [batteryReply] }
        #expect(try await client.readBatteryPercent() == 80)
    }

    @Test func aLateAnswerAfterTimeoutIsNotTakenForTheNextRequest() async throws {
        let (client, transport) = try await makeClient(timeout: .milliseconds(30))
        await #expect(throws: DriverError.timeout) {
            try await client.transact(request(battery))
        }
        var unsolicited = client.unsolicited.makeAsyncIterator()
        await transport.deliver(batteryReply)
        #expect(await unsolicited.next()?.address == battery)
    }

    @Test func framesForOtherAddressesAreUnsolicited() async throws {
        let other: [UInt8] = [0x1F, 0x03, 0x03, 0x01, 0x02]
        let (client, _) = try await makeClient { _ in [other + batteryReply] }
        var unsolicited = client.unsolicited.makeAsyncIterator()
        #expect(try await client.readBatteryPercent() == 80)
        #expect(await unsolicited.next()?.encoded() == other)
    }

    @Test func framesWithoutARequestAreUnsolicited() async throws {
        let (client, transport) = try await makeClient()
        var unsolicited = client.unsolicited.makeAsyncIterator()
        await transport.deliver(batteryReply)
        #expect(await unsolicited.next()?.encoded() == batteryReply)
    }

    @Test func aLostConnectionFailsThePendingRequest() async throws {
        let (client, transport) = try await makeClient()
        let frame = try request(battery)
        let result = Task { try await client.transact(frame) }
        while await transport.sent.isEmpty {
            await Task.yield()
        }
        await transport.simulateLoss()
        await #expect(throws: DriverError.notConnected) {
            try await result.value
        }
    }

    @Test func sendingWhileClosedFails() async throws {
        let transport = MockTransport()
        let client = BMAPClient(transport: transport, timeout: .seconds(5))
        await client.start()
        await #expect(throws: DriverError.self) {
            try await client.transact(request(battery))
        }
    }

    @Test func reconnectingDropsAPartialFrame() async throws {
        let (client, transport) = try await makeClient()
        await transport.deliver(Array(batteryReply.prefix(5)))
        await transport.simulateLoss()
        try await transport.open()

        // The next request must only start once the client has seen the reconnection.
        var events = client.connectionEvents.makeAsyncIterator()
        for _ in 0..<3 {
            _ = await events.next()
        }
        await transport.setResponder { _ in [batteryReply] }
        #expect(try await client.readBatteryPercent() == 80)
    }

    @Test func forwardsEveryConnectionEvent() async throws {
        let (client, transport) = try await makeClient()
        await transport.simulateLoss()
        try await transport.open()
        await transport.close()

        var events = client.connectionEvents.makeAsyncIterator()
        #expect(await events.next() == .opened)
        #expect(await events.next() == .lost)
        #expect(await events.next() == .opened)
        #expect(await events.next() == .closed)
    }

    @Test func logsBothDirections() async throws {
        let (client, _) = try await makeClient { _ in [batteryReply] }
        _ = try await client.readBatteryPercent()
        var traffic = client.traffic.makeAsyncIterator()
        #expect(await traffic.next()?.direction == .sent)
        #expect(await traffic.next()?.frame.encoded() == batteryReply)
    }

    @Test func consoleRefusesDeniedFramesEvenWhenCalledDirectly() async throws {
        let transport = MockTransport()
        let driver = BoseHeadphoneDriver(
            device: DiscoveredDevice(name: "Bose QC Ultra 2 HP", address: "00"), transport: transport
        )
        try await driver.connect()
        await #expect(throws: DriverError.unsupported) {
            try await driver.rawConsole?.send(RawFrame(bytes: [18, 1, 1, 0]))
        }
        #expect(await transport.sent.isEmpty)
    }

    @Test func servesConcurrentCallersOneAtATime() async throws {
        let (client, transport) = try await makeClient { _ in [batteryReply] }
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<100 {
                group.addTask { try await client.readBatteryPercent() }
            }
            for try await percent in group {
                #expect(percent == 80)
            }
        }
        #expect(await transport.sent.count == 100)
    }
}
