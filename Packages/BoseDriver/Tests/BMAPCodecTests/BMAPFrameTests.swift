import Testing

@testable import BMAPCodec

private let mode = BMAPAddress(functionBlock: 31, function: 3)

@Suite struct BMAPFrameEncodingTests {
    @Test func encodesKnownModeCommand() throws {
        let frame = try BMAPFrame(address: mode, operator: .start, payload: [0, 0])
        #expect(frame.encoded() == [0x1F, 0x03, 0x05, 0x02, 0x00, 0x00])
    }

    @Test func encodesEmptyPayload() throws {
        let frame = try BMAPFrame(address: BMAPAddress(functionBlock: 2, function: 2), operator: .get)
        #expect(frame.encoded() == [0x02, 0x02, 0x01, 0x00])
    }

    @Test func acceptsMaximumPayload() throws {
        let frame = try BMAPFrame(address: mode, operator: .status, payload: Array(repeating: 7, count: 255))
        #expect(frame.encoded().count == 259)
        #expect(frame.encoded()[3] == 255)
    }

    @Test func rejectsOversizedPayload() {
        #expect(throws: BMAPCodecError.payloadTooLong(256)) {
            try BMAPFrame(address: mode, operator: .status, payload: Array(repeating: 0, count: 256))
        }
    }

    @Test func operatorUsesOnlyLowNibble() throws {
        let frame = try BMAPFrame(address: mode, flags: 0xD3)
        #expect(frame.operator == .status)
        #expect(frame.operatorCode == 3)
        #expect(frame.flags == 0xD3)
    }

    @Test func unknownOperatorIsReportedAsNil() throws {
        let frame = try BMAPFrame(address: mode, flags: 0x0E)
        #expect(frame.operator == nil)
        #expect(frame.operatorCode == 0x0E)
    }

    @Test(arguments: BMAPOperator.allCases)
    func operatorsMatchTheProtocol(op: BMAPOperator) throws {
        let frame = try BMAPFrame(address: mode, operator: op)
        #expect(frame.operator == op)
    }

    @Test func operatorValues() {
        let values = BMAPOperator.allCases.map(\.rawValue)
        #expect(values == [0, 1, 2, 3, 4, 5, 6, 7])
    }

    @Test func addressPrintsLikeTheNotes() {
        #expect(mode.description == "[31.3]")
    }
}

@Suite struct BMAPErrorFrameTests {
    @Test func readsErrorCode() throws {
        let frame = try BMAPFrame(address: mode, operator: .error, payload: [5])
        #expect(frame.errorCode == .operatorNotSupported)
    }

    @Test func unlistedCodeIsUnrecognized() throws {
        let frame = try BMAPFrame(address: mode, operator: .error, payload: [99])
        #expect(frame.errorCode == .unrecognized)
    }

    @Test func emptyErrorPayloadHasNoCode() throws {
        let frame = try BMAPFrame(address: mode, operator: .error)
        #expect(frame.errorCode == nil)
    }

    @Test func nonErrorFrameHasNoCode() throws {
        let frame = try BMAPFrame(address: mode, operator: .status, payload: [5])
        #expect(frame.errorCode == nil)
    }

    @Test func errorFrameSurvivesDecoding() throws {
        var decoder = BMAPFrameDecoder()
        let frames = decoder.append([0x04, 0x0C, 0x04, 0x01, 0x04])
        #expect(frames.count == 1)
        #expect(frames.first?.errorCode == .functionNotSupported)
    }
}
