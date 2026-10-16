import Foundation
import Testing
@testable import IMC

struct IPAPackageCompatibilityTests {
    private func package(families: [Int], minimumOS: String = "") -> IPAPackage {
        IPAPackage(
            url: URL(fileURLWithPath: "/tmp/App.ipa"),
            bundleIdentifier: "com.example.app",
            name: "App",
            shortVersion: "1.0",
            buildVersion: "1",
            minimumOSVersion: minimumOS,
            supportedPlatforms: ["iPhoneOS"],
            supportedDeviceFamilies: families,
            fileSize: 0,
            modificationDate: .distantPast,
            signing: .unknown
        )
    }

    @Test func iPhoneOnlyAppRunsOnIPad() {
        let iPad = Device(udid: "1", productVersion: "17.0", deviceClass: "iPad")
        #expect(package(families: [1]).compatibility(with: iPad).isCompatible)
    }

    @Test func iPadOnlyAppDoesNotRunOnIPhone() {
        let iPhone = Device(udid: "1", productVersion: "17.0", deviceClass: "iPhone")
        #expect(!package(families: [2]).compatibility(with: iPhone).isCompatible)
    }

    @Test func rejectsOlderSystemVersion() {
        let iPhone = Device(udid: "1", productVersion: "16.4", deviceClass: "iPhone")
        let result = package(families: [1], minimumOS: "17.0").compatibility(with: iPhone)
        #expect(result.reason == "Richiede iOS 17.0, il dispositivo ha 16.4.")
    }

    @Test func acceptsUnknownDeviceVersion() {
        let iPhone = Device(udid: "1", deviceClass: "iPhone")
        #expect(package(families: [1], minimumOS: "17.0").compatibility(with: iPhone).isCompatible)
    }
}
