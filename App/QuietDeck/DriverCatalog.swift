import BluetoothTransport
import BoseDriver
import QuietDeckCore

/// The one place that knows vendor modules. Everything else uses `HeadphoneDriver`.
enum DriverCatalog {
    static let registry = DriverRegistry(drivers: [BoseHeadphoneDriver.self])

    /// The first paired device a driver recognizes.
    static func firstSupportedDevice() async -> DiscoveredDevice? {
        await BluetoothDevices.paired()
            .map { DiscoveredDevice(name: $0.name, address: $0.address) }
            .first { registry.driverType(for: $0) != nil }
    }

    static func session(for device: DiscoveredDevice) -> RFCOMMSession {
        let address = device.address
        return RFCOMMSession {
            IOBluetoothRFCOMMLink(address: address, channelID: BoseDevices.qcUltra2Channel)
        }
    }
}
