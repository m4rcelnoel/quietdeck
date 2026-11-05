/// Keeps this computer's audio output running, without anything audible.
public protocol LocalAudioStream: Sendable {
    func start() async
    func stop() async
}
