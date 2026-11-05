import BMAPCodec
import QuietDeckCore

/// Function addresses, named after the protocol map in the docs.
enum BoseAddress {
    static let firmware = BMAPAddress(functionBlock: 0, function: 5)
    static let productName = BMAPAddress(functionBlock: 1, function: 2)
    static let equalizer = BMAPAddress(functionBlock: 1, function: 7)
    static let multipoint = BMAPAddress(functionBlock: 1, function: 10)
    static let batteryLevel = BMAPAddress(functionBlock: 2, function: 2)
    static let connectDevice = BMAPAddress(functionBlock: 4, function: 1)
    static let pairedDevices = BMAPAddress(functionBlock: 4, function: 4)
    static let deviceInfo = BMAPAddress(functionBlock: 4, function: 5)
    static let activeSource = BMAPAddress(functionBlock: 5, function: 1)
    static let audioControl = BMAPAddress(functionBlock: 5, function: 3)
    static let currentMode = BMAPAddress(functionBlock: 31, function: 3)
    static let audioSettings = BMAPAddress(functionBlock: 31, function: 10)
}

/// Device facts that aren't discovered at runtime.
public enum BoseDevices {
    /// Channel 2 carries BMAP. Other channels can advertise the same UUID but refuse it.
    public static let qcUltra2Channel: UInt8 = 2
    public static let qcUltra2ProductID: UInt16 = 0x4082
}

extension BMAPClient {
    /// Reads the battery level in percent.
    public func readBatteryPercent() async throws -> Int {
        let request = try BMAPFrame(address: BoseAddress.batteryLevel, operator: .get)
        let response = try await transact(request)
        guard let percent = BoseStateCodec.batteryPercent(response.payload) else {
            throw DriverError.malformedResponse
        }
        return percent
    }
}
