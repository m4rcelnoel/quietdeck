/// Live device values. A `nil` value means "not read yet", not "unsupported".
public struct DeviceState: Sendable, Equatable {
    public var mode: ListeningModeSelection?
    public var noiseLevel: Int?
    public var spatialAudio: SpatialAudioMode?
    public var windBlock: Bool?
    public var equalizer: [EqualizerBandValue]?
    public var battery: BatteryStatus?
    public var sources: AudioSourceList?
    public var multipoint: Bool?
    public var name: String?
    public var firmwareVersion: String?

    public init(
        mode: ListeningModeSelection? = nil,
        noiseLevel: Int? = nil,
        spatialAudio: SpatialAudioMode? = nil,
        windBlock: Bool? = nil,
        equalizer: [EqualizerBandValue]? = nil,
        battery: BatteryStatus? = nil,
        sources: AudioSourceList? = nil,
        multipoint: Bool? = nil,
        name: String? = nil,
        firmwareVersion: String? = nil
    ) {
        self.mode = mode
        self.noiseLevel = noiseLevel
        self.spatialAudio = spatialAudio
        self.windBlock = windBlock
        self.equalizer = equalizer
        self.battery = battery
        self.sources = sources
        self.multipoint = multipoint
        self.name = name
        self.firmwareVersion = firmwareVersion
    }
}

public enum ListeningModeSelection: Sendable, Equatable {
    case preset(ListeningMode.ID)
    /// The device left its saved mode after a manual change.
    case custom
}

public struct EqualizerBandValue: Sendable, Equatable {
    public var id: EqualizerBand.ID
    public var value: Int

    public init(id: EqualizerBand.ID, value: Int) {
        self.id = id
        self.value = value
    }
}

public struct BatteryStatus: Sendable, Equatable {
    public var percent: Int
    public var isCharging: Bool?

    public init(percent: Int, isCharging: Bool? = nil) {
        self.percent = percent
        self.isCharging = isCharging
    }
}

public struct AudioSource: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case computer, phone, tablet, auxiliary, unknown
    }

    public enum Status: Sendable, Equatable {
        case active, connected, remembered
    }

    /// Normalized Bluetooth address, or a driver-defined identifier for wired sources.
    public typealias ID = String

    public var id: ID
    public var name: String
    public var kind: Kind
    public var status: Status

    public init(id: ID, name: String, kind: Kind, status: Status) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
    }
}

public struct AudioSourceList: Sendable, Equatable {
    public var sources: [AudioSource]
    /// A connection attempt is running, so statuses may still change.
    public var isConnecting: Bool

    public init(sources: [AudioSource], isConnecting: Bool = false) {
        self.sources = sources
        self.isConnecting = isConnecting
    }

    public var active: AudioSource? {
        sources.first { $0.status == .active }
    }

    /// Active first, then connected, then remembered, so a short list keeps what matters.
    public var byStatus: [AudioSource] {
        [AudioSource.Status.active, .connected, .remembered].flatMap(sources(with:))
    }

    public func sources(with status: AudioSource.Status) -> [AudioSource] {
        sources.filter { $0.status == status }
    }
}
