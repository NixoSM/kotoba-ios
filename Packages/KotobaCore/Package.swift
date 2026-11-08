// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KotobaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KotobaCore", targets: ["KotobaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(name: "KotobaCore", dependencies: ["ZIPFoundation"]),
        .testTarget(name: "KotobaCoreTests", dependencies: ["KotobaCore", "ZIPFoundation"]),
    ]
)
