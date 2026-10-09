// swift-tools-version:5.9
import PackageDescription

// Rotato's shared code. RotatoKit is the platform-neutral core (sources, storage, rotation,
// rendering); RotatoUI holds the SwiftUI screens. Both also build for macOS so the core can be
// compiled and checked without Xcode: `swift run RotatoChecks`.
let package = Package(
    name: "RotatoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RotatoKit", targets: ["RotatoKit"]),
        .library(name: "RotatoUI", targets: ["RotatoUI"]),
    ],
    targets: [
        .target(
            name: "RotatoKit",
            resources: [.copy("Resources/plugins")]
        ),
        .target(name: "RotatoUI", dependencies: ["RotatoKit"]),
        // Compiled straight into the app and widget targets by the Xcode project (Shortcuts only
        // finds intents built into the app itself); this target exists so they're type-checked here.
        .target(name: "RotatoIntents", dependencies: ["RotatoKit"]),
        .executableTarget(name: "RotatoChecks", dependencies: ["RotatoKit"]),
    ]
)
