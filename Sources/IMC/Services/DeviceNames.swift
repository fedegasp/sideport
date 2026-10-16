import Foundation

/// Mappa `ProductType` (es. iPhone15,3) al nome commerciale.
/// Non esaustiva: per i modelli non elencati si usa l'identificativo grezzo.
enum DeviceNames {
    static func marketingName(for productType: String) -> String? {
        if let exact = table[productType] { return exact }
        // Fallback per modelli piu' recenti di questa tabella.
        if productType.hasPrefix("iPhone") { return "iPhone" }
        if productType.hasPrefix("iPad") { return "iPad" }
        if productType.hasPrefix("iPod") { return "iPod touch" }
        if productType.hasPrefix("Watch") { return "Apple Watch" }
        if productType.hasPrefix("AppleTV") { return "Apple TV" }
        return nil
    }

    private static let table: [String: String] = [
        "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE",
        "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7", "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
        "iPhone11,8": "iPhone XR", "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2a gen)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3a gen)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "iPad7,11": "iPad (7a gen)", "iPad7,12": "iPad (7a gen)",
        "iPad11,6": "iPad (8a gen)", "iPad11,7": "iPad (8a gen)",
        "iPad12,1": "iPad (9a gen)", "iPad12,2": "iPad (9a gen)",
        "iPad13,18": "iPad (10a gen)", "iPad13,19": "iPad (10a gen)",
        "iPad11,1": "iPad mini (5a gen)", "iPad11,2": "iPad mini (5a gen)",
        "iPad14,1": "iPad mini (6a gen)", "iPad14,2": "iPad mini (6a gen)",
        "iPad11,3": "iPad Air (3a gen)", "iPad11,4": "iPad Air (3a gen)",
        "iPad13,1": "iPad Air (4a gen)", "iPad13,2": "iPad Air (4a gen)",
        "iPad13,16": "iPad Air (5a gen)", "iPad13,17": "iPad Air (5a gen)",
        "iPad8,9": "iPad Pro 11\" (2a gen)", "iPad8,10": "iPad Pro 11\" (2a gen)",
        "iPad13,4": "iPad Pro 11\" (3a gen)", "iPad13,5": "iPad Pro 11\" (3a gen)",
        "iPad13,6": "iPad Pro 11\" (3a gen)", "iPad13,7": "iPad Pro 11\" (3a gen)",
        "iPad14,3": "iPad Pro 11\" (4a gen)", "iPad14,4": "iPad Pro 11\" (4a gen)",
        "iPad13,8": "iPad Pro 12.9\" (5a gen)", "iPad13,9": "iPad Pro 12.9\" (5a gen)",
        "iPad13,10": "iPad Pro 12.9\" (5a gen)", "iPad13,11": "iPad Pro 12.9\" (5a gen)",
        "iPad14,5": "iPad Pro 12.9\" (6a gen)", "iPad14,6": "iPad Pro 12.9\" (6a gen)",
        "iPod9,1": "iPod touch (7a gen)"
    ]
}
