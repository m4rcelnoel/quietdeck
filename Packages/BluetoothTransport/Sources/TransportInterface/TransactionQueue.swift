/// Runs asynchronous work strictly one at a time, in submission order.
///
/// An actor alone can't guarantee this, because it interleaves other calls at every
/// `await`. A single consumer task can. Drivers use this so that a request and its
/// response are never mixed with another transaction.
public final class TransactionQueue: Sendable {
    private typealias Job = @Sendable () async -> Void

    private let jobs: AsyncStream<Job>.Continuation
    private let worker: Task<Void, Never>

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Job.self)
        jobs = continuation
        worker = Task {
            for await job in stream {
                await job()
            }
        }
    }

    deinit {
        jobs.finish()
    }

    public func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            jobs.yield {
                do {
                    continuation.resume(returning: try await operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
