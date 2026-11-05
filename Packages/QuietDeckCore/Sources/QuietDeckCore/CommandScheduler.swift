/// Debounces commands so dragging a slider doesn't flood the device.
///
/// Commands of the same kind replace each other: only the latest value is sent. Partial
/// audio commands are merged, so changing noise and wind in one window sends both.
///
/// Lives on the main actor so that `submit` runs synchronously: going through a task to
/// reach an actor wouldn't keep commands in order, and a stale value could win.
@MainActor
public final class CommandScheduler {
    public struct Configuration: Sendable {
        public var sliderDelay: Duration
        public var discreteDelay: Duration

        public init(sliderDelay: Duration = .milliseconds(500), discreteDelay: Duration = .milliseconds(150)) {
            self.sliderDelay = sliderDelay
            self.discreteDelay = discreteDelay
        }
    }

    private enum Key: Hashable {
        case mode, audio, multipoint, source, pause, rename
        case equalizer(EqualizerBand.ID)
    }

    private struct Pending {
        var command: DeviceCommand
        var task: Task<Void, Never>
    }

    private let configuration: Configuration
    private let execute: @MainActor (DeviceCommand) async -> Void
    private var pending: [Key: Pending] = [:]

    public init(
        configuration: Configuration = Configuration(),
        execute: @escaping @MainActor (DeviceCommand) async -> Void
    ) {
        self.configuration = configuration
        self.execute = execute
    }

    public func submit(_ command: DeviceCommand) {
        let key = Self.key(for: command)
        var merged = command
        if let previous = pending.removeValue(forKey: key) {
            previous.task.cancel()
            merged = Self.merge(previous.command, into: command)
        }

        // A new mode replaces all audio settings, so older audio changes are moot.
        if key == .mode, let audio = pending.removeValue(forKey: .audio) {
            audio.task.cancel()
        }

        let delay = Self.isSliderCommand(merged) ? configuration.sliderDelay : configuration.discreteDelay
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.fire(key)
        }
        pending[key] = Pending(command: merged, task: task)
    }

    /// Drops everything not yet sent, for example after losing the connection.
    public func cancelAll() {
        for item in pending.values {
            item.task.cancel()
        }
        pending = [:]
    }

    private func fire(_ key: Key) async {
        guard let item = pending.removeValue(forKey: key) else { return }
        await execute(item.command)
    }

    private static func key(for command: DeviceCommand) -> Key {
        switch command {
        case .setMode: return .mode
        case .setAudio: return .audio
        case .setEqualizerBand(let id, _): return .equalizer(id)
        case .setMultipoint: return .multipoint
        case .switchSource, .connectSource: return .source
        case .pausePlayback: return .pause
        case .rename: return .rename
        }
    }

    private static func isSliderCommand(_ command: DeviceCommand) -> Bool {
        switch command {
        case .setEqualizerBand:
            return true
        case .setAudio(let noiseLevel, _, _):
            return noiseLevel != nil
        case .setMode, .setMultipoint, .switchSource, .connectSource, .pausePlayback, .rename:
            return false
        }
    }

    private static func merge(_ older: DeviceCommand, into newer: DeviceCommand) -> DeviceCommand {
        guard case .setAudio(let oldNoise, let oldSpatial, let oldWind) = older,
            case .setAudio(let noise, let spatial, let wind) = newer
        else { return newer }
        return .setAudio(noiseLevel: noise ?? oldNoise, spatial: spatial ?? oldSpatial, windBlock: wind ?? oldWind)
    }
}
