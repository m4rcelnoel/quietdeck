import Foundation
import QuietDeckCore
import Testing

@testable import QuietDeckTesting

private let timing = CommandScheduler.Configuration(sliderDelay: .milliseconds(10), discreteDelay: .milliseconds(1))

@MainActor
private func connected(
    _ capabilities: DeviceCapabilities = Fixtures.fullCapabilities,
    _ state: DeviceState = Fixtures.fullState,
    refreshInterval: Duration = .seconds(60)
) async -> (DeviceController, MockDriver) {
    let driver = MockDriver(capabilities: capabilities, state: state)
    let controller = DeviceController(
        driver: driver, schedulerConfiguration: timing, refreshInterval: refreshInterval
    )
    await controller.connect()
    return (controller, driver)
}

/// Waits for a condition that depends on background work.
@MainActor
private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return false
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct DeviceControllerTests {
    @Test func connectingReadsTheDevice() async {
        let (controller, _) = await connected()
        #expect(controller.phase == .connected)
        #expect(controller.state.battery?.percent == 74)
        #expect(controller.capabilities == Fixtures.fullCapabilities)
    }

    @Test func aFailedConnectionIsReported() async {
        let driver = MockDriver(capabilities: Fixtures.fullCapabilities, state: Fixtures.fullState)
        await driver.failNext(with: .busy)
        let controller = DeviceController(driver: driver, schedulerConfiguration: timing)
        await controller.connect()
        #expect(controller.phase == .connectionFailed)
    }

    @Test func aDeviceThatAppearsLaterIsPolled() async {
        let driver = MockDriver(capabilities: Fixtures.fullCapabilities, state: Fixtures.fullState)
        await driver.failNext(with: .transportFailed("off"))
        let controller = DeviceController(
            driver: driver, schedulerConfiguration: timing, refreshInterval: .milliseconds(10)
        )
        await controller.connect()
        #expect(controller.phase == .connectionFailed)

        await driver.simulateConnection(.connected)
        #expect(await eventually { controller.phase == .connected })
        await driver.simulateSilentChange { $0.battery = BatteryStatus(percent: 12) }
        #expect(await eventually { controller.state.battery?.percent == 12 })
    }

    @Test func disconnectingForgetsWhatWasNotSent() async {
        let (controller, driver) = await connected()
        controller.setNoiseLevel(3)
        await controller.disconnect()
        #expect(controller.state.noiseLevel == Fixtures.fullState.noiseLevel)

        await controller.connect()
        await driver.simulateSilentChange { $0.battery = BatteryStatus(percent: 12) }
        await controller.refresh()
        #expect(controller.state.battery?.percent == 12)
        #expect(await driver.performed.isEmpty)
    }

    @Test func givingUpForgetsWhatWasNotSent() async {
        let (controller, driver) = await connected()
        controller.setNoiseLevel(3)
        await driver.simulateConnection(.disconnected)
        #expect(await eventually { controller.phase == .disconnected })
        #expect(controller.state.noiseLevel == Fixtures.fullState.noiseLevel)
    }

    @Test func changesShowImmediately() async {
        let (controller, _) = await connected()
        controller.setNoiseLevel(3)
        #expect(controller.state.noiseLevel == 3)
        #expect(controller.state.mode == .custom)
    }

    @Test func draggingSendsOnlyTheFinalValue() async {
        let (controller, driver) = await connected()
        for level in 0...9 {
            controller.setNoiseLevel(level)
        }
        #expect(await eventually { await driver.performed.count == 1 })
        #expect(await driver.performed == [.setAudio(noiseLevel: 9, spatial: nil, windBlock: nil)])
    }

    @Test func aPresetClearsCustom() async {
        let (controller, driver) = await connected()
        controller.setNoiseLevel(3)
        #expect(await eventually { await !driver.performed.isEmpty })
        controller.selectMode("aware")
        #expect(controller.state.mode == .preset("aware"))
        #expect(await eventually { await driver.performed.contains(.setMode("aware")) })
    }

    @Test func aFailureFallsBackToTheConfirmedValue() async {
        let (controller, driver) = await connected()
        await driver.failNext(with: .timeout)
        controller.setNoiseLevel(3)
        #expect(controller.state.noiseLevel == 3)
        #expect(await eventually { controller.problem != nil })
        #expect(controller.state.noiseLevel == 10)
        #expect(controller.state.mode == .preset("quiet"))
        #expect(controller.problem == .init(control: .noiseLevel, kind: .failed))
    }

    @Test func authenticationFailuresReadAsNotAvailable() async {
        let (controller, driver) = await connected()
        await driver.failNext(with: .authenticationRequired)
        controller.setMultipoint(false)
        #expect(await eventually { controller.problem != nil })
        #expect(controller.problem == .init(control: .multipoint, kind: .notAvailable))
        #expect(controller.state.multipoint == true)
    }

    @Test func anEqualizerFailureOnlyRestoresThatBand() async {
        let (controller, driver) = await connected()
        await driver.failNext(with: .timeout)
        controller.setEqualizerBand(1, value: 5)
        #expect(controller.state.equalizer?.map(\.value) == [2, 5, 1])
        #expect(await eventually { controller.problem != nil })
        #expect(controller.state.equalizer?.map(\.value) == [2, 0, 1])
    }

    @Test func aNewChangeClearsTheOldProblem() async {
        let (controller, driver) = await connected()
        await driver.failNext(with: .timeout)
        controller.setWindBlock(true)
        #expect(await eventually { controller.problem != nil })
        controller.setWindBlock(true)
        #expect(controller.problem == nil)
    }

    @Test func windBlockMasksNoiseControl() async {
        let (controller, _) = await connected()
        #expect(!controller.isNoiseControlMasked)
        controller.setWindBlock(true)
        #expect(controller.isNoiseControlMasked)
    }

    @Test func refreshPicksUpChangesMadeOnTheDevice() async {
        let (controller, driver) = await connected()
        await driver.simulateSilentChange { $0.mode = .preset("cinema") }
        await controller.refresh()
        #expect(controller.state.mode == .preset("cinema"))
    }

    @Test func pollingFindsChangesWithoutBeingAsked() async {
        let (controller, driver) = await connected(refreshInterval: .milliseconds(5))
        await driver.simulateSilentChange { $0.mode = .preset("cinema") }
        #expect(await eventually { controller.state.mode == .preset("cinema") })
    }

    @Test func refreshDoesNotUndoAPendingChange() async {
        let (controller, driver) = await connected()
        await driver.simulateSilentChange { $0.noiseLevel = 1 }
        controller.setNoiseLevel(7)
        await controller.refresh()
        #expect(controller.state.noiseLevel == 7)
    }

    @Test func reportedChangesUpdateTheState() async {
        let (controller, driver) = await connected()
        await driver.simulateDeviceChange { $0.battery = BatteryStatus(percent: 12) }
        #expect(await eventually { controller.state.battery?.percent == 12 })
    }

    @Test func aDisabledFeatureDisappears() async {
        let (controller, driver) = await connected()
        await driver.simulateCapabilityChange(Fixtures.limitedCapabilities)
        #expect(await eventually { controller.capabilities == Fixtures.limitedCapabilities })
    }

    @Test func switchingShowsProgressThenClears() async {
        let (controller, driver) = await connected()
        controller.switchSource(to: "AA:AA:AA:AA:AA:02")
        #expect(controller.switchingSource == "AA:AA:AA:AA:AA:02")
        #expect(await eventually { controller.switchingSource == nil })
        #expect(await eventually { controller.state.sources?.active?.name == "Studio Mac" })
        _ = driver
    }

    @Test func aFailedSwitchReportsAProblem() async {
        let (controller, driver) = await connected()
        await driver.failNext(with: .rejected(code: 4, reason: "functionNotSupported"))
        controller.switchSource(to: "AA:AA:AA:AA:AA:02")
        #expect(await eventually { controller.problem != nil })
        #expect(controller.problem == .init(control: .source, kind: .failed))
        #expect(controller.switchingSource == nil)
    }

    @Test func losingTheConnectionDropsPendingChanges() async {
        let (controller, driver) = await connected()
        controller.setNoiseLevel(3)
        await driver.simulateConnection(.connecting)
        #expect(await eventually { controller.phase == .connecting })
        #expect(controller.state.noiseLevel == 10)
    }

    @Test func reportsNewBatteryReadingsOnce() async {
        let (controller, driver) = await connected()
        var readings: [Int] = []
        controller.onBatteryReading = { readings.append($0) }
        await driver.simulateSilentChange { $0.battery = BatteryStatus(percent: 19) }
        await controller.refresh()
        await controller.refresh()
        #expect(readings == [19])
    }

    @Test func reportsPhaseChanges() async {
        let (controller, driver) = await connected()
        var phases: [DeviceController.Phase] = []
        controller.onPhaseChange = { phases.append($0) }
        await driver.simulateConnection(.connecting)
        #expect(await eventually { phases == [.connecting] })
    }

    @Test func reconnectingReadsTheDeviceAgain() async {
        let (controller, driver) = await connected()
        await driver.simulateConnection(.connecting)
        #expect(await eventually { controller.phase == .connecting })
        await driver.simulateSilentChange { $0.mode = .preset("cinema") }
        await driver.simulateConnection(.connected)
        #expect(await eventually { controller.state.mode == .preset("cinema") })
    }
}

private actor FakeStream: LocalAudioStream {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let onStart: @Sendable () async -> Void

    init(onStart: @escaping @Sendable () async -> Void) {
        self.onStart = onStart
    }

    func start() async {
        startCount += 1
        await onStart()
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct BringAudioHereTests {
    private let local = "AA:AA:AA:AA:AA:01"
    private let other = "AA:AA:AA:AA:AA:02"

    private func phoneIsActive() -> DeviceState {
        var state = Fixtures.fullState
        state.sources = AudioSourceList(sources: [
            AudioSource(id: local, name: "This Mac", kind: .computer, status: .connected),
            AudioSource(id: other, name: "iPhone", kind: .phone, status: .active),
        ])
        return state
    }

    private func setUp() async -> (DeviceController, MockDriver) {
        let driver = MockDriver(capabilities: Fixtures.fullCapabilities, state: phoneIsActive())
        let controller = DeviceController(
            driver: driver, schedulerConfiguration: timing, takeoverPause: .milliseconds(1)
        )
        controller.localSourceID = local
        await controller.connect()
        return (controller, driver)
    }

    private func takeOver(_ driver: MockDriver) -> FakeStream {
        let local = local
        return FakeStream {
            await driver.simulateSilentChange { state in
                state.sources = AudioSourceList(
                    sources: (state.sources?.sources ?? []).map { source in
                        var source = source
                        source.status = source.id == local ? .active : .connected
                        return source
                    }
                )
            }
        }
    }

    @Test func pausesThenStreamsThenStops() async {
        let (controller, driver) = await setUp()
        let stream = takeOver(driver)
        controller.localStream = stream
        await controller.bringAudioHere()
        #expect(await driver.performed == [.pausePlayback])
        #expect(controller.state.sources?.active?.id == local)
        #expect(await stream.startCount == 1)
        #expect(await stream.stopCount == 1)
        #expect(controller.switchingSource == nil)
        #expect(controller.problem == nil)
    }

    @Test func nothingPlayingIsNotAFailure() async {
        let (controller, driver) = await setUp()
        controller.localStream = takeOver(driver)
        await driver.failNext(with: .rejected(code: 6, reason: "invalidData"))
        await controller.bringAudioHere()
        #expect(controller.state.sources?.active?.id == local)
        #expect(controller.problem == nil)
    }

    @Test func reportsAProblemIfTheSourceStays() async {
        let (controller, _) = await setUp()
        let stream = FakeStream {}
        controller.localStream = stream
        await controller.bringAudioHere()
        #expect(controller.problem == .init(control: .source, kind: .failed))
        #expect(await stream.stopCount == 1)
    }

    @Test func aFailedPauseStopsEarly() async {
        let (controller, driver) = await setUp()
        let stream = takeOver(driver)
        controller.localStream = stream
        await driver.failNext(with: .timeout)
        await controller.bringAudioHere()
        #expect(controller.problem == .init(control: .source, kind: .failed))
        #expect(await stream.startCount == 0)
    }

    @Test func doesNothingWithoutAStream() async {
        let (controller, driver) = await setUp()
        await controller.bringAudioHere()
        #expect(await driver.performed.isEmpty)
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct ConnectSourceTests {
    private let remembered = "AA:AA:AA:AA:AA:03"

    private func setUp() async -> (DeviceController, MockDriver) {
        let driver = MockDriver(capabilities: Fixtures.fullCapabilities, state: Fixtures.fullState)
        let controller = DeviceController(
            driver: driver, schedulerConfiguration: timing, connectPollInterval: .milliseconds(1)
        )
        await controller.connect()
        return (controller, driver)
    }

    @Test func aSuccessfulConnectionShowsAsConnected() async {
        let (controller, _) = await setUp()
        await controller.connectSource(remembered)
        let source = controller.state.sources?.sources.first { $0.id == remembered }
        #expect(source?.status == .connected)
        #expect(controller.problem == nil)
        #expect(controller.connectingSource == nil)
    }

    @Test func aDeviceThatNeverConnectsReportsAProblem() async {
        let (controller, driver) = await setUp()
        await driver.failNext(with: .rejected(code: 13, reason: "unrecognized"))
        await controller.connectSource(remembered)
        #expect(controller.problem == .init(control: .connection, kind: .failed))
    }

    @Test func keepsWaitingWhileTheHeadsetIsConnecting() async {
        let (controller, driver) = await setUp()
        await driver.simulateSilentChange { state in
            state.sources?.isConnecting = true
        }
        let attempt = Task { await controller.connectSource(remembered) }
        try? await Task.sleep(for: .milliseconds(5))
        #expect(controller.connectingSource == remembered)
        await driver.simulateSilentChange { state in
            state.sources?.isConnecting = false
        }
        await attempt.value
        #expect(controller.connectingSource == nil)
    }

    @Test func aLostSessionIsAProblem() async {
        let (controller, driver) = await setUp()
        await driver.failNext(with: .timeout)
        await controller.connectSource(remembered)
        #expect(controller.problem == .init(control: .connection, kind: .failed))
    }
}

@MainActor
@Suite struct EqualizerPresetStoreTests {
    private func store() -> EqualizerPresetStore {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return EqualizerPresetStore(defaults: defaults)
    }

    private let bands = [EqualizerBandValue(id: 0, value: 2), EqualizerBandValue(id: 1, value: -1)]

    @Test func savesAndFindsAMatch() {
        let store = store()
        let preset = store.save(name: "Warm", bands: bands)
        #expect(store.preset(matching: bands) == preset)
        #expect(store.preset(matching: [EqualizerBandValue(id: 0, value: 9)]) == nil)
    }

    @Test func renamesAndDeletes() {
        let store = store()
        let preset = store.save(name: "Warm", bands: bands)
        store.rename(preset.id, to: "Cozy")
        #expect(store.presets.first?.name == "Cozy")
        store.delete(preset.id)
        #expect(store.presets.isEmpty)
    }

    @Test func repeatedBandsDoNotCrash() {
        let repeated = [EqualizerBandValue(id: 0, value: 1), EqualizerBandValue(id: 0, value: 2)]
        #expect(store().preset(matching: repeated) == nil)
    }

    @Test func survivesRelaunch() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        EqualizerPresetStore(defaults: defaults).save(name: "Warm", bands: bands)
        #expect(EqualizerPresetStore(defaults: defaults).presets.map(\.name) == ["Warm"])
    }
}
