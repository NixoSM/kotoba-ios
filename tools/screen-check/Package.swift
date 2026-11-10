// swift-tools-version:5.9
import PackageDescription

// A compiler's look at the app's screens, on Linux, before a Mac is paid to
// build them. See README.md here. Run it with ./run.sh, never on a Mac: there
// the real SwiftUI exists and these stand-ins would only get in its way.
let package = Package(
    name: "ScreenCheck",
    dependencies: [.package(path: "../../Packages/KotobaCore")],
    targets: [
        .target(name: "UniformTypeIdentifiers"),
        .target(name: "Photos"),
        .target(name: "SwiftUI", dependencies: ["UniformTypeIdentifiers"]),
        .target(name: "UIKit", dependencies: ["SwiftUI"]),
        .target(name: "Screens", dependencies: ["SwiftUI", "UIKit", "UniformTypeIdentifiers", "Photos",
                                                .product(name: "KotobaCore", package: "KotobaCore")]),
    ]
)
