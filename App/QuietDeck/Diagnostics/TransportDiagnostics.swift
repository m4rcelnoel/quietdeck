#if DEBUG
    import AppKit
    import BluetoothTransport
    import BoseDriver
    import Foundation
    import QuietDeckCore
    import UserNotifications

    /// Hardware checks for the transport, started with a launch argument.
    ///
    /// `--transport-test` opens the channel and runs 100 battery reads.
    /// `--reconnect-test` additionally waits for a power cycle and a reconnection.
    /// `--protocol-sweep` reads every function in the protocol map.
    /// `--write-verify` changes each MVP setting and restores it. This one does write.
    /// `--driver-verify` runs the full driver: read, change the mode, restore.
    /// `--watch-events` logs what the device reports by itself for 40 seconds.
    /// `--app-check` runs the app's own path: model, controller, scheduler and driver.
    @MainActor
    enum TransportDiagnostics {
        private static let transactionCount = 100
        private static let reconnectWindow = Duration.seconds(180)

        /// Returns whether a check started, in which case the app must not connect itself.
        static func startIfRequested() -> Bool {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--notify-test") {
                Task {
                    let notifier = Notifier(settings: AppSettings())
                    do {
                        let granted = try await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound])
                        log("granted: \(granted)")
                    } catch {
                        log("request failed: \(error)")
                    }
                    notifier.batteryChanged(percent: 19)
                    try? await Task.sleep(for: .seconds(6))
                    log("delivered \(await UNUserNotificationCenter.current().deliveredNotifications().count)")
                    log("DONE")
                    exit(0)
                }
                return true
            }
            if let values = arguments.first(where: { $0.hasPrefix("--set-eq=") }) {
                Task {
                    await setEqualizer(values.dropFirst("--set-eq=".count).split(separator: ",").compactMap { Int($0) })
                    log("DONE")
                    exit(0)
                }
                return true
            }
            if arguments.contains("--app-check") {
                Task {
                    await runAppCheck()
                    log("DONE")
                    exit(0)
                }
                return true
            }
            if arguments.contains("--driver-verify") || arguments.contains("--watch-events") {
                let watch = arguments.contains("--watch-events")
                Task {
                    await runDriverCheck(watchEvents: watch)
                    log("DONE")
                    exit(0)
                }
                return true
            }
            let waitForReconnect = arguments.contains("--reconnect-test")
            let sweep = arguments.contains("--protocol-sweep")
            let verifyWrites = arguments.contains("--write-verify")
            guard waitForReconnect || sweep || verifyWrites || arguments.contains("--transport-test") else {
                return false
            }
            Task {
                await run(waitForReconnect: waitForReconnect, sweep: sweep, verifyWrites: verifyWrites)
                log("DONE")
                exit(0)
            }
            return true
        }

        private static func run(waitForReconnect: Bool, sweep: Bool, verifyWrites: Bool) async {
            let paired = await BluetoothDevices.paired()
            log("paired devices: \(paired.count)")
            guard let device = paired.first(where: { $0.name.hasPrefix("Bose QC Ultra") }) else {
                log("FAIL no matching headset is paired")
                return
            }
            log("device: \(device.name), reported connected: \(device.reportedConnected)")

            let address = device.address
            let session = RFCOMMSession {
                IOBluetoothRFCOMMLink(address: address, channelID: BoseDevices.qcUltra2Channel)
            }
            let client = BMAPClient(transport: session)
            await client.start()

            let lost = LostFlag()
            let reconnected = LostFlag()
            let watcher = BluetoothConnectionWatcher { connected in
                guard connected == address else { return }
                log("system reports the device connected")
                Task { await session.deviceAppeared() }
            }
            defer { watcher.stop() }

            let events = Task {
                for await event in client.connectionEvents {
                    log("session event: \(event)")
                    if event == .lost {
                        await lost.set()
                    } else if event == .opened, await lost.value {
                        await reconnected.set()
                    }
                }
            }
            defer { events.cancel() }

            let clock = ContinuousClock()
            do {
                let elapsed = try await clock.measure { try await session.open() }
                log("channel open after \(milliseconds(elapsed)) ms")
                log("battery: \(try await client.readBatteryPercent())%")

                var latencies: [Duration] = []
                for _ in 0..<transactionCount {
                    latencies.append(try await clock.measure { _ = try await client.readBatteryPercent() })
                }
                latencies.sort()
                log(
                    "PASS \(latencies.count) reads: min \(milliseconds(latencies[0])) ms, "
                        + "median \(milliseconds(latencies[latencies.count / 2])) ms, "
                        + "max \(milliseconds(latencies[latencies.count - 1])) ms"
                )
            } catch {
                log("FAIL \(error)")
            }

            if sweep {
                for result in await BoseProbe.sweep(client) {
                    log(
                        "SWEEP \(result.address) \(result.label): \(result.payloadHex ?? "FAILED \(result.failure ?? "")")"
                    )
                }
            }

            if verifyWrites {
                await BoseProbe.verifyWrites(client) { log($0) }
            }

            if waitForReconnect {
                log("WAITING turn the headset off, wait 10 seconds, and turn it on again")
                let deadline = clock.now.advanced(by: reconnectWindow)
                while clock.now < deadline {
                    try? await Task.sleep(for: .seconds(1))
                    guard await reconnected.value else { continue }
                    do {
                        log("PASS reconnected, battery: \(try await client.readBatteryPercent())%")
                    } catch {
                        log("FAIL read after reconnecting: \(error)")
                    }
                    break
                }
                if await !reconnected.value {
                    log("FAIL no reconnection within the time limit")
                }
            }

            await session.close()
            try? await Task.sleep(for: .milliseconds(100))
        }

        private static func setEqualizer(_ values: [Int]) async {
            let app = AppModel()
            await app.start()
            guard let controller = app.controller else {
                log("FAIL no controller")
                return
            }
            log("EQ before \(controller.state.equalizer?.map(\.value) ?? [])")
            for (band, value) in values.enumerated() {
                controller.setEqualizerBand(band, value: value)
            }
            try? await Task.sleep(for: .seconds(2))
            await controller.refresh()
            log(
                "EQ after \(controller.state.equalizer?.map(\.value) ?? []) problem \(String(describing: controller.problem))"
            )
            await controller.disconnect()
            try? await Task.sleep(for: .milliseconds(100))
        }

        private static func runAppCheck() async {
            let app = AppModel()
            await app.start()
            guard let controller = app.controller else {
                log("FAIL availability \(app.availability)")
                return
            }
            log("phase \(controller.phase), sections \(controller.capabilities.sections)")
            log("mode \(controller.state.mode.map { "\($0)" } ?? "?") noise \(controller.state.noiseLevel ?? -1)")

            guard case .preset(let original) = controller.state.mode else {
                log("SKIP the device is in a custom state")
                await controller.disconnect()
                return
            }
            let other = original == "quiet" ? "aware" : "quiet"
            controller.selectMode(other)
            log("shown at once: \(controller.state.mode.map { "\($0)" } ?? "?")")
            try? await Task.sleep(for: .seconds(2))
            log(
                "after 2 s: mode \(controller.state.mode.map { "\($0)" } ?? "?") noise \(controller.state.noiseLevel ?? -1)"
            )

            controller.setNoiseLevel(5)
            log("custom shown at once: \(controller.state.mode.map { "\($0)" } ?? "?")")
            try? await Task.sleep(for: .seconds(2))
            log(
                "after 2 s: mode \(controller.state.mode.map { "\($0)" } ?? "?") noise \(controller.state.noiseLevel ?? -1)"
            )

            controller.selectMode(original)
            try? await Task.sleep(for: .seconds(2))
            await controller.refresh()
            let restored = controller.state.mode == .preset(original)
            log("\(restored ? "PASS restored" : "FAIL not restored") problem \(String(describing: controller.problem))")
            await controller.disconnect()
            try? await Task.sleep(for: .milliseconds(100))
        }

        private static func runDriverCheck(watchEvents: Bool) async {
            guard let paired = await BluetoothDevices.paired().first(where: { $0.name.hasPrefix("Bose QC Ultra") })
            else {
                log("FAIL no matching headset is paired")
                return
            }
            let device = DiscoveredDevice(name: paired.name, address: paired.address)
            let session = DriverCatalog.session(for: device)
            guard let driver = DriverCatalog.registry.makeDriver(for: device, transport: session) else {
                log("FAIL no driver")
                return
            }

            func describe(_ state: DeviceState) -> String {
                let bands = state.equalizer?.map { String($0.value) }.joined(separator: "/") ?? "?"
                let sources = state.sources?.sources.map { "\($0.kind)-\($0.status)" }.joined(separator: ",") ?? "?"
                return "mode \(state.mode.map { "\($0)" } ?? "?") noise \(state.noiseLevel ?? -1) "
                    + "spatial \(state.spatialAudio.map { "\($0)" } ?? "?") wind \(state.windBlock ?? false) "
                    + "eq \(bands) battery \(state.battery?.percent ?? -1) multipoint \(state.multipoint ?? false) "
                    + "firmware \(state.firmwareVersion ?? "?") sources \(sources)"
            }

            let events = Task {
                for await event in driver.events {
                    switch event {
                    case .stateChanged(let state): log("EVENT state: \(describe(state))")
                    case .connectionChanged(let state): log("EVENT connection: \(state)")
                    case .capabilitiesChanged: log("EVENT capabilities changed")
                    }
                }
            }
            defer { events.cancel() }

            let traffic = Task {
                guard let stream = driver.rawConsole?.traffic else { return }
                for await entry in stream where watchEvents && entry.direction == .received {
                    log("FRAME \(entry.summary) \(FrameLogExport.hex(entry.bytes))")
                }
            }
            defer { traffic.cancel() }

            let clock = ContinuousClock()
            do {
                try await driver.connect()
                var state = DeviceState()
                let elapsed = try await clock.measure { state = try await driver.refreshState() }
                log("STATE after \(milliseconds(elapsed)) ms: \(describe(state))")

                if watchEvents {
                    log("WAITING press the headset's buttons now")
                    try await Task.sleep(for: .seconds(40))
                } else if case .preset(let original) = state.mode {
                    let other = original == "aware" ? "quiet" : "aware"
                    try await driver.perform(.setMode(other))
                    log("CHANGED: \(describe(try await driver.refreshState()))")
                    try await driver.perform(.setMode(original))
                    let restored = try await driver.refreshState()
                    log("\(restored == state ? "PASS restored" : "FAIL differs"): \(describe(restored))")
                } else {
                    log("SKIP mode change: the device is in a custom state")
                }
            } catch {
                log("FAIL \(error)")
            }
            await driver.disconnect()
            try? await Task.sleep(for: .milliseconds(100))
        }

        private static func milliseconds(_ duration: Duration) -> Int {
            let parts = duration.components
            return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
        }

        private nonisolated static func log(_ message: String) {
            let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message)\n"
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Logs/QuietDeck")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "transport-test.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    private actor LostFlag {
        private(set) var value = false

        func set() {
            value = true
        }
    }
#endif
