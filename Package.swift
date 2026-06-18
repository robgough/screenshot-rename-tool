// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screenshot-renamer",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "screenshot-renamer",
            path: "Sources/screenshot-renamer"
        )
    ]
)
