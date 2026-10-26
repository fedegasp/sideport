import Foundation
import CryptoKit

/// Profilo di provisioning installato sul Mac o scelto dall'utente.
///
/// Gli entitlements restano serializzati invece che come dizionario: `[String: Any]`
/// non attraversa i confini di concorrenza, e comunque servono solo per essere
/// riscritti su disco al momento della firma.
struct ProvisioningProfile: Identifiable, Hashable, Sendable {
    let url: URL
    let uuid: String
    let name: String
    let teamName: String?
    let teamIdentifier: String?
    /// "843C67LUSB.com.example.app", con "*" finale nei profili jolly.
    let applicationIdentifier: String
    let entitlementsData: Data
    /// Profilo di sviluppo (`get-task-allow`): il debug e' permesso e i
    /// dispositivi vanno registrati uno per uno.
    let isDevelopment: Bool
    /// Profilo in-house: vale su qualunque dispositivo.
    let provisionsAllDevices: Bool
    let deviceUDIDs: [String]
    /// Impronte SHA-1 dei certificati ammessi dal profilo, nello stesso formato
    /// usato da `security find-identity`.
    let certificateSHA1s: [String]
    let creationDate: Date?
    let expirationDate: Date?

    var id: URL { url }

    init?(url: URL, plist: [String: Any]) {
        guard let identifier = (plist["Entitlements"] as? [String: Any])?.string("application-identifier")
                ?? (plist["Entitlements"] as? [String: Any])?.string("com.apple.application-identifier") else {
            return nil
        }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: entitlements,
            format: .xml,
            options: 0
        ) else { return nil }

        self.url = url
        self.uuid = plist.string("UUID") ?? url.deletingPathExtension().lastPathComponent
        self.name = plist.string("Name") ?? url.deletingPathExtension().lastPathComponent
        self.teamName = plist.string("TeamName")
        self.teamIdentifier = (plist["TeamIdentifier"] as? [String])?.first
        self.applicationIdentifier = identifier
        self.entitlementsData = data
        self.isDevelopment = entitlements.bool("get-task-allow") ?? false
        self.provisionsAllDevices = plist.bool("ProvisionsAllDevices") ?? false
        self.deviceUDIDs = plist["ProvisionedDevices"] as? [String] ?? []
        self.certificateSHA1s = (plist["DeveloperCertificates"] as? [Data])?.map(Self.sha1) ?? []
        self.creationDate = plist["CreationDate"] as? Date
        self.expirationDate = plist["ExpirationDate"] as? Date
    }

    // MARK: - Copertura

    /// Prefisso del team, la parte davanti all'identificativo dell'app.
    var teamPrefix: String {
        applicationIdentifier.components(separatedBy: ".").first ?? ""
    }

    /// "com.example.app" oppure "com.example.*" nei profili jolly.
    var bundlePattern: String {
        String(applicationIdentifier.dropFirst(min(teamPrefix.count + 1, applicationIdentifier.count)))
    }

    var isWildcard: Bool { bundlePattern.hasSuffix("*") }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    /// Un profilo jolly copre tutto cio' che inizia per il prefisso, quindi
    /// anche le estensioni, che hanno l'identificativo dell'app piu' un suffisso.
    func covers(bundleIdentifier identifier: String) -> Bool {
        guard isWildcard else { return identifier == bundlePattern }
        return identifier.hasPrefix(String(bundlePattern.dropLast()))
    }

    func covers(deviceUDID udid: String) -> Bool {
        provisionsAllDevices || deviceUDIDs.contains(udid)
    }

    func includes(identity: SigningIdentity) -> Bool {
        certificateSHA1s.contains(identity.sha1)
    }

    var teamLabel: String? {
        switch (teamName, teamIdentifier) {
        case let (name?, identifier?): return "\(name) (\(identifier))"
        case let (name?, nil): return name
        case let (nil, identifier?): return identifier
        case (nil, nil): return nil
        }
    }

    // MARK: - Entitlements per la firma

    /// Entitlements da passare a `codesign`: come quelli del profilo, ma con
    /// l'identificativo concreto al posto del jolly, che il dispositivo
    /// rifiuterebbe nella firma del binario.
    func entitlements(for bundleIdentifier: String) throws -> Data {
        var dictionary = try PlistParsing.dictionary(from: entitlementsData)
        let concrete = "\(teamPrefix).\(bundleIdentifier)"

        for key in ["application-identifier", "com.apple.application-identifier"] where dictionary[key] != nil {
            dictionary[key] = concrete
        }
        if let groups = dictionary["keychain-access-groups"] as? [String] {
            dictionary["keychain-access-groups"] = groups.map { $0.hasSuffix("*") ? concrete : $0 }
        }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    private static func sha1(_ der: Data) -> String {
        Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()
    }
}
