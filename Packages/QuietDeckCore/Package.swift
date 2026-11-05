// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuietDeckCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "QuietDeckCore", targets: ["QuietDeckCore"])],
    dependencies: [.package(path: "../BluetoothTransport")],
    targets: [
        .target(
            name: "QuietDeckCore",
            dependencies: [.product(name: "TransportInterface", package: "BluetoothTransport")]
        ),
        .testTarget(name: "QuietDeckCoreTests", dependencies: ["QuietDeckCore"]),
    ]
)
