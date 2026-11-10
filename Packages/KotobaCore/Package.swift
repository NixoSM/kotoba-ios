// swift-tools-version:5.9
import PackageDescription

// The engine also builds on Linux, so its tests run on GitHub's cheap Linux
// machines instead of a Mac. Linux has no built-in SQLite3 module (CSQLite3
// stands in for it) and no Vision framework (the OCR target stays Apple-only).
#if os(Linux)
let sqlite: [Target.Dependency] = ["CSQLite3"]
let platformTargets: [Target] = [
    .systemLibrary(name: "CSQLite3", providers: [.apt(["libsqlite3-dev"])]),
]
let platformProducts: [Product] = []
#else
let sqlite: [Target.Dependency] = []
let platformTargets: [Target] = [
    .target(name: "KotobaOCR"),
    // Runs Apple's recognizer on rendered and photographed 縦書き pages and prints how well it reads.
    .testTarget(name: "KotobaOCRTests", dependencies: ["KotobaOCR", "KotobaCore"], resources: [.copy("Fixtures")]),
]
let platformProducts: [Product] = [
    // Reading text from camera frames and photos (vertical included).
    .library(name: "KotobaOCR", targets: ["KotobaOCR"]),
]
#endif

let package = Package(
    name: "KotobaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KotobaCore", targets: ["KotobaCore"]),
    ] + platformProducts,
    dependencies: [
        // Pinned: an update on the library's side must not change a build we cannot reproduce on a Mac.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(name: "KotobaCore", dependencies: ["ZIPFoundation"] + sqlite),
        .testTarget(name: "KotobaCoreTests", dependencies: ["KotobaCore", "ZIPFoundation"]),
    ] + platformTargets
)
