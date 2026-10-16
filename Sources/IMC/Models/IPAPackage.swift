import Foundation

struct IPAPackage: Identifiable, Hashable, Codable {
    enum Signing: String, Codable {
        case appStore = "App Store"
        case provisioned = "Profilo di provisioning"
        case unknown = "Sconosciuta"
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
    var iconData: Data?

    var id: URL { url }

    var versionLabel: String {
        if shortVersion.isEmpty { return buildVersion }
        if buildVersion.isEmpty || buildVersion == shortVersion { return shortVersion }
        return "\(shortVersion) (\(buildVersion))"
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
                return .incompatible("Questa app non supporta \(device.marketingName).")
            }
        }
        if !minimumOSVersion.isEmpty, !device.productVersion.isEmpty,
           VersionCompare.isLower(device.productVersion, than: minimumOSVersion) {
            return .incompatible("Richiede iOS \(minimumOSVersion), il dispositivo ha \(device.productVersion).")
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
