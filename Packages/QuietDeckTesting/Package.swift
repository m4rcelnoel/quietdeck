// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuietDeckTesting",
    platforms: [.macOS(.v14)],
    products: [.library(name: "QuietDeckTesting", targets: ["QuietDeckTesting"])],
    dependencies: [
        .package(path: "../QuietDeckCore"),
        .package(path: "../BluetoothTransport"),
    ],
    targets: [
        .target(
            name: "QuietDeckTesting",
            dependencies: [
                "QuietDeckCore",
                .product(name: "TransportInterface", package: "BluetoothTransport"),
            ]
        ),
        .testTarget(name: "QuietDeckTestingTests", dependencies: ["QuietDeckTesting"]),
    ]
)
