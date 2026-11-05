#if DEBUG
    import BMAPCodec
    import QuietDeckCore

    /// Hardware verification helpers, left out of release builds. The sweep only ever reads.
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
            for (index, mac) in BoseStateCodec.addresses(inDeviceList: list).enumerated() {
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
            let restored =
                finalMode == originalMode && finalAudio == originalAudio && finalEqualizer == originalEqualizer
            log(
                "\(restored ? "RESTORED" : "NOT RESTORED") mode \(hex(finalMode.map { [$0] } ?? [])) audio \(hex(finalAudio ?? [])) eq \(hex(finalEqualizer ?? []))"
            )
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
                    label: label, address: address.description,
                    payloadHex: hex(response.payload), failure: nil,
                    payload: response.payload
                )
            } catch {
                return Result(
                    label: label, address: address.description, payloadHex: nil, failure: String(describing: error),
                    payload: []
                )
            }
        }

        private static func hex(_ bytes: [UInt8]) -> String {
            FrameLogExport.hex(bytes, separator: "")
        }
    }
#endif
