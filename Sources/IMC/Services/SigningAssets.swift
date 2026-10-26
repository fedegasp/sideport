import Foundation

/// Materiale di firma disponibile sul Mac: le identita' nel portachiavi e i
/// profili di provisioning installati da Xcode o da Apple Configurator.
enum SigningAssets {
    private static let security = URL(fileURLWithPath: "/usr/bin/security")

    /// Solo le identita' valide per le app iOS, in ordine alfabetico.
    static func identities() async -> [SigningIdentity] {
        guard let result = try? await ProcessRunner.run(security, ["find-identity", "-v", "-p", "codesigning"]),
              result.succeeded else { return [] }
        return SigningIdentity.parse(findIdentityOutput: result.stdout)
            .filter(\.signsIOSApps)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Le due cartelle dove finiscono i profili: la prima e' quella storica,
    /// la seconda quella usata da Xcode 16 in poi.
    static var profileDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/MobileDevice/Provisioning Profiles"),
            home.appending(path: "Library/Developer/Xcode/UserData/Provisioning Profiles"),
        ]
    }

    /// Profili installati, senza i doppioni che nascono quando lo stesso
    /// profilo sta in entrambe le cartelle.
    static func installedProfiles() -> [ProvisioningProfile] {
        let fm = FileManager.default
        var byUUID: [String: ProvisioningProfile] = [:]

        for directory in profileDirectories {
            let contents = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in contents where url.pathExtension.lowercased() == "mobileprovision" {
                guard let profile = profile(at: url) else { continue }
                if let existing = byUUID[profile.uuid],
                   (existing.creationDate ?? .distantPast) >= (profile.creationDate ?? .distantPast) {
                    continue
                }
                byUUID[profile.uuid] = profile
            }
        }

        return byUUID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func profile(at url: URL) -> ProvisioningProfile? {
        guard let data = try? Data(contentsOf: url),
              let plist = IPASignature.profile(inProvisioning: data) else { return nil }
        return ProvisioningProfile(url: url, plist: plist)
    }
}
