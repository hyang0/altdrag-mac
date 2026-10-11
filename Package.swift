// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AltDrag",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "AltDrag",
            path: "Sources/AltDrag"
        )
    ]
)
