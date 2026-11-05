// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BluetoothTransport",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TransportInterface", targets: ["TransportInterface"]),
        .library(name: "BluetoothTransport", targets: ["BluetoothTransport"]),
    ],
    targets: [
        // Protocol only. Must stay free of any Bluetooth import.
        .target(name: "TransportInterface"),
        // Objective-C wrapper around IOBluetooth.
        .target(name: "RFCOMMBridge", linkerSettings: [.linkedFramework("IOBluetooth")]),
        .target(name: "BluetoothTransport", dependencies: ["TransportInterface", "RFCOMMBridge"]),
        .testTarget(name: "BluetoothTransportTests", dependencies: ["BluetoothTransport", "TransportInterface"]),
    ]
)
