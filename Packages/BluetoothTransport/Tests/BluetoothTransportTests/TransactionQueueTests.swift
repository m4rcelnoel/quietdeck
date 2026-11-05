import Testing
import TransportInterface

private actor Recorder {
    private(set) var entries: [String] = []
    private(set) var running = 0
    private(set) var maximumRunning = 0

    func enter(_ name: String) {
        running += 1
        maximumRunning = max(maximumRunning, running)
        entries.append(name)
    }

    func leave() {
        running -= 1
    }
}

private struct SampleError: Error {}

@Suite struct TransactionQueueTests {
    @Test func returnsTheResult() async throws {
        let queue = TransactionQueue()
        #expect(try await queue.run { 42 } == 42)
    }

    @Test func propagatesErrorsAndKeepsRunning() async throws {
        let queue = TransactionQueue()
        await #expect(throws: SampleError.self) {
            try await queue.run { () -> Int in throw SampleError() }
        }
        #expect(try await queue.run { 1 } == 1)
    }

    @Test func neverOverlapsEvenAcrossSuspension() async throws {
        let queue = TransactionQueue()
        let recorder = Recorder()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    try await queue.run {
                        await recorder.enter("\(index)")
                        try await Task.sleep(for: .milliseconds(1))
                        await recorder.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await recorder.maximumRunning == 1)
        #expect(await recorder.entries.count == 50)
    }

    @Test func runsInSubmissionOrder() async throws {
        let queue = TransactionQueue()
        let recorder = Recorder()
        for index in 0..<20 {
            try await queue.run {
                await recorder.enter("\(index)")
                await recorder.leave()
            }
        }
        #expect(await recorder.entries == (0..<20).map(String.init))
    }
}
