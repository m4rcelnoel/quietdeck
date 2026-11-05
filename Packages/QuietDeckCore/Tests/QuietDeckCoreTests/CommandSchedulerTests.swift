import Testing

@testable import QuietDeckCore

private actor Sink {
    private(set) var commands: [DeviceCommand] = []

    func add(_ command: DeviceCommand) {
        commands.append(command)
    }
}

private let timing = CommandScheduler.Configuration(sliderDelay: .milliseconds(60), discreteDelay: .milliseconds(15))

@MainActor
private func scheduler(_ sink: Sink) -> CommandScheduler {
    CommandScheduler(configuration: timing) { await sink.add($0) }
}

/// Long enough for every delay above to have passed.
private func settle() async throws {
    try await Task.sleep(for: .milliseconds(180))
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct CommandSchedulerTests {
    @Test func sendsAfterTheDelayAndNotBefore() async throws {
        let sink = Sink()
        let scheduler = scheduler(sink)
        scheduler.submit(.setEqualizerBand(id: 0, value: 1))
        #expect(await sink.commands.isEmpty)
        try await settle()
        #expect(await sink.commands == [.setEqualizerBand(id: 0, value: 1)])
    }

    @Test func dragKeepsOnlyTheLastValue() async throws {
        let sink = Sink()
        let scheduler = scheduler(sink)
        for value in 0...10 {
            scheduler.submit(.setAudio(noiseLevel: value, spatial: nil, windBlock: nil))
        }
        try await settle()
        #expect(await sink.commands == [.setAudio(noiseLevel: 10, spatial: nil, windBlock: nil)])
    }

    @Test func eachBandIsIndependent() async throws {
        let sink = Sink()
        let scheduler = scheduler(sink)
        scheduler.submit(.setEqualizerBand(id: 0, value: 1))
        scheduler.submit(.setEqualizerBand(id: 1, value: 2))
        try await settle()
        #expect(await sink.commands.count == 2)
    }

    @Test func mergesPartialAudioChanges() async throws {
        let sink = Sink()
        let scheduler = scheduler(sink)
        scheduler.submit(.setAudio(noiseLevel: 4, spatial: nil, windBlock: nil))
        scheduler.submit(.setAudio(noiseLevel: nil, spatial: nil, windBlock: true))
        try await settle()
        #expect(await sink.commands == [.setAudio(noiseLevel: 4, spatial: nil, windBlock: true)])
    }

    @Test func aModeReplacesPendingAudio() async throws {
        let sink = Sink()
        let scheduler = scheduler(sink)
        scheduler.submit(.setAudio(noiseLevel: 4, spatial: nil, windBlock: nil))
        scheduler.submit(.setMode("quiet"))
        try await settle()
        #expect(await sink.commands == [.setMode("quiet")])
    }

    @Test func discreteCommandsBeatSliders() async throws {
        let sink = Sink()
        let scheduler = scheduler(sink)
        scheduler.submit(.setEqualizerBand(id: 0, value: 1))
        scheduler.submit(.setMultipoint(true))
        try await settle()
        #expect(await sink.commands.first == .setMultipoint(true))
    }

    @Test func cancelAllSendsNothing() async throws {
        let sink = Sink()
        let scheduler = scheduler(sink)
        scheduler.submit(.setMode("quiet"))
        scheduler.cancelAll()
        try await settle()
        #expect(await sink.commands.isEmpty)
    }
}
