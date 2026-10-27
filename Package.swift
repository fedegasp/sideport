// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sideport",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sideport",
            path: "Sources/Sideport",
            // Il catalogo lo compila Xcode; a `swift build` servono i .strings
            // generati da Scripts/compile-strings.sh, nelle cartelle .lproj.
            exclude: ["Resources/Localizable.xcstrings"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SideportTests",
            dependencies: ["Sideport"],
            path: "Tests/SideportTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
