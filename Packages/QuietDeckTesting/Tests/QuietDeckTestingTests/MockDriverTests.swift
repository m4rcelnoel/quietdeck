import QuietDeckCore
import Testing

@testable import QuietDeckTesting

@Suite struct MockDriverTests {
    private func connected(
        _ capabilities: DeviceCapabilities = Fixtures.fullCapabilities,
        _ state: DeviceState = Fixtures.fullState
    ) async throws -> MockDriver {
        let driver = MockDriver(capabilities: capabilities, state: state)
        try await driver.connect()
        return driver
    }

    @Test func refusesCommandsBeforeConnecting() async {
        let driver = MockDriver(capabilities: Fixtures.fullCapabilities, state: Fixtures.fullState)
        await #expect(throws: DriverError.notConnected) {
            try await driver.perform(.setMode("aware"))
        }
    }

    @Test func refusesWhatTheDeviceCannotDo() async throws {
        let driver = try await connected(Fixtures.limitedCapabilities, Fixtures.limitedState)
        await #expect(throws: DriverError.unsupported) {
            try await driver.perform(.setEqualizerBand(id: 0, value: 1))
        }
        #expect(await driver.performed.isEmpty)
    }

    @Test func modeChangeUpdatesState() async throws {
        let driver = try await connected()
        try await driver.perform(.setMode("aware"))
        #expect(try await driver.refreshState().mode == .preset("aware"))
    }

    @Test func manualAudioChangeLeavesThePreset() async throws {
        let driver = try await connected()
        try await driver.perform(.setAudio(noiseLevel: 4, spatial: nil, windBlock: nil))
        let state = try await driver.refreshState()
        #expect(state.mode == .custom)
        #expect(state.noiseLevel == 4)
        #expect(state.spatialAudio == .off)
    }

    @Test func switchingSourceDemotesThePreviousOne() async throws {
        let driver = try await connected()
        try await driver.perform(.switchSource("AA:AA:AA:AA:AA:02"))
        let sources = try await driver.refreshState().sources
        #expect(sources?.active?.name == "Studio Mac")
        #expect(sources?.sources(with: .connected).map(\.name) == ["This Mac"])
    }

    @Test func equalizerChangeKeepsOtherBands() async throws {
        let driver = try await connected()
        try await driver.perform(.setEqualizerBand(id: 1, value: -3))
        let bands = try await driver.refreshState().equalizer
        #expect(bands?.map(\.value) == [2, -3, 1])
    }

    @Test func scriptedErrorHappensOnceAndAppliesNothing() async throws {
        let driver = try await connected()
        await driver.failNext(with: .authenticationRequired)
        await #expect(throws: DriverError.authenticationRequired) {
            try await driver.perform(.setMultipoint(false))
        }
        #expect(try await driver.refreshState().multipoint == true)
        try await driver.perform(.setMultipoint(false))
        #expect(try await driver.refreshState().multipoint == false)
    }

    @Test func reportsChangesAsEvents() async throws {
        let driver = MockDriver(capabilities: Fixtures.fullCapabilities, state: Fixtures.fullState)
        var iterator = driver.events.makeAsyncIterator()
        try await driver.connect()
        #expect(await iterator.next() == .connectionChanged(.connected))

        await driver.simulateDeviceChange { $0.mode = .custom }
        guard case .stateChanged(let state) = await iterator.next() else {
            Issue.record("Expected a state change")
            return
        }
        #expect(state.mode == .custom)
    }

    @Test func registryFindsMockDriver() async {
        let registry = DriverRegistry(drivers: [MockDriver.self])
        let device = DiscoveredDevice(name: "Mock Headphones", address: "00")
        #expect(registry.makeDriver(for: device, transport: MockTransport()) is MockDriver)
    }

    @Test func limitedFixtureShowsFewerSections() {
        #expect(Fixtures.limitedCapabilities.sections == [.listening, .device])
        #expect(Fixtures.fullCapabilities.sections == DeviceSection.allCases)
    }
}
