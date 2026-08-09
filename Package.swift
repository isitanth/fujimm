// swift-tools-version:5.9
import PackageDescription

// Zero external dependencies on purpose: `swift build` works offline and the
// resulting binary links only against system frameworks (Foundation, ImageIO,
// AVFoundation, CryptoKit, DiskArbitration).
let package = Package(
    name: "fujimm",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "fujimm",
            path: "Sources/fujimm",
            linkerSettings: [
                .linkedFramework("ImageIO"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreServices"),
                .linkedFramework("DiskArbitration"),
            ]
        ),
        // The import policy under test lives in main.swift's top-level statements,
        // which are unreachable from a test host, so these tests drive the built
        // binary as a subprocess. The dependency exists to make `swift test` build
        // it. No library split is needed for this.
        .testTarget(
            name: "fujimmTests",
            dependencies: ["fujimm"],
            path: "Tests/fujimmTests"
        ),
    ]
)
