import TransportInterface

/// Matches discovered devices to the driver that recognizes them most specifically.
public struct DriverRegistry: Sendable {
    private let drivers: [any HeadphoneDriver.Type]

    public init(drivers: [any HeadphoneDriver.Type]) {
        self.drivers = drivers
    }

    /// The best driver for a device. On a tie, the driver registered first wins.
    public func driverType(for device: DiscoveredDevice) -> (any HeadphoneDriver.Type)? {
        var best: (type: any HeadphoneDriver.Type, match: DriverMatch)?
        for driver in drivers {
            guard let match = driver.match(device) else { continue }
            if best == nil || match > best!.match {
                best = (driver, match)
            }
        }
        return best?.type
    }

    public func makeDriver(
        for device: DiscoveredDevice,
        transport: any ByteTransport
    ) -> (any HeadphoneDriver)? {
        driverType(for: device)?.init(device: device, transport: transport)
    }
}
