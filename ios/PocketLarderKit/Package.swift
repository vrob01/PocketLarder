// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PocketLarderKit",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "PocketLarderKit", targets: ["PocketLarderKit"]),
    ],
    targets: [
        .target(name: "PocketLarderKit"),
        .testTarget(name: "PocketLarderKitTests", dependencies: ["PocketLarderKit"]),
    ]
)
