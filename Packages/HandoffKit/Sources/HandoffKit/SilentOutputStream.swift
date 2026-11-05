import AVFoundation
import QuietDeckCore

/// Plays silence on the default output. Headphones treat this like any other stream,
/// which is what lets this Mac take over once the line is free.
@MainActor
public final class SilentOutputStream: LocalAudioStream {
    private var engine: AVAudioEngine?

    public nonisolated init() {}

    public func start() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let frames: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames

        do {
            try engine.start()
        } catch {
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        self.engine = engine
    }

    public func stop() {
        engine?.stop()
        engine = nil
    }
}
