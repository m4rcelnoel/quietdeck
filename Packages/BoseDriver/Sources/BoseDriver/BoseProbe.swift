import BMAPCodec
import QuietDeckCore

/// Hardware verification helpers. The sweep only ever reads.
public enum BoseProbe {
    public struct Result: Sendable {
        public var label: String
        public var address: String
        /// Lowercase hex of the response payload, or `nil` on failure.
        public var payloadHex: String?
        public var failure: String?
        /// The raw payload, for follow-up requests.
        public var payload: [UInt8]
    }

    /// Everything the protocol map lists as readable, by name.
    static let readableFunctions: [(label: String, address: BMAPAddress)] = [
        ("firmware", .init(functionBlock: 0, function: 5)),
        ("product name", .init(functionBlock: 1, function: 2)),
        ("noise control info", .init(functionBlock: 1, function: 5)),
        ("equalizer", .init(functionBlock: 1, function: 7)),
        ("multipoint", .init(functionBlock: 1, function: 10)),
        ("sidetone", .init(functionBlock: 1, function: 11)),
        ("auto play pause", .init(functionBlock: 1, function: 24)),
        ("auto answer", .init(functionBlock: 1, function: 27)),
        ("battery", .init(functionBlock: 2, function: 2)),
        ("charging", .init(functionBlock: 2, function: 3)),
        ("paired devices", .init(functionBlock: 4, function: 4)),
        ("routing", .init(functionBlock: 4, function: 12)),
        ("active source", .init(functionBlock: 5, function: 1)),
        ("mode summary", .init(functionBlock: 31, function: 2)),
        ("current mode", .init(functionBlock: 31, function: 3)),
        ("favorites", .init(functionBlock: 31, function: 8)),
        ("audio settings", .init(functionBlock: 31, function: 10)),
        ("preset mask", .init(functionBlock: 31, function: 11)),
    ]

    /// Reads every listed function, then the details of each paired device.
    public static func sweep(_ client: BMAPClient) async -> [Result] {
        var results: [Result] = []
        for function in readableFunctions {
            results.append(await read(client, function.label, function.address))
        }

        let pairedAddress = BMAPAddress(functionBlock: 4, function: 4)
        let list = results.first { $0.address == pairedAddress.description }?.payload ?? []
        let info = BMAPAddress(functionBlock: 4, function: 5)
        for (index, mac) in macAddresses(inDeviceList: list).enumerated() {
            results.append(await read(client, "device \(index) info", info, payload: mac))
        }
        return results
    }

    /// Exercises each MVP write: read, write, read back, then restore the original values.
    ///
    /// - Parameter log: Receives one line per step.
    public static func verifyWrites(_ client: BMAPClient, log: @Sendable (String) -> Void) async {
        let mode = BMAPAddress(functionBlock: 31, function: 3)
        let audio = BMAPAddress(functionBlock: 31, function: 10)
        let equalizer = BMAPAddress(functionBlock: 1, function: 7)

        func read(_ address: BMAPAddress) async -> [UInt8]? {
            let result = await BoseProbe.read(client, "", address)
            return result.failure == nil ? result.payload : nil
        }

        func write(_ label: String, _ address: BMAPAddress, _ op: BMAPOperator, _ payload: [UInt8]) async {
            do {
                let request = try BMAPFrame(address: address, operator: op, payload: payload)
                let response = try await client.transact(request)
                log(
                    "WRITE \(label): sent \(hex(payload)), reply \(response.operator.map { "\($0)" } ?? "?") \(hex(response.payload))"
                )
            } catch {
                log("WRITE \(label): FAILED \(error)")
            }
            try? await Task.sleep(for: .seconds(1))
            log(
                "  mode \(hex(await read(mode) ?? [])) audio \(hex(await read(audio) ?? [])) eq \(hex(await read(equalizer) ?? []))"
            )
        }

        guard let originalMode = await read(mode)?.first,
            let originalAudio = await read(audio), originalAudio.count == 5,
            let originalEqualizer = await read(equalizer), originalEqualizer.count == 12
        else {
            log("WRITE aborted: could not read the original state")
            return
        }
        log("ORIGINAL mode \(hex([originalMode])) audio \(hex(originalAudio)) eq \(hex(originalEqualizer))")

        await write("mode aware", mode, .start, [1, 0])
        await write("mode quiet", mode, .start, [0, 0])
        await write("mode cinema", mode, .start, [3, 0])

        await write("noise cnc 5", audio, .setGet, [5, 0, 0, 0, 1])
        await write("spatial still", audio, .setGet, [5, 0, 1, 0, 1])
        await write("wind on", audio, .setGet, [5, 0, 0, 1, 1])
        await write("anc off", audio, .setGet, [5, 0, 0, 0, 0])

        let bass = originalEqualizer[2]
        let changedBass: UInt8 = bass == 3 ? 4 : 3
        await write("eq bass", equalizer, .setGet, [changedBass, 0])
        await write("eq bass negative", equalizer, .setGet, [0xF6, 0])

        // Restore: the equalizer first, then the mode, then audio only if it still differs.
        await write("restore eq bass", equalizer, .setGet, [bass, 0])
        if originalMode != 0xFF {
            await write("restore mode", mode, .start, [originalMode, 0])
        }
        if await read(audio) != originalAudio {
            await write("restore audio", audio, .setGet, originalAudio)
        }

        let finalMode = await read(mode)?.first
        let finalAudio = await read(audio)
        let finalEqualizer = await read(equalizer)
        let restored = finalMode == originalMode && finalAudio == originalAudio && finalEqualizer == originalEqualizer
        log(
            "\(restored ? "RESTORED" : "NOT RESTORED") mode \(hex(finalMode.map { [$0] } ?? [])) audio \(hex(finalAudio ?? [])) eq \(hex(finalEqualizer ?? []))"
        )
    }

    /// Exercises source switching and the multipoint setting, then restores multipoint.
    /// Both can interrupt audio. Addresses are never logged.
    public static func verifySourcesAndMultipoint(_ client: BMAPClient, log: @Sendable (String) -> Void) async {
        let source = BMAPAddress(functionBlock: 5, function: 1)
        let list = BMAPAddress(functionBlock: 4, function: 4)
        let info = BMAPAddress(functionBlock: 4, function: 5)
        let routing = BMAPAddress(functionBlock: 4, function: 12)
        let multipoint = BMAPAddress(functionBlock: 1, function: 10)

        func activeMac() async -> [UInt8]? {
            let payload = await read(client, "", source).payload
            return payload.count >= 9 ? Array(payload[3..<9]) : nil
        }

        func route(_ label: String, to mac: [UInt8]) async {
            for attempt in 1...5 {
                do {
                    let request = try BMAPFrame(address: routing, operator: .start, payload: [0x82] + mac)
                    let response = try await client.transact(request)
                    log(
                        "ROUTE \(label) try \(attempt): reply \(response.operator.map { "\($0)" } ?? "?") length \(response.payload.count)"
                    )
                    return
                } catch {
                    log("ROUTE \(label) try \(attempt): \(error)")
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        /// Reads multipoint, waiting through a reconnection.
        func readMultipoint() async -> [UInt8]? {
            for _ in 0..<45 {
                let result = await read(client, "", multipoint)
                if result.failure == nil { return result.payload }
                try? await Task.sleep(for: .seconds(1))
            }
            return nil
        }

        func setMultipoint(_ value: UInt8) async {
            do {
                let request = try BMAPFrame(address: multipoint, operator: .setGet, payload: [value])
                let response = try await client.transact(request)
                log(
                    "MULTIPOINT set \(value): reply \(response.operator.map { "\($0)" } ?? "?") \(hex(response.payload))"
                )
            } catch {
                log("MULTIPOINT set \(value): \(error)")
            }
            try? await Task.sleep(for: .seconds(3))
            log("MULTIPOINT read: \(await readMultipoint().map(hex) ?? "unavailable")")
        }

        guard let thisMac = await activeMac() else {
            log("SOURCE aborted: no active Bluetooth source")
            return
        }
        let devices = macAddresses(inDeviceList: await read(client, "", list).payload)
        var other: [UInt8]?
        for (index, mac) in devices.enumerated() {
            let details = await read(client, "", info, payload: mac).payload
            let status = details.count > 8 ? hex(Array(details[6..<9])) : "?"
            let isThisMac = mac == thisMac
            log("DEVICE \(index): header \(status) thisMac \(isThisMac)")
            if !isThisMac, details.count > 6, details[6] & 1 == 1 {
                other = mac
            }
        }

        await route("to this Mac", to: thisMac)
        if let other {
            await route("to other device", to: other)
            try? await Task.sleep(for: .seconds(2))
            let moved = await activeMac() != thisMac
            log("SOURCE moved away: \(moved)")
            if moved {
                await route("back to this Mac", to: thisMac)
                try? await Task.sleep(for: .seconds(2))
                log("SOURCE back on this Mac: \(await activeMac() == thisMac)")
            }
        } else {
            log("SOURCE no other connected device to route to")
        }

        guard let original = await readMultipoint() else {
            log("MULTIPOINT aborted: could not read it")
            return
        }
        log("MULTIPOINT original: \(hex(original))")
        await setMultipoint(0)
        await setMultipoint(1)
        let final = await readMultipoint()
        log("\(final == original ? "RESTORED" : "NOT RESTORED") multipoint \(final.map(hex) ?? "unavailable")")
    }

    /// Watches routing while another device connects and starts playing. Addresses and
    /// names are never logged. Tries to connect the first remembered phone, then tries to
    /// switch to any other connected device whenever the routing function answers.
    public static func watchRouting(
        _ client: BMAPClient,
        duration: Duration,
        log: @Sendable (String) -> Void
    ) async {
        let source = BMAPAddress(functionBlock: 5, function: 1)
        let list = BMAPAddress(functionBlock: 4, function: 4)
        let info = BMAPAddress(functionBlock: 4, function: 5)
        let routing = BMAPAddress(functionBlock: 4, function: 12)
        let connect = BMAPAddress(functionBlock: 4, function: 1)

        func devices() async -> [(mac: [UInt8], header: String, status: UInt8, type: UInt8)] {
            var result: [(mac: [UInt8], header: String, status: UInt8, type: UInt8)] = []
            for mac in macAddresses(inDeviceList: await read(client, "", list).payload) {
                let details = await read(client, "", info, payload: mac).payload
                if details.count > 8 {
                    result.append((mac, hex(Array(details[6..<9])), details[6], details[7]))
                }
            }
            return result
        }

        func describe(_ error: Error) -> String {
            String(describing: error).replacingOccurrences(of: "rejected", with: "error")
        }

        let start = await devices()
        log("ROUTING devices: \(start.map { "\($0.header)" })")
        let activeMac = Array(await read(client, "", source).payload.dropFirst(3).prefix(6))

        if !start.contains(where: { $0.mac != activeMac && $0.status & 1 == 1 }),
            let phone = start.first(where: { $0.type == 2 })
        {
            do {
                let request = try BMAPFrame(address: connect, operator: .start, payload: phone.mac)
                let response = try await client.transact(request)
                log("CONNECT reply \(response.operator.map { "\($0)" } ?? "?") length \(response.payload.count)")
            } catch {
                log("CONNECT \(describe(error))")
            }
            try? await Task.sleep(for: .seconds(8))
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: duration)
        var lastDevices = ""
        var lastActive = ""
        var lastRouting = ""
        var switched = false
        log("WAITING start playing on the other device now")
        while clock.now < deadline {
            let current = await devices()
            let summary = current.map(\.header).joined(separator: " ")
            if summary != lastDevices {
                lastDevices = summary
                log("DEVICES \(summary)")
            }
            let active = Array(await read(client, "", source).payload.dropFirst(3).prefix(6))
            let activeName = active == activeMac ? "this Mac" : "other"
            if activeName != lastActive {
                lastActive = activeName
                log("ACTIVE \(activeName)")
            }
            let probe = await read(client, "", routing)
            let routingState = probe.failure ?? "answers \(probe.payload.count) bytes"
            if routingState != lastRouting {
                lastRouting = routingState
                log("ROUTING GET \(routingState)")
            }
            if !switched, active == activeMac,
                let other = current.first(where: { $0.mac != activeMac && $0.status & 1 == 1 })
            {
                do {
                    let request = try BMAPFrame(address: routing, operator: .start, payload: [0x82] + other.mac)
                    let response = try await client.transact(request)
                    log("SWITCH reply \(response.operator.map { "\($0)" } ?? "?") length \(response.payload.count)")
                    switched = true
                } catch DriverError.rejected(code: 4, _) {
                    // The routing table is empty. Expected until the other stream starts.
                } catch {
                    log("SWITCH \(describe(error))")
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        log("END")
    }

    /// Tests taking audio to this Mac while another device plays: pause that device through
    /// the headset, then start a stream here, silent first and with a faint signal second.
    public static func bringAudioHere(
        _ client: BMAPClient,
        hostAddress: [UInt8],
        startStream: @Sendable (_ faintSignal: Bool) async -> Void,
        stopStream: @Sendable () async -> Void,
        log: @Sendable (String) -> Void
    ) async {
        let source = BMAPAddress(functionBlock: 5, function: 1)
        let routing = BMAPAddress(functionBlock: 4, function: 12)

        func active() async -> String {
            let payload = await read(client, "", source).payload
            guard payload.count >= 9 else { return "none (\(hex(payload)))" }
            return Array(payload[3..<9]) == hostAddress ? "this Mac" : "other"
        }

        func watch(_ label: String, for duration: Duration, route: Bool) async {
            let clock = ContinuousClock()
            let start = clock.now
            var last = ""
            var lastReply = ""
            while clock.now < start.advanced(by: duration) {
                let current = await active()
                if current != last {
                    last = current
                    let elapsed = (clock.now - start).components.seconds
                    log("\(label) +\(elapsed)s: active \(current)")
                    if current == "this Mac", route || label == "SILENT" {
                        return
                    }
                }
                if route {
                    var reply: String
                    do {
                        let request = try BMAPFrame(address: routing, operator: .start, payload: [0x82] + hostAddress)
                        let response = try await client.transact(request)
                        reply = "\(response.operator.map { "\($0)" } ?? "?") length \(response.payload.count)"
                    } catch {
                        reply = String(describing: error)
                    }
                    if reply != lastReply {
                        lastReply = reply
                        log("\(label) route reply: \(reply)")
                    }
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }

        log("BASE active \(await active())")
        if await active() == "this Mac" {
            log("RESULT skipped: this Mac is already active")
            return
        }

        do {
            let control = BMAPAddress(functionBlock: 5, function: 3)
            let request = try BMAPFrame(address: control, operator: .start, payload: [0x02])
            let response = try await client.transact(request)
            log("PAUSE reply \(response.operator.map { "\($0)" } ?? "?") length \(response.payload.count)")
        } catch {
            log("PAUSE \(error)")
        }
        try? await Task.sleep(for: .seconds(1))
        log("AFTER PAUSE active \(await active())")

        await startStream(false)
        log("STREAM silent")
        await watch("SILENT", for: .seconds(10), route: false)
        if await active() == "this Mac" {
            log("RESULT pause plus silence took over")
            await stopStream()
            return
        }
        await stopStream()

        await startStream(true)
        log("STREAM faint signal")
        await watch("SILENT", for: .seconds(10), route: false)
        if await active() == "this Mac" {
            log("RESULT pause plus a faint signal took over")
            await stopStream()
            return
        }

        await watch("SILENT+ROUTE", for: .seconds(8), route: true)
        log("RESULT nothing took over, active \(await active())")
        await stopStream()
    }

    /// Measures a connection attempt to a computer that is off, then to the phone.
    /// Addresses are never logged.
    public static func connectRemembered(_ client: BMAPClient, log: @Sendable (String) -> Void) async {
        let list = BMAPAddress(functionBlock: 4, function: 4)
        let info = BMAPAddress(functionBlock: 4, function: 5)
        let connect = BMAPAddress(functionBlock: 4, function: 1)

        func states() async -> [(mac: [UInt8], header: [UInt8])] {
            var result: [(mac: [UInt8], header: [UInt8])] = []
            for mac in macAddresses(inDeviceList: await read(client, "", list).payload) {
                let details = await read(client, "", info, payload: mac).payload
                if details.count > 8 {
                    result.append((mac, Array(details[6..<9])))
                }
            }
            return result
        }

        func timeline(_ label: String, of mac: [UInt8], seconds: Int) async {
            var last = ""
            for second in 0...seconds {
                let listByte = hex(Array(await read(client, "", list).payload.prefix(1)))
                let header = await states().first { $0.mac == mac }.map { hex($0.header) } ?? "?"
                let line = "list \(listByte) status \(header)"
                if line != last {
                    last = line
                    log("\(label) +\(second)s \(line)")
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }

        func attempt(_ label: String, _ device: (mac: [UInt8], header: [UInt8]), seconds: Int) async {
            do {
                let request = try BMAPFrame(address: connect, operator: .start, payload: [0] + device.mac)
                let response = try await client.transact(request, acceptsProcessing: true)
                log("\(label) reply \(response.operator.map { "\($0)" } ?? "?")")
            } catch {
                log("\(label) \(error)")
            }
            await timeline(label, of: device.mac, seconds: seconds)
        }

        let before = await states()
        log("CONNECT before \(before.map { hex($0.header) })")
        if let computer = before.first(where: { $0.header[0] & 1 == 0 && $0.header[1] == 1 }) {
            await attempt("OFFLINE", computer, seconds: 25)
        }
        if let phone = before.first(where: { $0.header[1] == 2 }) {
            await attempt("PHONE", phone, seconds: 20)
        }
        log("CONNECT after \(await states().map { hex($0.header) })")
    }

    /// Splits a paired device list payload into addresses, skipping empty slots.
    static func macAddresses(inDeviceList payload: [UInt8]) -> [[UInt8]] {
        let entries = payload.dropFirst()
        return stride(from: entries.startIndex, to: entries.endIndex - 5, by: 6).compactMap { start in
            let mac = Array(entries[start..<(start + 6)])
            return mac.allSatisfy { $0 == 0 } ? nil : mac
        }
    }

    private static func read(
        _ client: BMAPClient,
        _ label: String,
        _ address: BMAPAddress,
        payload: [UInt8] = []
    ) async -> Result {
        do {
            let request = try BMAPFrame(address: address, operator: .get, payload: payload)
            guard BoseFramePolicy.evaluate(request) == .allow else {
                return Result(
                    label: label, address: address.description, payloadHex: nil, failure: "denied by policy",
                    payload: []
                )
            }
            let response = try await client.transact(request)
            return Result(
                label: label, address: address.description, payloadHex: hex(response.payload), failure: nil,
                payload: response.payload
            )
        } catch {
            return Result(
                label: label, address: address.description, payloadHex: nil, failure: String(describing: error),
                payload: []
            )
        }
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }
}
