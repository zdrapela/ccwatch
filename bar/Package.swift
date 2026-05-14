// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCWatchBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CCWatchBar",
            path: "Sources/CCWatchBar",
            exclude: ["Info.plist"],
            resources: [.copy("Resources")]
        )
    ]
)
