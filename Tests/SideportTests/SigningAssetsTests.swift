import Foundation
import Testing
@testable import Sideport

struct SigningIdentityTests {
    private let output = """
      1) 90AB4430AC44F24ADFA62A7B787B6E7ABE92A433 "Apple Development: Mario Rossi (997856FBPZ)"
      2) 292ECCDD0F224F84B0E42821D8B3ACAEF40AC5BE "iPhone Distribution: Example spa"
      3) 93a93607feaf8c30dbe19dc847907776916c92e1 "Apple Distribution: Example S.p.A. (A9QK5Z4XBH)"
      4) 87A05C4439C29FF44F49AFE5155DE61D5D8CDCE3 "SomeCorporateCertificate"
      5) 90AB4430AC44F24ADFA62A7B787B6E7ABE92A433 "Apple Development: Mario Rossi (997856FBPZ)"
         5 valid identities found
    """

    @Test func parsesHashAndNameSkippingDuplicates() {
        let identities = SigningIdentity.parse(findIdentityOutput: output)

        #expect(identities.count == 4)
        #expect(identities[0].sha1 == "90AB4430AC44F24ADFA62A7B787B6E7ABE92A433")
        #expect(identities[0].name == "Apple Development: Mario Rossi (997856FBPZ)")
        // Le impronte si confrontano con quelle dei profili, sempre maiuscole.
        #expect(identities[2].sha1 == "93A93607FEAF8C30DBE19DC847907776916C92E1")
    }

    @Test func keepsOnlyCertificatesThatSignIOSApps() {
        let names = SigningIdentity.parse(findIdentityOutput: output).filter(\.signsIOSApps).map(\.name)

        #expect(names.count == 3)
        #expect(!names.contains("SomeCorporateCertificate"))
    }

    @Test func readsTheTeamFromTheName() {
        let identities = SigningIdentity.parse(findIdentityOutput: output)

        #expect(identities[0].teamIdentifier == "997856FBPZ")
        #expect(identities[1].teamIdentifier == nil)
    }
}

struct ProvisioningProfileTests {
    private func profile(
        applicationIdentifier: String,
        getTaskAllow: Bool = true,
        devices: [String]? = ["0001"],
        provisionsAllDevices: Bool? = nil,
        expires: Date = Date(timeIntervalSinceNow: 86_400),
        keychainGroups: [String]? = nil
    ) -> ProvisioningProfile {
        var entitlements: [String: Any] = [
            "application-identifier": applicationIdentifier,
            "get-task-allow": getTaskAllow,
            "com.apple.developer.team-identifier": "AB12CD34EF",
        ]
        if let keychainGroups { entitlements["keychain-access-groups"] = keychainGroups }

        var plist: [String: Any] = [
            "UUID": "11111111-2222-3333-4444-555555555555",
            "Name": "Profilo",
            "TeamName": "Example S.p.A.",
            "TeamIdentifier": ["AB12CD34EF"],
            "Entitlements": entitlements,
            "ExpirationDate": expires,
        ]
        if let devices { plist["ProvisionedDevices"] = devices }
        if let provisionsAllDevices { plist["ProvisionsAllDevices"] = provisionsAllDevices }

        return ProvisioningProfile(url: URL(fileURLWithPath: "/tmp/p.mobileprovision"), plist: plist)!
    }

    @Test func splitsTeamPrefixFromBundlePattern() {
        let explicit = profile(applicationIdentifier: "AB12CD34EF.com.example.app")

        #expect(explicit.teamPrefix == "AB12CD34EF")
        #expect(explicit.bundlePattern == "com.example.app")
        #expect(!explicit.isWildcard)
    }

    @Test func wildcardCoversNestedExtensions() {
        let wildcard = profile(applicationIdentifier: "AB12CD34EF.com.example.*")

        #expect(wildcard.isWildcard)
        #expect(wildcard.covers(bundleIdentifier: "com.example.app"))
        #expect(wildcard.covers(bundleIdentifier: "com.example.app.notifications"))
        #expect(!wildcard.covers(bundleIdentifier: "com.other.app"))
    }

    @Test func explicitProfileCoversOneBundleOnly() {
        let explicit = profile(applicationIdentifier: "AB12CD34EF.com.example.app")

        #expect(explicit.covers(bundleIdentifier: "com.example.app"))
        #expect(!explicit.covers(bundleIdentifier: "com.example.app.notifications"))
    }

    @Test func fullWildcardCoversEverything() {
        let any = profile(applicationIdentifier: "AB12CD34EF.*")

        #expect(any.bundlePattern == "*")
        #expect(any.covers(bundleIdentifier: "com.whatever.app"))
    }

    @Test func deviceCoverageFollowsTheProfileKind() {
        let development = profile(applicationIdentifier: "AB12CD34EF.*", devices: ["0001"])
        #expect(development.covers(deviceUDID: "0001"))
        #expect(!development.covers(deviceUDID: "0002"))

        let inHouse = profile(applicationIdentifier: "AB12CD34EF.*", devices: nil, provisionsAllDevices: true)
        #expect(inHouse.covers(deviceUDID: "0002"))
    }

    @Test func reportsExpiry() {
        #expect(!profile(applicationIdentifier: "AB12CD34EF.*").isExpired)
        #expect(profile(applicationIdentifier: "AB12CD34EF.*", expires: Date(timeIntervalSinceNow: -60)).isExpired)
    }

    /// Un "*" dentro la firma del binario il dispositivo lo rifiuta: va
    /// sostituito con l'identificativo vero dell'app.
    @Test func entitlementsReplaceTheWildcardWithTheRealIdentifier() throws {
        let wildcard = profile(
            applicationIdentifier: "AB12CD34EF.com.example.*",
            keychainGroups: ["AB12CD34EF.com.example.*", "com.apple.token"]
        )

        let data = try wildcard.entitlements(for: "com.example.app.notifications")
        let written = try PlistParsing.dictionary(from: data)

        #expect(written.string("application-identifier") == "AB12CD34EF.com.example.app.notifications")
        #expect(written["keychain-access-groups"] as? [String] == [
            "AB12CD34EF.com.example.app.notifications",
            "com.apple.token",
        ])
        // Il resto del profilo passa invariato.
        #expect(written.bool("get-task-allow") == true)
        #expect(written.string("com.apple.developer.team-identifier") == "AB12CD34EF")
    }

    @Test func matchesTheIdentityByCertificateFingerprint() {
        var plist: [String: Any] = [
            "Name": "Profilo",
            "Entitlements": ["application-identifier": "AB12CD34EF.com.example.app"],
        ]
        plist["DeveloperCertificates"] = [Data("der".utf8)]
        let parsed = ProvisioningProfile(url: URL(fileURLWithPath: "/tmp/p.mobileprovision"), plist: plist)!

        // SHA-1 di "der" in maiuscolo, lo stesso formato di find-identity.
        #expect(parsed.certificateSHA1s == ["7D44C33CF9A82AB9BD5300D266784504E9772177"])
        #expect(parsed.includes(identity: SigningIdentity(
            sha1: "7D44C33CF9A82AB9BD5300D266784504E9772177",
            name: "Apple Development: X"
        )))
        #expect(!parsed.includes(identity: SigningIdentity(sha1: "0000", name: "Apple Development: Y")))
    }
}
