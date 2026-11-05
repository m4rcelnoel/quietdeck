import QuietDeckCore
import QuietDeckTesting
import Testing
import TransportInterface

@testable import BoseDriver

private let device = DiscoveredDevice(name: "Bose QC Ultra 2 HP", address: "00")

private func connected(
    _ headset: SimulatedHeadset = SimulatedHeadset()
) async throws -> (BoseHeadphoneDriver, SimulatedHeadset) {
    let transport = MockTransport { headset.respond(to: $0) }
    let driver = BoseHeadphoneDriver(device: device, transport: transport)
    try await driver.connect()
    return (driver, headset)
}

@Suite(.timeLimit(.minutes(1))) struct BoseHeadphoneDriverTests {
    @Test func matchesByProductThenName() {
        #expect(
            BoseHeadphoneDriver.match(DiscoveredDevice(name: "x", address: "0", productID: 0x4082)) == .vendorAndProduct
        )
        #expect(BoseHeadphoneDriver.match(device) == .name)
        #expect(BoseHeadphoneDriver.match(DiscoveredDevice(name: "Other", address: "0")) == nil)
    }

    @Test func refreshReadsEverything() async throws {
        let (driver, _) = try await connected()
        let state = try await driver.refreshState()
        #expect(state.mode == .preset("quiet"))
        #expect(state.noiseLevel == 10)
        #expect(state.spatialAudio == .off)
        #expect(state.windBlock == false)
        #expect(state.equalizer?.map(\.value) == [1, -1, 1])
        #expect(state.battery?.percent == 90)
        #expect(state.multipoint == true)
        #expect(state.name == "Bose QC Ultra 2 HP")
        #expect(state.firmwareVersion == "10.12.14+gde0210e")
        #expect(state.sources?.active?.name == "This Mac")
        #expect(state.sources?.sources(with: .connected).map(\.name) == ["Other"])
    }

    @Test func nameAndFirmwareAreReadOncePerConnection() async throws {
        let headset = SimulatedHeadset()
        let transport = MockTransport { headset.respond(to: $0) }
        let driver = BoseHeadphoneDriver(device: device, transport: transport)
        try await driver.connect()

        func nameReads() async -> Int {
            await transport.sent.filter { Array($0.prefix(2)) == [1, 2] }.count
        }
        let first = try await driver.refreshState()
        let second = try await driver.refreshState()
        #expect(second.name == first.name)
        #expect(second.firmwareVersion == first.firmwareVersion)
        #expect(await nameReads() == 1)
    }

    @Test func aMalformedBatteryReportKeepsTheLastLevel() async throws {
        let headset = SimulatedHeadset()
        let transport = MockTransport { headset.respond(to: $0) }
        let driver = BoseHeadphoneDriver(device: device, transport: transport)
        try await driver.connect()
        _ = try await driver.refreshState()

        var events = driver.events.makeAsyncIterator()
        await transport.deliver([2, 2, 3, 1, 200])
        await transport.deliver([31, 3, 3, 1, 1])
        var battery: BatteryStatus?
        while let event = await events.next() {
            if case .stateChanged(let state) = event, state.mode == .preset("aware") {
                battery = state.battery
                break
            }
        }
        #expect(battery?.percent == 90)
    }

    @Test func refreshSurvivesARefusedFunction() async throws {
        let headset = SimulatedHeadset()
        headset.state.withLock { $0.refused = [BoseAddress.multipoint] }
        let (driver, _) = try await connected(headset)
        let state = try await driver.refreshState()
        #expect(state.multipoint == nil)
        #expect(state.battery?.percent == 90)
    }

    @Test func modeChangePicksUpTheDevicesSettings() async throws {
        let (driver, _) = try await connected()
        try await driver.perform(.setMode("aware"))
        let state = try await driver.refreshState()
        #expect(state.mode == .preset("aware"))
        #expect(state.noiseLevel == 0)
    }

    @Test func partialAudioChangeKeepsOtherValues() async throws {
        let (driver, headset) = try await connected()
        try await driver.perform(.setMode("immersion"))
        try await driver.perform(.setAudio(noiseLevel: 5, spatial: nil, windBlock: nil))
        #expect(headset.state.withLock { $0.audio } == [5, 0, 2, 0, 1])
        #expect(try await driver.refreshState().mode == .custom)
    }

    @Test func audioChangeWorksWithoutAnEarlierRead() async throws {
        let (driver, headset) = try await connected()
        try await driver.perform(.setAudio(noiseLevel: nil, spatial: nil, windBlock: true))
        #expect(headset.state.withLock { $0.audio } == [0, 0, 0, 1, 1])
    }

    @Test func equalizerChangeUsesTheResponse() async throws {
        let (driver, headset) = try await connected()
        try await driver.perform(.setEqualizerBand(id: 2, value: -10))
        #expect(headset.state.withLock { $0.equalizer } == [1, -1, -10])
    }

    @Test func multipointChangesOnlyBitZero() async throws {
        let (driver, headset) = try await connected()
        try await driver.perform(.setMultipoint(false))
        #expect(headset.state.withLock { $0.multipoint } == 0x06)
        try await driver.perform(.setMultipoint(true))
        #expect(headset.state.withLock { $0.multipoint } == 0x07)
    }

    @Test func refusesCommandsTheDeviceCannotDo() async throws {
        let (driver, _) = try await connected()
        await #expect(throws: DriverError.unsupported) {
            try await driver.perform(.rename("New"))
        }
        await #expect(throws: DriverError.unsupported) {
            try await driver.perform(.setEqualizerBand(id: 0, value: 11))
        }
    }

    @Test func pausesTheActiveSource() async throws {
        let (driver, headset) = try await connected()
        try await driver.perform(.pausePlayback)
        #expect(headset.state.withLock { $0.paused })
    }

    @Test func connectingSendsTheLeadingZeroAndAcceptsProcessing() async throws {
        let (driver, headset) = try await connected()
        try await driver.perform(.connectSource(BoseStateCodec.sourceID(SimulatedHeadset.otherMac)))
        #expect(headset.state.withLock { $0.connectRequest } == [0] + SimulatedHeadset.otherMac)
    }

    @Test func routingIsNotOffered() async throws {
        let (driver, _) = try await connected()
        await #expect(throws: DriverError.unsupported) {
            try await driver.perform(.switchSource(BoseStateCodec.sourceID(SimulatedHeadset.otherMac)))
        }
    }

    @Test func authenticationGateHidesTheFeatureAndStopsRetrying() async throws {
        let headset = SimulatedHeadset()
        headset.state.withLock { $0.refused = [BoseAddress.multipoint] }
        let (driver, _) = try await connected(headset)
        await #expect(throws: DriverError.authenticationRequired) {
            try await driver.perform(.setMultipoint(true))
        }
        #expect(await driver.capabilities.multipoint == nil)
        await #expect(throws: DriverError.unsupported) {
            try await driver.perform(.setMultipoint(true))
        }
    }

    @Test func appliesChangesTheDeviceReportsByItself() async throws {
        let headset = SimulatedHeadset()
        let transport = MockTransport { headset.respond(to: $0) }
        let driver = BoseHeadphoneDriver(device: device, transport: transport)
        var events = driver.events.makeAsyncIterator()
        try await driver.connect()

        await transport.deliver([31, 3, 3, 1, 1])
        while let event = await events.next() {
            if case .stateChanged(let state) = event {
                #expect(state.mode == .preset("aware"))
                break
            }
        }
    }

    @Test func offersEveryVerifiedCapability() async throws {
        let (driver, _) = try await connected()
        let capabilities = await driver.capabilities
        #expect(capabilities.sections == DeviceSection.allCases)
        #expect(capabilities.rename == nil)
    }
}
