// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scribe",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Scribe",
            path: "Scribe"
        ),
    ]
)
