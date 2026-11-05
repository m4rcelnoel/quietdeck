/// Static description of what a device can do. The UI is built only from this.
///
/// A `nil` capability means the device can never do it, so the UI hides the control.
public struct DeviceCapabilities: Sendable, Equatable {
    public var listeningModes: ListeningModesCapability?
    public var noiseControl: LevelCapability?
    public var spatialAudio: OptionsCapability<SpatialAudioMode>?
    public var windBlock: ToggleCapability?
    public var equalizer: EqualizerCapability?
    public var battery: BatteryCapability?
    public var audioSources: AudioSourcesCapability?
    public var multipoint: ToggleCapability?
    public var rename: RenameCapability?

    public init(
        listeningModes: ListeningModesCapability? = nil,
        noiseControl: LevelCapability? = nil,
        spatialAudio: OptionsCapability<SpatialAudioMode>? = nil,
        windBlock: ToggleCapability? = nil,
        equalizer: EqualizerCapability? = nil,
        battery: BatteryCapability? = nil,
        audioSources: AudioSourcesCapability? = nil,
        multipoint: ToggleCapability? = nil,
        rename: RenameCapability? = nil
    ) {
        self.listeningModes = listeningModes
        self.noiseControl = noiseControl
        self.spatialAudio = spatialAudio
        self.windBlock = windBlock
        self.equalizer = equalizer
        self.battery = battery
        self.audioSources = audioSources
        self.multipoint = multipoint
        self.rename = rename
    }
}

public struct ListeningMode: Sendable, Equatable, Identifiable {
    /// Selects the symbol and default name, so the UI needs no vendor knowledge.
    public enum Kind: Sendable, Equatable {
        case quiet, aware, immersion, cinema, other
    }

    public typealias ID = String

    public var id: ID
    public var name: String
    public var kind: Kind

    public init(id: ID, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct ListeningModesCapability: Sendable, Equatable {
    public var modes: [ListeningMode]

    public init(modes: [ListeningMode]) {
        self.modes = modes
    }
}

public struct LevelCapability: Sendable, Equatable {
    public var range: ClosedRange<Int>

    public init(range: ClosedRange<Int>) {
        self.range = range
    }
}

public struct OptionsCapability<Option: Sendable & Equatable>: Sendable, Equatable {
    public var options: [Option]

    public init(options: [Option]) {
        self.options = options
    }
}

public struct ToggleCapability: Sendable, Equatable {
    public init() {}
}

public enum SpatialAudioMode: Sendable, Equatable, CaseIterable {
    case off, still, motion
}

public struct EqualizerBand: Sendable, Equatable, Identifiable {
    public typealias ID = Int

    public var id: ID
    public var name: String

    public init(id: ID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct EqualizerCapability: Sendable, Equatable {
    public var bands: [EqualizerBand]
    public var level: LevelCapability

    public init(bands: [EqualizerBand], range: ClosedRange<Int>) {
        self.bands = bands
        self.level = LevelCapability(range: range)
    }
}

public struct BatteryCapability: Sendable, Equatable {
    public var reportsCharging: Bool

    public init(reportsCharging: Bool) {
        self.reportsCharging = reportsCharging
    }
}

public struct AudioSourcesCapability: Sendable, Equatable {
    public var canSwitch: Bool
    public var listsRememberedDevices: Bool
    public var canConnect: Bool

    public init(canSwitch: Bool, listsRememberedDevices: Bool, canConnect: Bool = false) {
        self.canSwitch = canSwitch
        self.listsRememberedDevices = listsRememberedDevices
        self.canConnect = canConnect
    }
}

public struct RenameCapability: Sendable, Equatable {
    public var maxLength: Int

    public init(maxLength: Int) {
        self.maxLength = maxLength
    }
}

/// Sidebar sections of the main window.
public enum DeviceSection: Sendable, Equatable, CaseIterable {
    case listening, sound, sources, device
}

extension DeviceCapabilities {
    /// The sections to show. A section never appears empty; `device` is always present.
    public var sections: [DeviceSection] {
        var result: [DeviceSection] = []
        if listeningModes != nil || noiseControl != nil || spatialAudio != nil || windBlock != nil {
            result.append(.listening)
        }
        if equalizer != nil {
            result.append(.sound)
        }
        if audioSources != nil {
            result.append(.sources)
        }
        result.append(.device)
        return result
    }

    /// Whether a command can be sent to this device at all.
    public func supports(_ command: DeviceCommand) -> Bool {
        switch command {
        case .setMode(let id):
            return listeningModes?.modes.contains { $0.id == id } ?? false
        case .setAudio(let noiseLevel, let spatial, let windBlock):
            guard noiseLevel != nil || spatial != nil || windBlock != nil else { return false }
            if let noiseLevel, noiseControl?.range.contains(noiseLevel) != true { return false }
            if let spatial, spatialAudio?.options.contains(spatial) != true { return false }
            if windBlock != nil, self.windBlock == nil { return false }
            return true
        case .setEqualizerBand(let id, let value):
            guard let equalizer else { return false }
            return equalizer.level.range.contains(value) && equalizer.bands.contains { $0.id == id }
        case .setMultipoint:
            return multipoint != nil
        case .switchSource:
            return audioSources?.canSwitch ?? false
        case .pausePlayback:
            return audioSources != nil
        case .connectSource:
            return audioSources?.canConnect ?? false
        case .rename(let name):
            guard let rename else { return false }
            return !name.isEmpty && name.count <= rename.maxLength
        }
    }
}
