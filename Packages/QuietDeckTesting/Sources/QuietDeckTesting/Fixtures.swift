import QuietDeckCore

/// Sample devices for tests and previews.
public enum Fixtures {
    public static let modes = [
        ListeningMode(id: "quiet", name: "Quiet", kind: .quiet),
        ListeningMode(id: "aware", name: "Aware", kind: .aware),
        ListeningMode(id: "immersion", name: "Immersion", kind: .immersion),
        ListeningMode(id: "cinema", name: "Cinema", kind: .cinema),
    ]

    /// A device with every capability.
    public static let fullCapabilities = DeviceCapabilities(
        listeningModes: ListeningModesCapability(modes: modes),
        noiseControl: LevelCapability(range: 0...10),
        spatialAudio: OptionsCapability(options: SpatialAudioMode.allCases),
        windBlock: ToggleCapability(),
        equalizer: EqualizerCapability(
            bands: [
                EqualizerBand(id: 0, name: "Bass"),
                EqualizerBand(id: 1, name: "Mid"),
                EqualizerBand(id: 2, name: "Treble"),
            ],
            range: -10...10
        ),
        battery: BatteryCapability(reportsCharging: true),
        audioSources: AudioSourcesCapability(canSwitch: true, listsRememberedDevices: true, canConnect: true),
        multipoint: ToggleCapability(),
        rename: RenameCapability(maxLength: 31)
    )

    public static let fullState = DeviceState(
        mode: .preset("quiet"),
        noiseLevel: 10,
        spatialAudio: .off,
        windBlock: false,
        equalizer: [
            EqualizerBandValue(id: 0, value: 2),
            EqualizerBandValue(id: 1, value: 0),
            EqualizerBandValue(id: 2, value: 1),
        ],
        battery: BatteryStatus(percent: 74, isCharging: false),
        sources: AudioSourceList(sources: [
            AudioSource(id: "AA:AA:AA:AA:AA:01", name: "This Mac", kind: .computer, status: .active),
            AudioSource(id: "AA:AA:AA:AA:AA:02", name: "Studio Mac", kind: .computer, status: .connected),
            AudioSource(id: "AA:AA:AA:AA:AA:03", name: "iPhone", kind: .phone, status: .remembered),
        ]),
        multipoint: true,
        name: "Mock Headphones",
        firmwareVersion: "1.0.0"
    )

    /// A device with modes and battery only, for checking capability-driven layouts.
    public static let limitedCapabilities = DeviceCapabilities(
        listeningModes: ListeningModesCapability(modes: Array(modes.prefix(2))),
        battery: BatteryCapability(reportsCharging: false)
    )

    public static let limitedState = DeviceState(
        mode: .preset("quiet"),
        battery: BatteryStatus(percent: 41),
        name: "Mock Basic"
    )
}
