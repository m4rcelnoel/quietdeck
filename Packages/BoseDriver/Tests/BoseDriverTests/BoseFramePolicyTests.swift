import BMAPCodec
import QuietDeckCore
import Testing

@testable import BoseDriver

private func frame(_ block: UInt8, _ function: UInt8, _ op: BMAPOperator, _ payload: [UInt8] = []) throws -> BMAPFrame {
    try BMAPFrame(address: BMAPAddress(functionBlock: block, function: function), operator: op, payload: payload)
}

private func isDenied(_ verdict: RawFrameVerdict) -> Bool {
    if case .deny = verdict { return true }
    return false
}

private func needsConfirmation(_ verdict: RawFrameVerdict) -> Bool {
    if case .confirm = verdict { return true }
    return false
}

@Suite struct BoseFramePolicyTests {
    @Test(arguments: [BMAPOperator.get, .start, .setGet, .set])
    func authenticationBlockIsAlwaysDenied(op: BMAPOperator) throws {
        for function in UInt8(0)...40 {
            #expect(isDenied(BoseFramePolicy.evaluate(try frame(18, function, op))))
        }
    }

    @Test(arguments: [UInt8(3), 8])
    func firmwareAndDebugBlocksAreDeniedEvenForReading(block: UInt8) throws {
        #expect(isDenied(BoseFramePolicy.evaluate(try frame(block, 1, .get))))
    }

    @Test(arguments: [(UInt8(4), UInt8(3)), (4, 7), (31, 9)])
    func destructiveFunctionsAreDenied(block: UInt8, function: UInt8) throws {
        #expect(isDenied(BoseFramePolicy.evaluate(try frame(block, function, .start))))
        #expect(isDenied(BoseFramePolicy.evaluate(try frame(block, function, .setGet))))
    }

    @Test func pureSetIsDenied() throws {
        #expect(isDenied(BoseFramePolicy.evaluate(try frame(31, 3, .set))))
    }

    @Test(arguments: [BMAPOperator.status, .error, .result, .processing])
    func responseOperatorsCannotBeSent(op: BMAPOperator) throws {
        #expect(isDenied(BoseFramePolicy.evaluate(try frame(2, 2, op))))
    }

    @Test func unknownOperatorIsDenied() throws {
        let unknown = try BMAPFrame(address: BMAPAddress(functionBlock: 2, function: 2), flags: 0x0E)
        #expect(isDenied(BoseFramePolicy.evaluate(unknown)))
    }

    @Test func readingOrdinaryFunctionsIsAllowed() throws {
        #expect(BoseFramePolicy.evaluate(try frame(2, 2, .get)) == .allow)
        #expect(BoseFramePolicy.evaluate(try frame(200, 1, .get)) == .allow)
    }

    @Test func verifiedWritesAreAllowed() throws {
        #expect(BoseFramePolicy.evaluate(try frame(31, 3, .start, [0, 0])) == .allow)
        #expect(BoseFramePolicy.evaluate(try frame(31, 10, .setGet)) == .allow)
        #expect(BoseFramePolicy.evaluate(try frame(1, 7, .setGet)) == .allow)
    }

    @Test(arguments: [(UInt8(7), UInt8(4)), (4, 8), (4, 2), (1, 9), (4, 12), (1, 10)])
    func otherWritesNeedConfirmation(block: UInt8, function: UInt8) throws {
        #expect(needsConfirmation(BoseFramePolicy.evaluate(try frame(block, function, .start))))
    }

    @Test(arguments: [
        [UInt8](), [2, 2, 1], [2, 2, 1, 2, 0], [2, 2, 1, 0, 2, 2, 1, 0], [2, 2, 1, 0, 9],
    ])
    func malformedBytesAreDenied(bytes: [UInt8]) {
        #expect(isDenied(BoseFramePolicy.evaluate(bytes)))
    }

    @Test func wellFormedBytesAreEvaluated() {
        #expect(BoseFramePolicy.evaluate([2, 2, 1, 0]) == .allow)
    }

    @Test func everySweepEntryIsAllowed() throws {
        for function in BoseProbe.readableFunctions {
            let request = try BMAPFrame(address: function.address, operator: .get)
            #expect(BoseFramePolicy.evaluate(request) == .allow, "\(function.label)")
        }
    }
}

@Suite struct DeviceListTests {
    @Test func skipsEmptySlots() {
        let mac: [UInt8] = [1, 2, 3, 4, 5, 6]
        let empty = [UInt8](repeating: 0, count: 6)
        #expect(BoseStateCodec.addresses(inDeviceList: [2] + mac + empty + mac) == [mac, mac])
    }

    @Test func toleratesShortLists() {
        #expect(BoseStateCodec.addresses(inDeviceList: []).isEmpty)
        #expect(BoseStateCodec.addresses(inDeviceList: [1, 2, 3]).isEmpty)
    }
}
