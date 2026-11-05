import QuietDeckCore

/// The five bytes of `[31.10]`. `cnc` is inverted: 0 is full noise cancellation.
struct BoseAudioSettings: Equatable, Sendable {
    var cnc: UInt8
    var spatial: UInt8
    var wind: UInt8
    var anc: UInt8

    /// `auto_cnc` always stays 0, because the device rejects anything else.
    var payload: [UInt8] {
        [cnc, 0, spatial, wind, anc]
    }
}

/// One entry of `[4.5]`.
struct BoseDeviceInfo: Equatable, Sendable {
    var address: [UInt8]
    var isConnected: Bool
    var kind: AudioSource.Kind
    var name: String
}

/// Converts between BMAP payloads and vendor-neutral values. Every function here is
/// pure, so all of it is tested against payloads recorded from real hardware.
enum BoseStateCodec {
    static let noiseLevels = 0...10

    static let modes = [
        ListeningMode(id: "quiet", name: "Quiet", kind: .quiet),
        ListeningMode(id: "aware", name: "Aware", kind: .aware),
        ListeningMode(id: "immersion", name: "Immersion", kind: .immersion),
        ListeningMode(id: "cinema", name: "Cinema", kind: .cinema),
    ]

    static let bands = [
        EqualizerBand(id: 0, name: "Bass"),
        EqualizerBand(id: 1, name: "Mid"),
        EqualizerBand(id: 2, name: "Treble"),
    ]

    static func modeIndex(for id: ListeningMode.ID) -> UInt8? {
        modes.firstIndex { $0.id == id }.map(UInt8.init)
    }

    /// User-created modes aren't offered yet, so they count as custom.
    static func mode(_ payload: [UInt8]) -> ListeningModeSelection? {
        guard let index = payload.first else { return nil }
        return Int(index) < modes.count ? .preset(modes[Int(index)].id) : .custom
    }

    static func audioSettings(_ payload: [UInt8]) -> BoseAudioSettings? {
        guard payload.count >= 5 else { return nil }
        return BoseAudioSettings(cnc: payload[0], spatial: payload[2], wind: payload[3], anc: payload[4])
    }

    static func noiseLevel(_ settings: BoseAudioSettings) -> Int? {
        let level = noiseLevels.upperBound - Int(settings.cnc)
        return noiseLevels.contains(level) ? level : nil
    }

    static func cnc(forNoiseLevel level: Int) -> UInt8 {
        UInt8(noiseLevels.upperBound - level)
    }

    static func spatialMode(_ settings: BoseAudioSettings) -> SpatialAudioMode? {
        switch settings.spatial {
        case 0: return .off
        case 1: return .still
        case 2: return .motion
        default: return nil
        }
    }

    static func spatialByte(_ mode: SpatialAudioMode) -> UInt8 {
        switch mode {
        case .off: return 0
        case .still: return 1
        case .motion: return 2
        }
    }

    /// Records of `[min, max, current, band]`.
    static func equalizer(_ payload: [UInt8]) -> [EqualizerBandValue]? {
        guard !payload.isEmpty, payload.count.isMultiple(of: 4) else { return nil }
        return stride(from: 0, to: payload.count, by: 4).map { start in
            EqualizerBandValue(id: Int(payload[start + 3]), value: Int(Int8(bitPattern: payload[start + 2])))
        }
    }

    static func equalizerPayload(band: EqualizerBand.ID, value: Int) -> [UInt8] {
        [UInt8(bitPattern: Int8(value)), UInt8(band)]
    }

    static func batteryPercent(_ payload: [UInt8]) -> Int? {
        guard let percent = payload.first, percent <= 100 else { return nil }
        return Int(percent)
    }

    /// Bit 0 is the setting. The other bits stayed the same when it changed.
    static func multipoint(_ payload: [UInt8]) -> Bool? {
        payload.first.map { $0 & 1 == 1 }
    }

    /// `[flag, utf8...]`
    static func name(_ payload: [UInt8]) -> String? {
        guard payload.count > 1 else { return nil }
        return String(decoding: payload.dropFirst(), as: UTF8.self)
    }

    static func firmware(_ payload: [UInt8]) -> String? {
        guard !payload.isEmpty else { return nil }
        return String(decoding: payload.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// `[mac(6), status, type, unknown, name...]`. The name has a fixed offset: scanning
    /// for a marker byte fails, because the status byte can hold the same value.
    static func deviceInfo(_ payload: [UInt8]) -> BoseDeviceInfo? {
        guard payload.count >= 9 else { return nil }
        let kind: AudioSource.Kind
        switch payload[7] {
        case 1: kind = .computer
        case 2: kind = .phone
        default: kind = .unknown
        }
        return BoseDeviceInfo(
            address: Array(payload[0..<6]),
            isConnected: payload[6] & 0b01 != 0,
            kind: kind,
            name: String(decoding: payload[9...], as: UTF8.self)
        )
    }

    /// The address in `[supported(2), type, mac(6)]`, if a Bluetooth source is active.
    static func activeAddress(_ payload: [UInt8]) -> [UInt8]? {
        guard payload.count >= 9, payload[2] == 1 else { return nil }
        return Array(payload[3..<9])
    }

    /// The first byte of `[4.4]`. `05` was seen while connecting, then `03` with two
    /// devices connected, and `01` with one.
    static func isConnecting(_ deviceList: [UInt8]) -> Bool {
        (deviceList.first ?? 0) & 0b100 != 0
    }

    /// Splits a `[4.4]` payload into addresses, skipping empty slots.
    static func addresses(inDeviceList payload: [UInt8]) -> [[UInt8]] {
        let entries = payload.dropFirst()
        return stride(from: entries.startIndex, to: entries.endIndex - 5, by: 6).compactMap { start in
            let address = Array(entries[start..<(start + 6)])
            return address.allSatisfy { $0 == 0 } ? nil : address
        }
    }

    static func sourceID(_ address: [UInt8]) -> AudioSource.ID {
        FrameLogExport.hex(address, separator: ":").uppercased()
    }

    static func address(fromSourceID id: AudioSource.ID) -> [UInt8]? {
        let bytes = id.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        return bytes.count == 6 ? bytes : nil
    }

    /// `[5.1]` decides what's active, because it's the documented source of truth.
    static func sourceList(
        devices: [BoseDeviceInfo],
        activeAddress: [UInt8]?,
        isConnecting: Bool = false
    ) -> AudioSourceList {
        AudioSourceList(
            sources: devices.map { device in
                let status: AudioSource.Status
                if device.address == activeAddress {
                    status = .active
                } else if device.isConnected {
                    status = .connected
                } else {
                    status = .remembered
                }
                return AudioSource(
                    id: sourceID(device.address), name: device.name, kind: device.kind, status: status
                )
            },
            isConnecting: isConnecting
        )
    }
}
