// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Swab",
            path: "Sources/Swab"
        ),
    ]
)
