import Foundation

/// A named set of equalizer values, saved on this Mac.
public struct EqualizerPreset: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// Values by band ID.
    public var values: [Int: Int]

    public init(id: UUID = UUID(), name: String, values: [Int: Int]) {
        self.id = id
        self.name = name
        self.values = values
    }
}

/// The user's equalizer presets.
@MainActor
@Observable
public final class EqualizerPresetStore {
    private static let key = "equalizerPresets"

    public private(set) var presets: [EqualizerPreset]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets =
            defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([EqualizerPreset].self, from: $0) } ?? []
    }

    /// The preset matching these values exactly, if any.
    public func preset(matching bands: [EqualizerBandValue]) -> EqualizerPreset? {
        let values = Self.values(of: bands)
        return presets.first { $0.values == values }
    }

    @discardableResult
    public func save(name: String, bands: [EqualizerBandValue]) -> EqualizerPreset {
        let preset = EqualizerPreset(name: name, values: Self.values(of: bands))
        presets.append(preset)
        persist()
        return preset
    }

    public func rename(_ id: EqualizerPreset.ID, to name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = name
        persist()
    }

    public func delete(_ id: EqualizerPreset.ID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    /// Bands come from the device, so a repeated ID must not be able to crash the app.
    private static func values(of bands: [EqualizerBandValue]) -> [Int: Int] {
        Dictionary(bands.map { ($0.id, $0.value) }) { _, latest in latest }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(presets), forKey: Self.key)
    }
}
