// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HandoffKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "HandoffKit", targets: ["HandoffKit"])],
    dependencies: [.package(path: "../QuietDeckCore")],
    targets: [
        .target(name: "HandoffKit", dependencies: ["QuietDeckCore"]),
        .testTarget(name: "HandoffKitTests", dependencies: ["HandoffKit"]),
    ]
)
