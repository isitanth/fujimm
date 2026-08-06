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
        )
    ]
)
