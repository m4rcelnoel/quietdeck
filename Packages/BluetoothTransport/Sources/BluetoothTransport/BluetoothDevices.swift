import Foundation
import RFCOMMBridge

/// A device paired with this Mac.
public struct PairedBluetoothDevice: Sendable, Equatable {
    public var name: String
    public var address: String
    /// Informational only: the system's value can be stale, even while audio plays.
    public var reportedConnected: Bool

    public init(name: String, address: String, reportedConnected: Bool) {
        self.name = name
        self.address = address
        self.reportedConnected = reportedConnected
    }
}

/// First use of IOBluetooth starts a one-time setup that can wait for the main thread, and
/// for the user to answer the permission dialog. If the main thread then touches
/// IOBluetooth as well, the app deadlocks. So everything here runs on a background thread
/// with the main thread free, and nothing limits how long it may take.
public enum BluetoothDevices {
    public static func isPoweredOn() async -> Bool {
        await onBackgroundThread { QDBluetoothIsPoweredOn() }
    }

    /// This Mac's address as `AA:BB:CC:DD:EE:FF`.
    public static func hostAddress() async -> String? {
        await onBackgroundThread {
            QDBluetoothHostAddress()?.uppercased().replacingOccurrences(of: "-", with: ":")
        }
    }

    public static func paired() async -> [PairedBluetoothDevice] {
        await onBackgroundThread {
            QDPairedDevices().map {
                PairedBluetoothDevice(name: $0.name, address: $0.address, reportedConnected: $0.isConnected)
            }
        }
    }

    private static func onBackgroundThread<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value
    ) async -> Value {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}

/// Reports Bluetooth connections until it is stopped.
@MainActor
public final class BluetoothConnectionWatcher {
    private let monitor: QDConnectionMonitor

    /// - Parameter handler: Called on the main actor with the connected device's address.
    public init(handler: @escaping @Sendable (String) -> Void) {
        monitor = QDConnectionMonitor(handler: handler)
    }

    public func stop() {
        monitor.stop()
    }
}
