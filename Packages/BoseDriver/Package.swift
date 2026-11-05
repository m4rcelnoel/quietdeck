// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoseDriver",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BMAPCodec", targets: ["BMAPCodec"]),
        .library(name: "BoseDriver", targets: ["BoseDriver"]),
    ],
    dependencies: [
        .package(path: "../QuietDeckCore"),
        .package(path: "../BluetoothTransport"),
        .package(path: "../QuietDeckTesting"),
    ],
    targets: [
        // Pure frame codec. Must stay free of all dependencies.
        .target(name: "BMAPCodec"),
        .target(
            name: "BoseDriver",
            dependencies: [
                "BMAPCodec",
                "QuietDeckCore",
                .product(name: "TransportInterface", package: "BluetoothTransport"),
            ]
        ),
        .testTarget(name: "BMAPCodecTests", dependencies: ["BMAPCodec"]),
        .testTarget(
            name: "BoseDriverTests",
            dependencies: [
                "BoseDriver",
                .product(name: "QuietDeckTesting", package: "QuietDeckTesting"),
                .product(name: "TransportInterface", package: "BluetoothTransport"),
            ]
        ),
    ]
)
