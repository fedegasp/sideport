import Foundation

struct Device: Identifiable, Hashable {
    enum ConnectionState: Hashable {
        /// Collegato ma non ancora abbinato: serve "Autorizza" sul dispositivo.
        case untrusted
        /// Abbinato ma bloccato con codice: alcune query falliscono.
        case locked
        case ready
        case error(String)
    }

    let udid: String
    var state: ConnectionState = .untrusted
    var name: String = ""
    var productType: String = ""
    var productVersion: String = ""
    var buildVersion: String = ""
    var serialNumber: String = ""
    var deviceClass: String = ""
    var totalDiskCapacity: Int64?
    var availableDiskCapacity: Int64?
    var batteryLevel: Int?
    var isCharging: Bool?

    var id: String { udid }

    var displayName: String {
        name.isEmpty ? marketingName : name
    }

    var marketingName: String {
        if let known = DeviceNames.marketingName(for: productType) { return known }
        if !productType.isEmpty { return productType }
        // lockdownd puo' non aver ancora risposto: ripiega sulla classe.
        return deviceClass.isEmpty ? "Dispositivo iOS" : deviceClass
    }

    var osName: String {
        switch deviceClass {
        case "iPad": return "iPadOS"
        case "iPod": return "iOS"
        case "AppleTV": return "tvOS"
        case "Watch": return "watchOS"
        default: return "iOS"
        }
    }

    var systemVersionLabel: String {
        productVersion.isEmpty ? osName : "\(osName) \(productVersion)"
    }

    var usedDiskCapacity: Int64? {
        guard let total = totalDiskCapacity, let available = availableDiskCapacity else { return nil }
        return max(0, total - available)
    }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var symbolName: String {
        switch deviceClass {
        case "iPad": return "ipad"
        case "iPod": return "ipodtouch"
        case "AppleTV": return "appletv"
        case "Watch": return "applewatch"
        default: return "iphone"
        }
    }
}
