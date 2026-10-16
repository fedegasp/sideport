import Foundation

struct InstalledApp: Identifiable, Hashable {
    let bundleIdentifier: String
    var name: String
    var shortVersion: String
    var buildVersion: String
    var applicationType: String      // User / System
    var diskUsage: Int64?
    var minimumOSVersion: String
    var isRemovable: Bool

    var id: String { bundleIdentifier }

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
        // StaticDiskUsage non e' sempre presente: dipende dagli attributi richiesti.
        if let usage = plist.int("StaticDiskUsage") ?? plist.int("DynamicDiskUsage") {
            diskUsage = Int64(usage)
        }
        minimumOSVersion = plist.string("MinimumOSVersion") ?? ""
        // Le app di sistema non possono essere disinstallate via installation_proxy.
        isRemovable = applicationType == "User"
    }
}
