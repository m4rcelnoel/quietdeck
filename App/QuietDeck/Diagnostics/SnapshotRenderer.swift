#if DEBUG
    import AppKit
    import QuietDeckCore
    import QuietDeckTesting
    import SwiftUI

    /// Renders every screen with sample data to PNG files, so layouts can be reviewed.
    @MainActor
    enum SnapshotRenderer {
        static func startIfRequested() -> Bool {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--scene-click-test") || arguments.contains("--demo") {
                return true
            }
            if ProcessInfo.processInfo.arguments.contains("--slider-test") {
                Task {
                    await runSliderTest()
                    exit(0)
                }
                return true
            }
            if ProcessInfo.processInfo.arguments.contains("--click-test") {
                Task {
                    await runClickTest()
                    exit(0)
                }
                return true
            }
            guard ProcessInfo.processInfo.arguments.contains("--render-snapshots") else { return false }
            Task {
                await renderAll()
                exit(0)
            }
            return true
        }

        /// Runs the real interface with sample data, for documentation screenshots. No real
        /// device names appear, and the headset isn't touched.
        static func runDemoIfRequested(_ app: AppModel, openMainWindow: () -> Void) async -> Bool {
            guard ProcessInfo.processInfo.arguments.contains("--demo") else { return false }
            var state = Fixtures.fullState
            state.name = "Headphones"
            state.battery = BatteryStatus(percent: 82)
            state.sources = AudioSourceList(sources: [
                AudioSource(id: "AA:AA:AA:AA:AA:01", name: "This Mac", kind: .computer, status: .active),
                AudioSource(id: "AA:AA:AA:AA:AA:02", name: "Work PC", kind: .computer, status: .connected),
                AudioSource(id: "AA:AA:AA:AA:AA:03", name: "iPhone", kind: .phone, status: .remembered),
            ])
            let controller = DeviceController(
                driver: MockDriver(capabilities: Fixtures.fullCapabilities, state: state)
            )
            controller.localSourceID = "AA:AA:AA:AA:AA:01"
            await controller.connect()
            app.useForTesting(controller)
            if ProcessInfo.processInfo.arguments.contains("--tour") {
                await runTour(app, openMainWindow: openMainWindow)
                exit(0)
            }
            return true
        }

        /// Shows each page in real windows, one at a time, and publishes the window number so
        /// an external tool can capture it with its real materials.
        private static func runTour(_ app: AppModel, openMainWindow: () -> Void) async {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Logs/QuietDeck/tour")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let current = directory.appending(path: "current.txt")
            try? "".write(to: current, atomically: true, encoding: .utf8)

            func publish(_ name: String, _ window: NSWindow) async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .seconds(1.2))
                try? "\(name) \(window.windowNumber)\n".write(to: current, atomically: true, encoding: .utf8)
                try? await Task.sleep(for: .seconds(1.2))
            }

            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openMainWindow()
            var found: NSWindow?
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(300))
                found = NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0.frame.width > 300 }
                if found != nil { break }
            }
            guard let main = found else {
                let seen = NSApp.windows.map { "\(type(of: $0)) \($0.identifier?.rawValue ?? "-") v\($0.isVisible)" }
                try? "missing \(seen)\n".write(
                    to: directory.appending(path: "error.txt"), atomically: true, encoding: .utf8)
                try? "done\n".write(to: current, atomically: true, encoding: .utf8)
                return
            }
            main.setContentSize(NSSize(width: 820, height: 620))
            main.center()

            let pages: [(String, WindowSection, NSAppearance.Name)] = [
                ("main-listening", .device(.listening), .darkAqua),
                ("main-listening-light", .device(.listening), .aqua),
                ("main-sound", .device(.sound), .darkAqua),
                ("main-sources", .device(.sources), .darkAqua),
                ("settings", .settings, .darkAqua),
                ("about", .about, .darkAqua),
            ]
            for (name, section, appearance) in pages {
                NSApp.appearance = NSAppearance(named: appearance)
                app.selectedSection = section
                await publish(name, main)
            }
            main.orderOut(nil)

            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 378),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isReleasedWhenClosed = false
            let material = NSVisualEffectView()
            material.material = .popover
            material.state = .active
            let host = NSHostingView(rootView: MenuBarPanel(app: app))
            host.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                host.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
            panel.contentView = material
            panel.center()
            for (name, appearance) in [("panel", NSAppearance.Name.darkAqua), ("panel-light", .aqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                await publish(name, panel)
            }
            try? "done\n".write(to: current, atomically: true, encoding: .utf8)
        }

        /// Opens the real menu bar panel and clicks its tiles. Uses the real headset with
        /// `--real-device`, which also restores the mode afterwards.
        static func runSceneClickTestIfRequested(_ app: AppModel) async -> Bool {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--scene-click-test") else { return false }
            if arguments.contains("--real-device") {
                await app.start()
            } else {
                let controller = DeviceController(
                    driver: MockDriver(capabilities: Fixtures.fullCapabilities, state: Fixtures.fullState)
                )
                await controller.connect()
                app.useForTesting(controller)
            }
            try? await Task.sleep(for: .seconds(1))

            var lines: [String] = []
            guard let controller = app.controller else {
                write(["no controller"])
                exit(0)
            }
            lines.append("phase \(controller.phase) mode \(String(describing: controller.state.mode))")

            let statusWindows = NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
            var panel: NSWindow?
            for window in statusWindows where panel == nil {
                guard let button = window.contentView.flatMap(statusButton) else { continue }
                button.performClick(nil)
                try? await Task.sleep(for: .seconds(1.5))
                panel = NSApp.windows.first { !statusWindows.contains($0) && $0.isVisible }
            }
            lines.append(
                "windows \(NSApp.windows.map { "\(type(of: $0)) \(Int($0.frame.width))x\(Int($0.frame.height)) v\($0.isVisible) k\($0.isKeyWindow)" })"
            )
            guard let panel else {
                write(lines + ["no panel"])
                exit(0)
            }

            let original = controller.state.mode
            let height = panel.frame.height
            func click(_ x: Double, _ fromTop: Double) async {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(
                        with: type, location: NSPoint(x: x, y: height - fromTop), modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
                    )
                    if let event {
                        panel.sendEvent(event)
                    }
                    try? await Task.sleep(for: .milliseconds(120))
                }
                try? await Task.sleep(for: .seconds(1.2))
            }

            for row in stride(from: 60.0, through: 200.0, by: 20.0) {
                for x in [80.0, 240.0] {
                    let before = controller.state.mode
                    await click(x, row)
                    if controller.state.mode != before {
                        lines.append("hit x \(Int(x)) top \(Int(row)): \(String(describing: controller.state.mode))")
                    }
                }
            }
            lines.append(
                "problem \(String(describing: controller.problem)) final \(String(describing: controller.state.mode))")
            if case .preset(let id) = original {
                controller.selectMode(id)
                try? await Task.sleep(for: .seconds(2))
                lines.append("restored \(String(describing: controller.state.mode))")
            }
            write(lines)
            exit(0)
        }

        private static func statusButton(in view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton { return button }
            for child in view.subviews {
                if let found = statusButton(in: child) { return found }
            }
            return nil
        }

        private static func write(_ lines: [String]) {
            let text = lines.map { "CLICK \($0)" }.joined(separator: "\n") + "\nDONE\n"
            let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/QuietDeck")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? text.write(to: directory.appending(path: "click-test.log"), atomically: true, encoding: .utf8)
        }

        /// Clicks and drags the vertical slider with real mouse events, in both directions.
        private static func runSliderTest() async {
            let box = SliderBox()
            let height = 220.0
            let window = NSWindow(
                contentRect: NSRect(x: 200, y: 300, width: 60, height: height),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SliderHarness(box: box))
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(1))

            func event(_ type: NSEvent.EventType, _ y: Double) -> NSEvent? {
                NSEvent.mouseEvent(
                    with: type, location: NSPoint(x: 30, y: y), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
                )
            }

            /// NSSlider tracks in its own loop inside mouse down, so the rest must be queued first.
            func drag(from start: Double, to end: Double) async {
                for step in 1...8 {
                    let y = start + (end - start) * Double(step) / 8
                    if let moved = event(.leftMouseDragged, y) {
                        NSApp.postEvent(moved, atStart: false)
                    }
                }
                if let up = event(.leftMouseUp, end) {
                    NSApp.postEvent(up, atStart: false)
                }
                if let down = event(.leftMouseDown, start) {
                    window.sendEvent(down)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }

            var results = ["start \(box.value)"]
            let middle = height / 2
            await drag(from: middle, to: middle + 40)
            results.append("drag up \(box.value)")
            await drag(from: middle + 40, to: middle - 60)
            results.append("drag down \(box.value)")
            await drag(from: middle - 60, to: middle)
            results.append("drag to middle \(box.value)")
            await drag(from: height - 12, to: height - 12)
            results.append("click top \(box.value)")
            await drag(from: 12, to: 12)
            results.append("click bottom \(box.value)")
            write(results)
        }

        @MainActor
        @Observable
        final class SliderBox {
            var value = 0
        }

        struct SliderHarness: View {
            let box: SliderBox

            var body: some View {
                VerticalSlider(value: box.value, range: -10...10, label: "Test") { box.value = $0 }
                    .frame(width: 60, height: 220)
            }
        }

        /// Sends real mouse events to the mode tiles, in a real window with real materials.
        /// A plain button in the same window shows whether the events themselves work.
        private static func runClickTest() async {
            let app = AppModel()
            let useRealDevice = ProcessInfo.processInfo.arguments.contains("--real-device")
            if useRealDevice {
                await app.start()
            }
            let controller =
                app.controller
                ?? DeviceController(
                    driver: MockDriver(capabilities: Fixtures.fullCapabilities, state: Fixtures.fullState)
                )
            if !useRealDevice {
                await controller.connect()
            }
            let original = controller.state.mode

            let counter = ClickCounter()
            let window = NSWindow(
                contentRect: NSRect(x: 200, y: 300, width: 400, height: 140),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            let content = VStack(spacing: 0) {
                ModeTiles(controller: controller)
                    .padding(8)
                    .frame(height: 100)
                Button("Control") { counter.count += 1 }
                    .frame(height: 40)
            }
            .frame(width: 400, height: 140)
            window.contentView = NSHostingView(rootView: content)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(1.5))

            func click(_ point: NSPoint) async {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                        pressure: type == .leftMouseDown ? 1 : 0
                    )
                    if let event {
                        window.sendEvent(event)
                    }
                    try? await Task.sleep(for: .milliseconds(120))
                }
                try? await Task.sleep(for: .seconds(1))
            }

            var results: [String] = []
            for round in 1...2 {
                await click(NSPoint(x: 200, y: 20))
                results.append("control round \(round): count \(counter.count)")
            }
            for (name, x) in [("aware", 145.0), ("immersion", 245.0), ("cinema", 345.0), ("quiet", 55.0)] {
                await click(NSPoint(x: x, y: 90))
                let mode = controller.state.mode.map { "\($0)" } ?? "nil"
                results.append("\(name) \(controller.state.mode == .preset(name) ? "ok" : "MISSED") [\(mode)]")
            }
            if case .preset(let id) = original {
                controller.selectMode(id)
                try? await Task.sleep(for: .seconds(2))
                results.append("restored \(String(describing: controller.state.mode))")
            }
            results.append("problem \(String(describing: controller.problem))")
            write(results)
        }

        @MainActor
        private final class ClickCounter {
            var count = 0
        }

        private static func model(
            _ capabilities: DeviceCapabilities = Fixtures.fullCapabilities,
            _ state: DeviceState = Fixtures.fullState,
            connect: Bool = true
        ) async -> AppModel {
            let controller = DeviceController(driver: MockDriver(capabilities: capabilities, state: state))
            if connect {
                await controller.connect()
            }
            return AppModel(availability: .ready, controller: controller)
        }

        private static func renderAll() async {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Logs/QuietDeck/snapshots")
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let full = await model()
            let limited = await model(Fixtures.limitedCapabilities, Fixtures.limitedState)
            var custom = Fixtures.fullState
            custom.mode = .custom
            custom.windBlock = true
            let customized = await model(Fixtures.fullCapabilities, custom)
            let disconnected = await model(connect: false)
            let noDevice = AppModel(availability: .noDevice, controller: nil)

            for appearance in [NSAppearance.Name.darkAqua, .aqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                write(MenuBarPanel(app: full), "panel-\(suffix)", 320, 420, appearance, directory)
                write(MainWindow(app: full), "main-\(suffix)", 760, 560, appearance, directory)
            }
            write(MenuBarPanel(app: limited), "panel-limited", 320, 300, .darkAqua, directory)
            write(MainWindow(app: limited), "main-limited", 760, 560, .darkAqua, directory)
            write(MainWindow(app: customized), "main-custom", 760, 600, .aqua, directory)
            write(MainWindow(app: full), "main-narrow", 460, 620, .darkAqua, directory)
            write(MenuBarPanel(app: disconnected), "panel-disconnected", 320, 420, .darkAqua, directory)
            write(MainWindow(app: noDevice), "main-no-device", 760, 560, .aqua, directory)
            let sections: [(String, WindowSection)] = [
                ("sound", .device(.sound)), ("sources", .device(.sources)), ("device", .device(.device)),
            ]
            let onboarding = AppModel(availability: .checking, controller: nil)
            write(OnboardingView(app: onboarding), "onboarding", 520, 440, .darkAqua, directory)
            write(MainWindow(app: full, initialSection: .settings), "settings", 760, 640, .darkAqua, directory)
            write(MainWindow(app: full, initialSection: .about), "about", 760, 640, .darkAqua, directory)
            for (name, section) in sections {
                write(MainWindow(app: full, initialSection: section), "main-\(name)", 760, 560, .darkAqua, directory)
            }
        }

        /// Offscreen rendering can't draw system materials, so plain surfaces stand in for
        /// them. This checks layout and text, not the final look.
        private static func write(
            _ view: some View,
            _ name: String,
            _ width: CGFloat,
            _ height: CGFloat,
            _ appearance: NSAppearance.Name,
            _ directory: URL
        ) {
            let backdrop = appearance == .aqua ? Color(white: 0.95) : Color(white: 0.14)
            let host = NSHostingView(
                rootView: view.environment(\.usesPlainSurfaces, true)
                    .frame(width: width, height: height)
                    .background(backdrop)
            )
            host.appearance = NSAppearance(named: appearance)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))

            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])
            try? data?.write(to: directory.appending(path: "\(name).png"))
            window.orderOut(nil)
        }
    }
#endif
