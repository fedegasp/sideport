import Foundation
import Testing
@testable import IMC

/// Prova la rifirma su una .ipa costruita sul momento, firmando ad hoc
/// (`codesign -s -`): il risultato non si installa su un dispositivo, ma passa
/// per gli stessi passaggi della firma vera.
struct IPAResignerTests {
    private let fm = FileManager.default

    // MARK: - Impalcatura

    private func makeArchive(bundleIdentifier: String, extensionIdentifier: String?) throws -> (archive: URL, root: URL) {
        let root = fm.temporaryDirectory.appending(path: "imc-test-\(UUID().uuidString)")
        let app = root.appending(path: "build/Payload/Demo.app")
        try fm.createDirectory(at: app.appending(path: "_CodeSignature"), withIntermediateDirectories: true)

        try write(info: ["CFBundleIdentifier": bundleIdentifier, "CFBundleExecutable": "Demo"], to: app)
        try fm.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: app.appending(path: "Demo"))
        try Data("old".utf8).write(to: app.appending(path: "_CodeSignature/CodeResources"))
        try Data("old".utf8).write(to: root.appending(path: "build/iTunesMetadata.plist"))

        if let extensionIdentifier {
            let appex = app.appending(path: "PlugIns/Ext.appex")
            try fm.createDirectory(at: appex, withIntermediateDirectories: true)
            try write(info: ["CFBundleIdentifier": extensionIdentifier, "CFBundleExecutable": "Ext"], to: appex)
            try fm.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: appex.appending(path: "Ext"))
        }

        let archive = root.appending(path: "demo.ipa")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qry", archive.path, "Payload"]
        zip.currentDirectoryURL = root.appending(path: "build")
        try zip.run()
        zip.waitUntilExit()

        return (archive, root)
    }

    private func write(info: [String: Any], to bundle: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
        try data.write(to: bundle.appending(path: "Info.plist"))
    }

    /// Un .mobileprovision vero e' un contenitore CMS, ma il lettore ritaglia
    /// il plist: per la prova basta il plist da solo.
    private func makeProfile(
        applicationIdentifier: String,
        in root: URL,
        named name: String = "profile.mobileprovision"
    ) throws -> ProvisioningProfile {
        let plist: [String: Any] = [
            "UUID": UUID().uuidString,
            "Name": "Profilo di prova",
            "TeamName": "Example S.p.A.",
            "TeamIdentifier": ["AB12CD34EF"],
            "ExpirationDate": Date(timeIntervalSinceNow: 86_400),
            "ProvisionedDevices": ["0001"],
            "Entitlements": [
                "application-identifier": applicationIdentifier,
                "get-task-allow": true,
                "com.apple.developer.team-identifier": "AB12CD34EF",
            ],
        ]
        let url = root.appending(path: name)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        return try #require(SigningAssets.profile(at: url))
    }

    private let adHoc = SigningIdentity(sha1: "-", name: "ad hoc")

    private func unzip(_ archive: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archive.path, "-d", folder.path]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Prove

    @Test func replacesSignatureProfileAndStoreLeftovers() async throws {
        let (archive, root) = try makeArchive(bundleIdentifier: "com.example.demo", extensionIdentifier: nil)
        defer { try? fm.removeItem(at: root) }
        let profile = try makeProfile(applicationIdentifier: "AB12CD34EF.com.example.*", in: root)
        let destination = root.appending(path: "signed.ipa")

        try await IPAResigner.resign(.init(
            archive: archive,
            identity: adHoc,
            profile: profile,
            bundleIdentifier: "com.example.demo",
            destination: destination
        ))

        let check = root.appending(path: "check")
        try unzip(destination, into: check)
        let app = check.appending(path: "Payload/Demo.app")

        #expect(fm.fileExists(atPath: app.appending(path: "embedded.mobileprovision").path))
        #expect(fm.fileExists(atPath: app.appending(path: "_CodeSignature/CodeResources").path))
        // La firma vecchia e' stata rifatta, non riciclata.
        #expect(try Data(contentsOf: app.appending(path: "_CodeSignature/CodeResources")) != Data("old".utf8))
        #expect(!fm.fileExists(atPath: check.appending(path: "iTunesMetadata.plist").path))
    }

    @Test func renamesTheAppAndItsExtensions() async throws {
        let (archive, root) = try makeArchive(
            bundleIdentifier: "com.example.demo",
            extensionIdentifier: "com.example.demo.notifications"
        )
        defer { try? fm.removeItem(at: root) }
        let profile = try makeProfile(applicationIdentifier: "AB12CD34EF.com.mine.*", in: root)
        let destination = root.appending(path: "signed.ipa")

        try await IPAResigner.resign(.init(
            archive: archive,
            identity: adHoc,
            profile: profile,
            bundleIdentifier: "com.mine.demo",
            destination: destination
        ))

        let check = root.appending(path: "check")
        try unzip(destination, into: check)
        let app = check.appending(path: "Payload/Demo.app")
        let appex = app.appending(path: "PlugIns/Ext.appex")

        #expect(try identifier(of: app) == "com.mine.demo")
        // L'estensione resta prefissata dall'app, altrimenti iOS la rifiuta.
        #expect(try identifier(of: appex) == "com.mine.demo.notifications")
        #expect(fm.fileExists(atPath: appex.appending(path: "embedded.mobileprovision").path))
        #expect(fm.fileExists(atPath: appex.appending(path: "_CodeSignature/CodeResources").path))
    }

    /// Con i profili espliciti, come li fa Xcode, ogni estensione ha il suo.
    @Test func signsExtensionsWithTheirOwnProfile() async throws {
        let (archive, root) = try makeArchive(
            bundleIdentifier: "com.example.demo",
            extensionIdentifier: "com.example.demo.notifications"
        )
        defer { try? fm.removeItem(at: root) }
        let appProfile = try makeProfile(applicationIdentifier: "AB12CD34EF.com.example.demo", in: root)
        let extensionProfile = try makeProfile(
            applicationIdentifier: "AB12CD34EF.com.example.demo.notifications",
            in: root,
            named: "extension.mobileprovision"
        )
        let destination = root.appending(path: "signed.ipa")

        try await IPAResigner.resign(.init(
            archive: archive,
            identity: adHoc,
            profile: appProfile,
            bundleIdentifier: "com.example.demo",
            destination: destination,
            extensionProfiles: ["com.example.demo.notifications": extensionProfile]
        ))

        let check = root.appending(path: "check")
        try unzip(destination, into: check)
        let appex = check.appending(path: "Payload/Demo.app/PlugIns/Ext.appex")
        let embedded = try Data(contentsOf: appex.appending(path: "embedded.mobileprovision"))

        #expect(embedded == (try Data(contentsOf: extensionProfile.url)))
    }

    @Test func refusesABundleTheProfileDoesNotCover() async throws {
        let (archive, root) = try makeArchive(bundleIdentifier: "com.example.demo", extensionIdentifier: nil)
        defer { try? fm.removeItem(at: root) }
        let profile = try makeProfile(applicationIdentifier: "AB12CD34EF.com.other.app", in: root)

        await #expect(throws: IPAResigner.ResignError.self) {
            try await IPAResigner.resign(.init(
                archive: archive,
                identity: adHoc,
                profile: profile,
                bundleIdentifier: "com.example.demo",
                destination: root.appending(path: "signed.ipa")
            ))
        }
    }

    private func identifier(of bundle: URL) throws -> String? {
        let data = try Data(contentsOf: bundle.appending(path: "Info.plist"))
        return try PlistParsing.dictionary(from: data).string("CFBundleIdentifier")
    }
}
