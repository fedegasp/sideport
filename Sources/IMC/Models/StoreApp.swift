import Foundation

/// App restituita da `ipatool search` o `ipatool list-purchases`.
///
/// ipatool usa due convenzioni diverse per gli stessi dati: la CLI emette
/// `id` / `bundleID` / `name`, mentre il server MCP dichiara
/// `trackId` / `bundleId` / `trackName`. Si accettano entrambe, cosi' il
/// parsing non si rompe se una delle due cambia.
struct StoreApp: Identifiable, Hashable, Decodable {
    let trackId: Int
    let bundleId: String
    let trackName: String
    let version: String
    let price: Double
    let purchaseDate: String?
    let platforms: [String]?

    var id: Int { trackId }

    private enum CodingKeys: String, CodingKey {
        case id, trackId
        case bundleID, bundleId
        case name, trackName
        case version, price, purchaseDate, platforms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(Int.self, forKey: .id) {
            trackId = value
        } else {
            trackId = try container.decode(Int.self, forKey: .trackId)
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .bundleID) {
            bundleId = value
        } else {
            bundleId = try container.decode(String.self, forKey: .bundleId)
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .name) {
            trackName = value
        } else {
            trackName = try container.decode(String.self, forKey: .trackName)
        }
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        price = try container.decodeIfPresent(Double.self, forKey: .price) ?? 0
        purchaseDate = try container.decodeIfPresent(String.self, forKey: .purchaseDate)
        platforms = try container.decodeIfPresent([String].self, forKey: .platforms)
    }

    var isFree: Bool { price <= 0 }

    var priceLabel: String {
        isFree ? "Gratis" : price.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR"))
    }

    /// Vero solo quando ipatool riporta esplicitamente la data d'acquisto
    /// (`list-purchases`). La ricerca non include il campo, quindi l'assenza
    /// non va interpretata come "non posseduta".
    var isOwned: Bool { purchaseDate != nil }

    var purchaseDateLabel: String? {
        guard let purchaseDate else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: purchaseDate)
            ?? ISO8601DateFormatter().date(from: purchaseDate)
        guard let date else { return purchaseDate }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var platformsLabel: String {
        guard let platforms, !platforms.isEmpty else { return "—" }
        return platforms.joined(separator: ", ")
    }

    /// Nome file suggerito per il pacchetto scaricato.
    var suggestedFileName: String {
        let safeName = trackName
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return "\(safeName) \(version).ipa"
    }
}

/// Account App Store autenticato in ipatool.
struct StoreAccount: Equatable {
    var email: String
    var name: String?

    var displayName: String {
        guard let name, !name.isEmpty else { return email }
        return "\(name) (\(email))"
    }
}
