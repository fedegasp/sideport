// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IMC",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "IMC",
            path: "Sources/IMC",
            // Il catalogo lo compila Xcode; a `swift build` servono i .strings
            // generati da Scripts/compile-strings.sh, nelle cartelle .lproj.
            exclude: ["Resources/Localizable.xcstrings"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "IMCTests",
            dependencies: ["IMC"],
            path: "Tests/IMCTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
