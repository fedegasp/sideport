import Foundation

struct InstalledApp: Identifiable, Hashable {
    let bundleIdentifier: String
    var name: String
    var shortVersion: String
    var buildVersion: String
    var applicationType: String      // User / System
    /// Pacchetto dell'app (`StaticDiskUsage`).
    var appDiskUsage: Int64?
    /// Documenti e dati (`DynamicDiskUsage`).
    var dataDiskUsage: Int64?
    var minimumOSVersion: String
    var isRemovable: Bool

    var id: String { bundleIdentifier }

    /// `installation_proxy` restituisce solo gli attributi richiesti, e le
    /// dimensioni solo se richieste esplicitamente: l'elenco deve coprire tutto
    /// cio' che legge `init(plist:)`.
    static let requestedAttributes = [
        "CFBundleIdentifier",
        "CFBundleDisplayName",
        "CFBundleName",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "ApplicationType",
        "MinimumOSVersion",
        "StaticDiskUsage",
        "DynamicDiskUsage",
    ]

    /// Spazio totale, come in Impostazioni > Generali > Spazio iPhone.
    var diskUsage: Int64? {
        guard appDiskUsage != nil || dataDiskUsage != nil else { return nil }
        return (appDiskUsage ?? 0) + (dataDiskUsage ?? 0)
    }

    var versionLabel: String {
        if shortVersion.isEmpty { return buildVersion }
        if buildVersion.isEmpty || buildVersion == shortVersion { return shortVersion }
        return "\(shortVersion) (\(buildVersion))"
    }

    init(plist: [String: Any]) {
        bundleIdentifier = plist.string("CFBundleIdentifier") ?? "sconosciuto"
        name = plist.string("CFBundleDisplayName")
            ?? plist.string("CFBundleName")
            ?? bundleIdentifier
        shortVersion = plist.string("CFBundleShortVersionString") ?? ""
        buildVersion = plist.string("CFBundleVersion") ?? ""
        applicationType = plist.string("ApplicationType") ?? "User"
        appDiskUsage = plist.int("StaticDiskUsage").map(Int64.init)
        dataDiskUsage = plist.int("DynamicDiskUsage").map(Int64.init)
        minimumOSVersion = plist.string("MinimumOSVersion") ?? ""
        // Le app di sistema non possono essere disinstallate via installation_proxy.
        isRemovable = applicationType == "User"
    }
}
