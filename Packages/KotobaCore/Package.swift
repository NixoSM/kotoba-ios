// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KotobaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KotobaCore", targets: ["KotobaCore"]),
    ],
    targets: [
        .target(name: "KotobaCore"),
        .testTarget(name: "KotobaCoreTests", dependencies: ["KotobaCore"]),
    ]
)
