import Testing
import TransportInterface
import os

@testable import BluetoothTransport

/// Stands in for a real channel. `close()` fails a pending open, as the contract requires.
private actor FakeLink: RFCOMMLink {
    enum Behavior: Sendable {
        case succeed
        case fail
        case hang
    }

    nonisolated let events: AsyncStream<RFCOMMLinkEvent>
    private let continuation: AsyncStream<RFCOMMLinkEvent>.Continuation
    private let behavior: Behavior
    private var pendingOpen: CheckedContinuation<Void, Error>?

    private(set) var written: [[UInt8]] = []
    private(set) var closeCount = 0

    init(behavior: Behavior) {
        self.behavior = behavior
        (events, continuation) = AsyncStream.makeStream(of: RFCOMMLinkEvent.self)
    }

    func open() async throws {
        switch behavior {
        case .succeed:
            return
        case .fail:
            throw TransportError.openFailed(-1)
        case .hang:
            try await withCheckedThrowingContinuation { pendingOpen = $0 }
        }
    }

    func write(_ bytes: [UInt8]) async throws {
        written.append(bytes)
    }

    func close() async {
        closeCount += 1
        pendingOpen?.resume(throwing: TransportError.closed)
        pendingOpen = nil
        continuation.finish()
    }

    func receive(_ bytes: [UInt8]) {
        continuation.yield(.data(bytes))
    }

    func drop() {
        continuation.yield(.closed)
        continuation.finish()
    }
}

/// Hands out links with scripted behavior and remembers them.
private final class LinkFactory: Sendable {
    private struct State {
        var script: [FakeLink.Behavior]
        var made: [FakeLink] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(_ behaviors: [FakeLink.Behavior] = []) {
        state = OSAllocatedUnfairLock(uncheckedState: State(script: behaviors))
    }

    @Sendable func make() -> any RFCOMMLink {
        state.withLockUnchecked { state in
            let behavior = state.script.isEmpty ? FakeLink.Behavior.succeed : state.script.removeFirst()
            let link = FakeLink(behavior: behavior)
            state.made.append(link)
            return link
        }
    }

    var links: [FakeLink] {
        state.withLockUnchecked { $0.made }
    }
}

private func fast(
    timeout: Duration = .milliseconds(40),
    cooldown: Duration = .milliseconds(5),
    delays: [Duration] = [.milliseconds(5), .milliseconds(5)]
) -> RFCOMMSession.Configuration {
    RFCOMMSession.Configuration(openTimeout: timeout, cooldown: cooldown, reconnectDelays: delays)
}

private func nextEvents(_ session: RFCOMMSession, count: Int) async -> [TransportEvent] {
    var events: [TransportEvent] = []
    for await event in session.lifecycle {
        events.append(event)
        if events.count == count { break }
    }
    return events
}

@Suite(.timeLimit(.minutes(1))) struct RFCOMMSessionTests {
    @Test func opensAndSends() async throws {
        let factory = LinkFactory()
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        try await session.open()
        try await session.send([1, 2])
        #expect(await factory.links[0].written == [[1, 2]])
        #expect(await nextEvents(session, count: 1) == [.opened])
    }

    @Test func sendBeforeOpenFails() async {
        let session = RFCOMMSession(configuration: fast(), makeLink: LinkFactory().make)
        await #expect(throws: TransportError.notOpen) {
            try await session.send([1])
        }
    }

    @Test func openingTwiceKeepsOneLink() async throws {
        let factory = LinkFactory()
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        try await session.open()
        try await session.open()
        #expect(factory.links.count == 1)
    }

    @Test func concurrentOpensShareOneAttempt() async throws {
        let factory = LinkFactory()
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        async let first: Void = session.open()
        async let second: Void = session.open()
        _ = try await (first, second)
        #expect(factory.links.count == 1)
    }

    @Test func deliversBytes() async throws {
        let factory = LinkFactory()
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        try await session.open()
        await factory.links[0].receive([7, 8])
        var iterator = session.incoming.makeAsyncIterator()
        #expect(await iterator.next() == [7, 8])
    }

    @Test func reportsOpenFailure() async {
        let factory = LinkFactory([.fail])
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        await #expect(throws: TransportError.openFailed(-1)) {
            try await session.open()
        }
        #expect(await factory.links[0].closeCount >= 1)
    }

    @Test func timesOutWhenTheCallbackNeverComes() async {
        let factory = LinkFactory([.hang])
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        await #expect(throws: TransportError.openTimedOut) {
            try await session.open()
        }
    }

    @Test func waitsForCooldownBeforeReopening() async throws {
        let factory = LinkFactory()
        let cooldown = Duration.milliseconds(120)
        let session = RFCOMMSession(configuration: fast(cooldown: cooldown), makeLink: factory.make)
        try await session.open()
        await session.close()

        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            try await session.open()
        }
        #expect(elapsed >= .milliseconds(100))
        #expect(factory.links.count == 2)
    }

    @Test func closesOnRequestWithoutReconnecting() async throws {
        let factory = LinkFactory()
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        try await session.open()
        await session.close()
        try await Task.sleep(for: .milliseconds(40))
        #expect(factory.links.count == 1)
        #expect(await nextEvents(session, count: 2) == [.opened, .closed])
        await #expect(throws: TransportError.notOpen) {
            try await session.send([1])
        }
    }

    @Test func reconnectsAfterALostConnection() async throws {
        let factory = LinkFactory()
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        try await session.open()
        await factory.links[0].drop()
        #expect(await nextEvents(session, count: 3) == [.opened, .lost, .opened])
        #expect(factory.links.count == 2)
        try await session.send([3])
        #expect(await factory.links[1].written == [[3]])
    }

    @Test func triesEachDelayThenGivesUp() async throws {
        let factory = LinkFactory([.succeed, .fail, .fail])
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        try await session.open()
        await factory.links[0].drop()
        #expect(await nextEvents(session, count: 3) == [.opened, .lost, .gaveUp])
        #expect(factory.links.count == 3)
    }

    @Test func deviceAppearingRestartsAfterGivingUp() async throws {
        let factory = LinkFactory([.succeed, .fail, .fail, .succeed])
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        try await session.open()
        await factory.links[0].drop()
        _ = await nextEvents(session, count: 3)
        await session.deviceAppeared()
        #expect(await nextEvents(session, count: 1) == [.opened])
    }

    @Test func deviceAppearingIsIgnoredAfterClosing() async throws {
        let factory = LinkFactory()
        let session = RFCOMMSession(configuration: fast(), makeLink: factory.make)
        try await session.open()
        await session.close()
        await session.deviceAppeared()
        try await Task.sleep(for: .milliseconds(40))
        #expect(factory.links.count == 1)
    }

    @Test func closingStopsReconnection() async throws {
        let factory = LinkFactory()
        let delays: [Duration] = [.milliseconds(30), .milliseconds(30)]
        let session = RFCOMMSession(configuration: fast(delays: delays), makeLink: factory.make)
        try await session.open()
        await factory.links[0].drop()
        _ = await nextEvents(session, count: 2)
        await session.close()
        try await Task.sleep(for: .milliseconds(80))
        #expect(factory.links.count == 1)
    }
}
