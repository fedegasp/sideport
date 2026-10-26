import Foundation
import Security

/// Come e' firmato un .ipa, ricavato da quello che l'archivio porta con se':
/// il profilo di provisioning incorporato (`embedded.mobileprovision`), i
/// metadati dell'acquisto (`iTunesMetadata.plist`) e la presenza della cartella
/// `_CodeSignature` e dei file FairPlay in `SC_Info`.
///
/// Non verifica la firma: per quello servirebbe estrarre il bundle e passarlo a
/// `codesign`, che comunque su macOS non valuta le firme iOS.
struct IPASignature: Hashable, Sendable, Codable {
    enum Kind: String, Hashable, Sendable, Codable {
        /// Copia scaricata dall'App Store, legata a un Apple ID.
        case appStore
        /// Profilo con `get-task-allow`: gira solo sui dispositivi registrati.
        case development
        /// Profilo di distribuzione con elenco di dispositivi.
        case adHoc
        /// Profilo in-house, valido su qualunque dispositivo dell'azienda.
        case enterprise
        /// Profilo di distribuzione App Store, non ancora passato dallo Store.
        case distribution
        /// Nessuna firma nel bundle.
        case unsigned
        case unknown

        var label: LocalizedStringResource {
            switch self {
            case .appStore: .ui("App Store")
            case .development: .ui("Development")
            case .adHoc: .ui("Ad Hoc")
            case .enterprise: .ui("Enterprise (in-house)")
            case .distribution: .ui("App Store distribution")
            case .unsigned: .ui("Not signed")
            case .unknown: .ui("Unknown signature")
            }
        }

        var symbol: String {
            switch self {
            case .appStore: "checkmark.seal"
            case .development: "hammer"
            case .adHoc: "person.2"
            case .enterprise: "building.2"
            case .distribution: "paperplane"
            case .unsigned: "lock.open"
            case .unknown: "questionmark.circle"
            }
        }
    }

    var kind: Kind = .unknown
    /// Il bundle contiene `_CodeSignature/CodeResources`.
    var isCodeSigned = false
    /// Il binario e' cifrato con FairPlay: si installa solo con l'Apple ID che
    /// ha scaricato la copia.
    var isFairPlayProtected = false
    var profileName: String?
    var teamName: String?
    var teamIdentifier: String?
    /// Nome comune del certificato, es. "Apple Distribution: Foo (AB12CD34EF)",
    /// solo quando il profilo ne ammette uno: chi ha firmato davvero sta nel
    /// binario, e un profilo di squadra elenca i certificati di tutti.
    var certificate: String?
    /// Quanti certificati ammette il profilo.
    var certificateCount = 0
    var creationDate: Date?
    var expirationDate: Date?
    var provisionedDeviceCount: Int?
    /// Venditore dell'app sull'App Store.
    var seller: String?
    /// Apple ID a cui e' legata la copia scaricata.
    var appleID: String?

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    /// Chi ha firmato, in breve: il titolare del certificato senza il prefisso
    /// del tipo, che e' gia' detto dal genere della firma. In mancanza del
    /// certificato ripiega sul team o, per le copie dello Store, sul venditore.
    var signerLabel: String? {
        if let certificate {
            for prefix in Self.certificatePrefixes where certificate.hasPrefix(prefix) {
                return String(certificate.dropFirst(prefix.count))
            }
            return certificate
        }
        return teamName ?? seller ?? teamIdentifier
    }

    private static let certificatePrefixes = [
        "Apple Development: ",
        "Apple Distribution: ",
        "iPhone Developer: ",
        "iPhone Distribution: ",
    ]

    /// "Foo S.p.A. (AB12CD34EF)", con una sola delle due parti se l'altra manca.
    var teamLabel: String? {
        switch (teamName, teamIdentifier) {
        case let (name?, identifier?): return "\(name) (\(identifier))"
        case let (name?, nil): return name
        case let (nil, identifier?): return identifier
        case (nil, nil): return nil
        }
    }

    // MARK: - Lettura dei dati dell'archivio

    /// Campi del profilo di provisioning gia' convertito in dizionario.
    mutating func apply(profile: [String: Any]) {
        kind = Self.kind(ofProfile: profile)
        profileName = profile.string("Name")
        teamName = profile.string("TeamName")
        teamIdentifier = (profile["TeamIdentifier"] as? [String])?.first
        creationDate = profile["CreationDate"] as? Date
        expirationDate = profile["ExpirationDate"] as? Date
        provisionedDeviceCount = (profile["ProvisionedDevices"] as? [String])?.count
        let certificates = (profile["DeveloperCertificates"] as? [Data]) ?? []
        certificateCount = certificates.count
        certificate = certificates.count == 1 ? Self.commonName(ofCertificate: certificates[0]) : nil
    }

    /// Campi di `iTunesMetadata.plist`: ci sono solo nelle copie scaricate
    /// dall'App Store, quindi la loro presenza decide il tipo di firma.
    mutating func apply(storeMetadata: [String: Any]) {
        kind = .appStore
        seller = storeMetadata.string("artistName")
        appleID = storeMetadata.string("apple-id") ?? storeMetadata.string("userName")
    }

    /// `get-task-allow` distingue lo sviluppo dalla distribuzione; fra i profili
    /// di distribuzione, l'elenco dei dispositivi distingue l'ad hoc, e
    /// `ProvisionsAllDevices` l'in-house.
    static func kind(ofProfile profile: [String: Any]) -> Kind {
        let entitlements = profile["Entitlements"] as? [String: Any] ?? [:]
        if entitlements.bool("get-task-allow") == true { return .development }
        if profile.bool("ProvisionsAllDevices") == true { return .enterprise }
        if let devices = profile["ProvisionedDevices"] as? [String], !devices.isEmpty { return .adHoc }
        return .distribution
    }

    /// `embedded.mobileprovision` e' un contenitore CMS firmato: il plist sta in
    /// chiaro dentro al blob, fra l'intestazione ASN.1 e le firme, quindi si
    /// ritaglia invece di decodificare il contenitore.
    static func profile(inProvisioning data: Data) -> [String: Any]? {
        guard let plist = PlistParsing.extractPlistData(from: String(decoding: data, as: UTF8.self)) else {
            return nil
        }
        return try? PlistParsing.dictionary(from: plist)
    }

    private static func commonName(ofCertificate der: Data) -> String? {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        var name: CFString?
        guard SecCertificateCopyCommonName(certificate, &name) == errSecSuccess else { return nil }
        return name as String?
    }
}
