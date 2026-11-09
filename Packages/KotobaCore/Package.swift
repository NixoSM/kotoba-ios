// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KotobaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KotobaCore", targets: ["KotobaCore"]),
        // Reading text from camera frames and photos (vertical included).
        .library(name: "KotobaOCR", targets: ["KotobaOCR"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(name: "KotobaCore", dependencies: ["ZIPFoundation"]),
        .target(name: "KotobaOCR"),
        .testTarget(name: "KotobaCoreTests", dependencies: ["KotobaCore", "ZIPFoundation"]),
        // Runs Apple's recognizer on rendered and photographed 縦書き pages and prints how well it reads.
        .testTarget(name: "KotobaOCRTests", dependencies: ["KotobaOCR", "KotobaCore"], resources: [.copy("Fixtures")]),
    ]
)
