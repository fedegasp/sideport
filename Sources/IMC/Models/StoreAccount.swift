import Foundation

/// Account App Store autenticato in ipatool.
struct StoreAccount: Equatable {
    var email: String
    var name: String?

    var displayName: String {
        guard let name, !name.isEmpty else { return email }
        return "\(name) (\(email))"
    }
}
