import BluetoothTransport
import Foundation
import HandoffKit
import Observation
import QuietDeckCore

/// What the app shows and owns. Panel, window and console share this one instance, and
/// therefore one Bluetooth session.
@MainActor
@Observable
final class AppModel {
    enum Availability: Equatable {
        case checking, bluetoothOff, noDevice, ready
    }

    private(set) var availability: Availability = .checking
    private(set) var controller: DeviceController?
    let presets = EqualizerPresetStore()
    let settings: AppSettings
    let notifier: Notifier
    let console = ProtocolConsoleModel()

    /// What the main window shows. Kept here so the panel and menus can open a page.
    var selectedSection: WindowSection = .device(.listening)

    private var watcher: BluetoothConnectionWatcher?

    init() {
        settings = AppSettings()
        notifier = Notifier(settings: settings)
    }

    /// For previews and snapshots.
    init(availability: Availability, controller: DeviceController?) {
        self.availability = availability
        self.controller = controller
        settings = AppSettings()
        notifier = Notifier(settings: settings)
    }

    var phase: DeviceController.Phase {
        controller?.phase ?? .disconnected
    }

    func start() async {
        guard controller == nil else { return }
        guard await BluetoothDevices.isPoweredOn() else {
            availability = .bluetoothOff
            return
        }
        guard let device = await DriverCatalog.firstSupportedDevice() else {
            availability = .noDevice
            return
        }

        let session = DriverCatalog.session(for: device)
        guard let driver = DriverCatalog.registry.makeDriver(for: device, transport: session) else {
            availability = .noDevice
            return
        }
        let controller = DeviceController(driver: driver)
        #if DEBUG
            controller.trace = { Self.appendTrace($0) }
            Self.appendTrace("start, device found")
        #endif
        self.controller = controller
        availability = .ready
        console.attach(driver.rawConsole)

        let address = device.address
        watcher = BluetoothConnectionWatcher { connected in
            guard connected == address else { return }
            Task { await session.deviceAppeared() }
        }
        controller.localStream = SilentOutputStream()
        let notifier = notifier
        controller.onBatteryReading = { notifier.batteryChanged(percent: $0) }
        controller.onPhaseChange = { notifier.phaseChanged($0) }
        await controller.connect()

        controller.localSourceID = await BluetoothDevices.hostAddress()
        await notifier.requestPermissionIfNeeded()
        #if DEBUG
            Self.appendTrace("local address known: \(controller.localSourceID != nil)")
        #endif
    }

    #if DEBUG
        private static func appendTrace(_ message: String) {
            let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/QuietDeck")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "ui-trace.log")
            let line = Data("\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message)\n".utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
                try? handle.close()
            } else {
                try? line.write(to: url)
            }
        }

        /// Installs a controller for the scene click test.
        func useForTesting(_ controller: DeviceController) {
            self.controller = controller
            availability = .ready
        }
    #endif

    /// Removes all stored data and quits, because the running app would write it back.
    func deleteAllData() {
        settings.deleteEverything()
        exit(0)
    }

    /// Connects shortcuts to their actions.
    func activateShortcuts() {
        GlobalShortcuts.shared.handler = { [weak self] action in
            self?.perform(action)
        }
        GlobalShortcuts.shared.register(settings.shortcuts)
    }

    private func perform(_ action: ShortcutAction) {
        guard let controller, controller.phase == .connected else { return }
        let modes = controller.capabilities.listeningModes?.modes ?? []
        switch action {
        case .firstMode, .secondMode, .thirdMode, .fourthMode:
            guard let index = action.modeIndex, index < modes.count else { return }
            select(modes[index], on: controller)
        case .cycleMode:
            guard !modes.isEmpty else { return }
            var next = 0
            if case .preset(let id) = controller.state.mode, let current = modes.firstIndex(where: { $0.id == id }) {
                next = (current + 1) % modes.count
            }
            select(modes[next], on: controller)
        case .bringAudioHere:
            Task { await controller.bringAudioHere() }
        }
    }

    private func select(_ mode: ListeningMode, on controller: DeviceController) {
        controller.selectMode(mode.id)
        if settings.showHUD {
            ModeHUD.shared.show(title: mode.name, symbol: mode.kind.symbol)
        }
    }

    /// Checks again after the user fixed what was wrong.
    func retry() async {
        if let controller {
            await controller.connect()
        } else {
            await start()
        }
    }

    /// Bits of state can be stale, because the device doesn't report button presses.
    func panelOpened() async {
        await controller?.refresh()
    }
}
