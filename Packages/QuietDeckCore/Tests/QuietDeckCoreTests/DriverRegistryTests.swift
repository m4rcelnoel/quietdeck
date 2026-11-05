import Testing
import TransportInterface

@testable import QuietDeckCore

private struct NullTransport: ByteTransport {
    let incoming = AsyncStream<[UInt8]> { $0.finish() }
    let lifecycle = AsyncStream<TransportEvent> { $0.finish() }
    func open() async throws {}
    func close() async {}
    func send(_ bytes: [UInt8]) async throws {}
}

private protocol StubDriver: HeadphoneDriver {}

extension StubDriver {
    var capabilities: DeviceCapabilities { get async { DeviceCapabilities() } }
    var events: AsyncStream<DeviceEvent> { AsyncStream { $0.finish() } }
    var rawConsole: (any RawFrameConsole)? { nil }
    func connect() async throws {}
    func disconnect() async {}
    func refreshState() async throws -> DeviceState { DeviceState() }
    func perform(_ command: DeviceCommand) async throws {}
}

private struct NameDriver: StubDriver {
    static let descriptor = DriverDescriptor(id: "name", displayName: "Name")
    static func match(_ device: DiscoveredDevice) -> DriverMatch? {
        device.name.hasPrefix("Acme") ? .name : nil
    }
    init(device: DiscoveredDevice, transport: any ByteTransport) {}
}

private struct SecondNameDriver: StubDriver {
    static let descriptor = DriverDescriptor(id: "name2", displayName: "Name 2")
    static func match(_ device: DiscoveredDevice) -> DriverMatch? {
        device.name.hasPrefix("Acme") ? .name : nil
    }
    init(device: DiscoveredDevice, transport: any ByteTransport) {}
}

private struct ProductDriver: StubDriver {
    static let descriptor = DriverDescriptor(id: "product", displayName: "Product")
    static func match(_ device: DiscoveredDevice) -> DriverMatch? {
        device.vendorID == 1 && device.productID == 2 ? .vendorAndProduct : nil
    }
    init(device: DiscoveredDevice, transport: any ByteTransport) {}
}

private struct UUIDDriver: StubDriver {
    static let descriptor = DriverDescriptor(id: "uuid", displayName: "UUID")
    static func match(_ device: DiscoveredDevice) -> DriverMatch? {
        device.serviceUUIDs.contains("cafe") ? .serviceUUID : nil
    }
    init(device: DiscoveredDevice, transport: any ByteTransport) {}
}

@Suite struct DriverRegistryTests {
    private let registry = DriverRegistry(drivers: [
        NameDriver.self, SecondNameDriver.self, UUIDDriver.self, ProductDriver.self,
    ])

    private func id(_ device: DiscoveredDevice) -> String? {
        registry.driverType(for: device)?.descriptor.id
    }

    @Test func unknownDeviceHasNoDriver() {
        #expect(id(DiscoveredDevice(name: "Other", address: "00")) == nil)
    }

    @Test func emptyRegistryHasNoDriver() {
        let device = DiscoveredDevice(name: "Acme One", address: "00")
        #expect(DriverRegistry(drivers: []).driverType(for: device) == nil)
    }

    @Test func matchesByName() {
        #expect(id(DiscoveredDevice(name: "Acme One", address: "00")) == "name")
    }

    @Test func firstRegisteredDriverWinsTies() {
        let reversed = DriverRegistry(drivers: [SecondNameDriver.self, NameDriver.self])
        let device = DiscoveredDevice(name: "Acme One", address: "00")
        #expect(reversed.driverType(for: device)?.descriptor.id == "name2")
    }

    @Test func serviceUUIDBeatsName() {
        let device = DiscoveredDevice(name: "Acme One", address: "00", serviceUUIDs: ["cafe"])
        #expect(id(device) == "uuid")
    }

    @Test func vendorAndProductBeatEverything() {
        let device = DiscoveredDevice(
            name: "Acme One", address: "00", vendorID: 1, productID: 2, serviceUUIDs: ["cafe"]
        )
        #expect(id(device) == "product")
    }

    @Test func createsDriverForMatch() {
        let device = DiscoveredDevice(name: "Acme One", address: "00")
        #expect(registry.makeDriver(for: device, transport: NullTransport()) is NameDriver)
    }

    @Test func createsNothingWithoutMatch() {
        let device = DiscoveredDevice(name: "Other", address: "00")
        #expect(registry.makeDriver(for: device, transport: NullTransport()) == nil)
    }
}
