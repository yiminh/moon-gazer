// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MoonGazer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MoonGazer",
            path: "Sources/MoonGazer"
        )
    ]
)
