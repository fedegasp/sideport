import Foundation
import Testing
@testable import Sideport

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

    private func package(bundleIdentifier: String, file: String) -> IPAPackage {
        IPAPackage(
            url: URL(fileURLWithPath: "/tmp/\(file)"),
            bundleIdentifier: bundleIdentifier,
            name: "App",
            shortVersion: "1.0",
            buildVersion: "1",
            minimumOSVersion: "",
            supportedPlatforms: ["iPhoneOS"],
            supportedDeviceFamilies: [1],
            fileSize: 0,
            modificationDate: .distantPast,
            signing: .unknown
        )
    }

    /// L'originale e la copia rifirmata differiscono solo nel nome del file.
    @Test func spotsTheBundleIdentifiersThatRepeat() {
        let packages = [
            package(bundleIdentifier: "com.example.app", file: "App.ipa"),
            package(bundleIdentifier: "com.example.app", file: "App (rifirmata).ipa"),
            package(bundleIdentifier: "com.example.other", file: "Other.ipa"),
        ]

        #expect(IPAPackage.duplicatedBundleIdentifiers(in: packages) == ["com.example.app"])
        #expect(IPAPackage.duplicatedBundleIdentifiers(in: [packages[2]]).isEmpty)
    }

    /// Finche' la firma dettagliata non e' stata letta vale quella grossolana.
    @Test func signatureLabelPrefersTheDetailedKind() {
        var package = package(bundleIdentifier: "com.example.app", file: "App.ipa")
        package.signing = .provisioned
        #expect(String(localized: package.signatureLabel) == String(localized: IPAPackage.Signing.provisioned.label))

        var signature = IPASignature()
        signature.kind = .adHoc
        package.signature = signature
        #expect(String(localized: package.signatureLabel) == String(localized: IPASignature.Kind.adHoc.label))
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
        // Il testo dipende dalla lingua: conta che riporti le due versioni.
        #expect(result.reason?.contains("17.0") == true)
        #expect(result.reason?.contains("16.4") == true)
    }

    @Test func acceptsUnknownDeviceVersion() {
        let iPhone = Device(udid: "1", deviceClass: "iPhone")
        #expect(package(families: [1], minimumOS: "17.0").compatibility(with: iPhone).isCompatible)
    }
}
