// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IMC",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "IMC",
            path: "Sources/IMC",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
