import Testing

@testable import QuietDeckCore

private let quiet = ListeningMode(id: "quiet", name: "Quiet", kind: .quiet)

private let full = DeviceCapabilities(
    listeningModes: ListeningModesCapability(modes: [quiet]),
    noiseControl: LevelCapability(range: 0...10),
    spatialAudio: OptionsCapability(options: [.off, .still]),
    windBlock: ToggleCapability(),
    equalizer: EqualizerCapability(bands: [EqualizerBand(id: 0, name: "Bass")], range: -10...10),
    battery: BatteryCapability(reportsCharging: true),
    audioSources: AudioSourcesCapability(canSwitch: true, listsRememberedDevices: true),
    multipoint: ToggleCapability(),
    rename: RenameCapability(maxLength: 8)
)

@Suite struct SectionTests {
    @Test func fullDeviceShowsEverySection() {
        #expect(full.sections == [.listening, .sound, .sources, .device])
    }

    @Test func emptyDeviceStillShowsDeviceSection() {
        #expect(DeviceCapabilities().sections == [.device])
    }

    @Test func modesOnlyDeviceHidesSoundAndSources() {
        let limited = DeviceCapabilities(listeningModes: ListeningModesCapability(modes: [quiet]))
        #expect(limited.sections == [.listening, .device])
    }

    @Test func noiseControlAloneShowsListening() {
        let limited = DeviceCapabilities(noiseControl: LevelCapability(range: 0...10))
        #expect(limited.sections.contains(.listening))
    }
}

@Suite struct CommandSupportTests {
    @Test(arguments: [
        DeviceCommand.setMode("quiet"),
        .setAudio(noiseLevel: 10, spatial: nil, windBlock: nil),
        .setAudio(noiseLevel: nil, spatial: .still, windBlock: true),
        .setEqualizerBand(id: 0, value: -10),
        .setMultipoint(true),
        .switchSource("AA:BB"),
        .rename("Studio"),
    ])
    func fullDeviceSupports(command: DeviceCommand) {
        #expect(full.supports(command))
    }

    @Test(arguments: [
        DeviceCommand.setMode("cinema"),
        .setAudio(noiseLevel: nil, spatial: nil, windBlock: nil),
        .setAudio(noiseLevel: 11, spatial: nil, windBlock: nil),
        .setAudio(noiseLevel: nil, spatial: .motion, windBlock: nil),
        .setEqualizerBand(id: 1, value: 0),
        .setEqualizerBand(id: 0, value: 11),
        .rename(""),
        .rename("Far too long"),
    ])
    func fullDeviceRejects(command: DeviceCommand) {
        #expect(!full.supports(command))
    }

    @Test(arguments: [
        DeviceCommand.setMode("quiet"),
        .setAudio(noiseLevel: 1, spatial: nil, windBlock: nil),
        .setAudio(noiseLevel: nil, spatial: nil, windBlock: false),
        .setEqualizerBand(id: 0, value: 0),
        .setMultipoint(false),
        .switchSource("AA:BB"),
        .rename("Studio"),
    ])
    func emptyDeviceSupportsNothing(command: DeviceCommand) {
        #expect(!DeviceCapabilities().supports(command))
    }

    @Test func listOnlySourcesCannotSwitch() {
        let device = DeviceCapabilities(
            audioSources: AudioSourcesCapability(canSwitch: false, listsRememberedDevices: true)
        )
        #expect(!device.supports(.switchSource("AA:BB")))
    }
}

@Suite struct ValueTests {
    @Test func levelClampsToRange() {
        let level = LevelCapability(range: -10...10)
        #expect(level.clamp(-11) == -10)
        #expect(level.clamp(4) == 4)
        #expect(level.clamp(11) == 10)
    }

    @Test func sourceListFindsActiveAndGroups() {
        let list = AudioSourceList(sources: [
            AudioSource(id: "1", name: "Studio Mac", kind: .computer, status: .connected),
            AudioSource(id: "2", name: "This Mac", kind: .computer, status: .active),
            AudioSource(id: "3", name: "iPhone", kind: .phone, status: .remembered),
        ])
        #expect(list.active?.id == "2")
        #expect(list.sources(with: .remembered).map(\.id) == ["3"])
    }

    @Test func authenticationFailuresAreNeverRetried() {
        #expect(!DriverError.authenticationRequired.isRetryable)
        #expect(!DriverError.rejected(code: 6, reason: "Invalid data").isRetryable)
        #expect(DriverError.timeout.isRetryable)
    }
}
