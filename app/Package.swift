// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scribe",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    targets: [
        .executableTarget(
            name: "Scribe",
            path: "Scribe",
            sources: ["Shared", "macOS", "iOS"],
            resources: [.copy("Info.plist")]
        ),
    ]
)
