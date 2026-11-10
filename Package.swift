// swift-tools-version:5.9
import PackageDescription

// For development only: the app itself is built from project.yml (XcodeGen).
//
// This package compiles the parts of the app that need no screen (search, the
// results page, settings, translations) straight from App/Sources, so they are
// tested on Linux for free instead of only being built on a Mac. The two
// pieces that need an iPhone are replaced by App/LogicSupport/LinuxStandIns.swift.
//
//   swift test            (from the repository root)
let package = Package(
    name: "KotobaAppLogic",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [.package(path: "Packages/KotobaCore")],
    targets: [
        .target(
            name: "KotobaAppLogic",
            dependencies: [.product(name: "KotobaCore", package: "KotobaCore")],
            path: "App",
            exclude: ["Resources", "Shared"],
            sources: [
                "LogicSupport/LinuxStandIns.swift",
                "Sources/AppSettings.swift",
                "Sources/Appearance.swift",
                "Sources/HeadwordGroup.swift",
                "Sources/L10n.swift",
                "Sources/MediaLink.swift",
                "Sources/Reason+Italian.swift",
                "Sources/ResultsPage.swift",
                "Sources/SearchResults.swift",
            ]
        ),
        .testTarget(
            name: "KotobaAppLogicTests",
            dependencies: ["KotobaAppLogic", .product(name: "KotobaCore", package: "KotobaCore")],
            path: "Tests/KotobaAppLogicTests"
        ),
    ]
)
