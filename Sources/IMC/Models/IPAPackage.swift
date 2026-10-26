import Foundation

struct IPAPackage: Identifiable, Hashable, Codable {
    enum Signing: String, Codable {
        case appStore
        case provisioned
        case unknown

        var label: LocalizedStringResource {
            switch self {
            case .appStore: .ui("App Store")
            case .provisioned: .ui("Provisioning profile")
            case .unknown: .ui("Unknown")
            }
        }
    }

    let url: URL
    var bundleIdentifier: String
    var name: String
    var shortVersion: String
    var buildVersion: String
    var minimumOSVersion: String
    var supportedPlatforms: [String]
    var supportedDeviceFamilies: [Int]
    var fileSize: Int64
    var modificationDate: Date
    var signing: Signing
    /// Dati di firma completi: il genere grossolano di `signing` non basta a
    /// distinguere due copie della stessa app firmate da team diversi.
    var signature: IPASignature?
    var iconData: Data?

    var id: URL { url }

    var versionLabel: String {
        if shortVersion.isEmpty { return buildVersion }
        if buildVersion.isEmpty || buildVersion == shortVersion { return shortVersion }
        return "\(shortVersion) (\(buildVersion))"
    }

    /// Genere della firma, dal dato piu' preciso disponibile.
    var signatureLabel: LocalizedStringResource {
        signature?.kind.label ?? signing.label
    }

    /// Identificativi presenti in piu' di una .ipa della libreria: le loro
    /// righe hanno bisogno del nome del file per essere distinte.
    static func duplicatedBundleIdentifiers(in packages: [IPAPackage]) -> Set<String> {
        var seen = Set<String>()
        var duplicated = Set<String>()
        for package in packages where !seen.insert(package.bundleIdentifier).inserted {
            duplicated.insert(package.bundleIdentifier)
        }
        return duplicated
    }

    /// "iPhone, iPad" ricavato da UIDeviceFamily.
    var deviceFamilyLabel: String {
        let names = supportedDeviceFamilies.compactMap { family -> String? in
            switch family {
            case 1: return "iPhone"
            case 2: return "iPad"
            case 3: return "Apple TV"
            case 4: return "Apple Watch"
            default: return nil
            }
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    /// Verifica grossolana di compatibilita' prima di tentare l'installazione.
    func compatibility(with device: Device) -> Compatibility {
        if !supportedDeviceFamilies.isEmpty {
            let expected: Int
            switch device.deviceClass {
            case "iPad": expected = 2
            case "AppleTV": expected = 3
            case "Watch": expected = 4
            default: expected = 1
            }
            // Un'app solo-iPhone gira comunque su iPad in modalita' compatibilita'.
            let runsAnyway = expected == 2 && supportedDeviceFamilies.contains(1)
            if !supportedDeviceFamilies.contains(expected) && !runsAnyway {
                return .incompatible(String.ui("This app does not support \(device.marketingName)."))
            }
        }
        if !minimumOSVersion.isEmpty, !device.productVersion.isEmpty,
           VersionCompare.isLower(device.productVersion, than: minimumOSVersion) {
            return .incompatible(String.ui("Requires iOS \(minimumOSVersion), the device has \(device.productVersion)."))
        }
        return .compatible
    }

    enum Compatibility: Equatable {
        case compatible
        case incompatible(String)

        var isCompatible: Bool { self == .compatible }
        var reason: String? {
            if case .incompatible(let message) = self { return message }
            return nil
        }
    }
}
