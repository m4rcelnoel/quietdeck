import Testing

@testable import HandoffKit

@MainActor
@Suite struct SilentOutputStreamTests {
    @Test func stoppingWithoutStartingIsHarmless() {
        SilentOutputStream().stop()
    }
}
