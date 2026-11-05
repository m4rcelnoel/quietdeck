import Testing

@testable import BMAPCodec

private let battery = [UInt8]([0x02, 0x02, 0x03, 0x04, 0x50, 0xFF, 0xFF, 0x00])
private let empty = [UInt8]([0x1F, 0x03, 0x06, 0x00])

/// Small deterministic generator, so failures reproduce.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite struct BMAPFrameDecoderTests {
    @Test func decodesWholeFrame() {
        var decoder = BMAPFrameDecoder()
        let frames = decoder.append(battery)
        #expect(frames.count == 1)
        #expect(frames[0].address == BMAPAddress(functionBlock: 2, function: 2))
        #expect(frames[0].operator == .status)
        #expect(frames[0].payload == [0x50, 0xFF, 0xFF, 0x00])
        #expect(decoder.pendingByteCount == 0)
    }

    @Test func decodesFrameWithoutPayload() {
        var decoder = BMAPFrameDecoder()
        #expect(decoder.append(empty).first?.payload == [])
    }

    @Test func decodesByteByByte() {
        var decoder = BMAPFrameDecoder()
        var frames: [BMAPFrame] = []
        for (index, byte) in battery.enumerated() {
            let result = decoder.append([byte])
            if index < battery.count - 1 {
                #expect(result.isEmpty)
            }
            frames += result
        }
        #expect(frames.count == 1)
        #expect(frames.first?.encoded() == battery)
    }

    @Test func holdsHeaderOnlyFragment() {
        var decoder = BMAPFrameDecoder()
        #expect(decoder.append(battery.prefix(3)).isEmpty)
        #expect(decoder.pendingByteCount == 3)
        #expect(decoder.append(battery.dropFirst(3)).count == 1)
    }

    @Test func holdsPartialPayload() {
        var decoder = BMAPFrameDecoder()
        #expect(decoder.append(battery.prefix(6)).isEmpty)
        #expect(decoder.pendingByteCount == 6)
    }

    @Test func decodesSeveralFramesFromOneRead() {
        var decoder = BMAPFrameDecoder()
        let frames = decoder.append(battery + empty + battery)
        #expect(frames.map { $0.encoded() } == [battery, empty, battery])
        #expect(decoder.pendingByteCount == 0)
    }

    @Test func keepsTrailingFragmentAfterWholeFrame() {
        var decoder = BMAPFrameDecoder()
        #expect(decoder.append(battery + empty.prefix(2)).count == 1)
        #expect(decoder.pendingByteCount == 2)
        #expect(decoder.append(empty.suffix(2)).first?.encoded() == empty)
    }

    @Test func decodesMaximumLengthPayload() throws {
        let frame = try BMAPFrame(
            address: BMAPAddress(functionBlock: 4, function: 4),
            operator: .status,
            payload: (0..<255).map { UInt8($0) }
        )
        var decoder = BMAPFrameDecoder()
        #expect(decoder.append(frame.encoded()) == [frame])
    }

    @Test func resetDropsPartialFrame() {
        var decoder = BMAPFrameDecoder()
        _ = decoder.append(battery.prefix(5))
        decoder.reset()
        #expect(decoder.pendingByteCount == 0)
        #expect(decoder.append(empty).first?.encoded() == empty)
    }

    @Test func emptyInputDoesNothing() {
        var decoder = BMAPFrameDecoder()
        #expect(decoder.append([]).isEmpty)
    }

    @Test(arguments: [UInt64(1), 2, 3, 42, 2026])
    func roundTripsRandomFramesInRandomChunks(seed: UInt64) throws {
        var random = SeededGenerator(state: seed)
        var frames: [BMAPFrame] = []
        for _ in 0..<200 {
            let length = Int.random(in: 0...255, using: &random)
            frames.append(
                try BMAPFrame(
                    address: BMAPAddress(
                        functionBlock: .random(in: 0...255, using: &random),
                        function: .random(in: 0...255, using: &random)
                    ),
                    flags: .random(in: 0...255, using: &random),
                    payload: (0..<length).map { _ in .random(in: 0...255, using: &random) }
                )
            )
        }

        var stream = frames.flatMap { $0.encoded() }[...]
        var decoder = BMAPFrameDecoder()
        var decoded: [BMAPFrame] = []
        while !stream.isEmpty {
            let size = min(Int.random(in: 1...300, using: &random), stream.count)
            decoded += decoder.append(stream.prefix(size))
            stream = stream.dropFirst(size)
        }

        #expect(decoded == frames)
        #expect(decoder.pendingByteCount == 0)
    }
}
