import BMAPCodec
import os

/// A small simulation of the headset, built from behavior verified on real hardware.
final class SimulatedHeadset: Sendable {
    struct State {
        var mode: UInt8 = 0
        var audio: [UInt8] = [0, 0, 0, 0, 1]
        var equalizer: [Int8] = [1, -1, 1]
        var multipoint: UInt8 = 0x07
        var routingErrorsLeft = 0
        var active: [UInt8] = [1, 1, 1, 1, 1, 1]
        var refused: Set<BMAPAddress> = []
        var paused = false
        var connectRequest: [UInt8]?
    }

    static let thisMac: [UInt8] = [1, 1, 1, 1, 1, 1]
    static let otherMac: [UInt8] = [2, 2, 2, 2, 2, 2]

    private static let presets: [[UInt8]] = [
        [0, 0, 0, 0, 1], [10, 0, 0, 0, 1], [0, 0, 2, 0, 1], [0, 0, 1, 0, 1],
    ]

    let state = OSAllocatedUnfairLock(initialState: State())

    func respond(to bytes: [UInt8]) -> [[UInt8]] {
        var decoder = BMAPFrameDecoder()
        return decoder.append(bytes).compactMap { frame in
            state.withLock { reply(to: frame, state: &$0) }?.encoded()
        }
    }

    private func reply(to request: BMAPFrame, state: inout State) -> BMAPFrame? {
        func answer(_ op: BMAPOperator, _ payload: [UInt8]) -> BMAPFrame? {
            try? BMAPFrame(address: request.address, operator: op, payload: payload)
        }
        if state.refused.contains(request.address) {
            return answer(.error, [5])
        }
        let isGet = request.operator == .get
        switch (request.address.functionBlock, request.address.function) {
        case (0, 5):
            return answer(.status, Array("10.12.14+gde0210e".utf8))
        case (1, 2):
            return answer(.status, [0] + Array("Bose QC Ultra 2 HP".utf8))
        case (2, 2):
            return answer(.status, [0x5A, 0xFF, 0xFF, 0])
        case (31, 3):
            if isGet { return answer(.status, [state.mode]) }
            state.mode = request.payload[0]
            state.audio = Self.presets[Int(state.mode)]
            return answer(.result, [state.mode])
        case (31, 10):
            if !isGet {
                state.audio = request.payload
                state.mode = 0xFF
            }
            return answer(.status, state.audio)
        case (1, 7):
            if !isGet {
                state.equalizer[Int(request.payload[1])] = Int8(bitPattern: request.payload[0])
            }
            var records: [UInt8] = []
            for (band, value) in state.equalizer.enumerated() {
                records += [0xF6, 0x0A, UInt8(bitPattern: value), UInt8(band)]
            }
            return answer(.status, records)
        case (1, 10):
            if !isGet {
                state.multipoint = (state.multipoint & 0xFE) | request.payload[0]
            }
            return answer(.status, [state.multipoint])
        case (4, 4):
            return answer(.status, [3] + Self.thisMac + Self.otherMac)
        case (4, 5):
            let isThisMac = request.payload == Self.thisMac
            return answer(
                .status,
                request.payload + (isThisMac ? [3, 1, 1] : [1, 1, 3]) + Array((isThisMac ? "This Mac" : "Other").utf8)
            )
        case (5, 1):
            return answer(.status, [0, 0x0F, 1] + state.active)
        case (4, 1):
            state.connectRequest = request.payload
            return answer(.processing, Array(request.payload.dropFirst()))
        case (5, 3):
            state.paused = request.payload == [2]
            return answer(.result, [0])
        case (4, 12):
            if state.routingErrorsLeft > 0 {
                state.routingErrorsLeft -= 1
                return answer(.error, [4])
            }
            state.active = Array(request.payload[1...])
            return answer(.result, [0x82] + state.active)
        default:
            return answer(.error, [4])
        }
    }
}
