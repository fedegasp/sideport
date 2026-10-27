import Foundation

/// Rifirma una .ipa con un'identita' del portachiavi e un profilo di
/// provisioning, cosi' da poterla installare su un dispositivo che la firma
/// originale non copre.
///
/// E' lo stesso lavoro che fa Xcode: si sostituisce il profilo incorporato, si
/// riscrivono gli entitlements con l'identificativo concreto e si firma dal
/// basso verso l'alto (librerie, framework, estensioni e infine il bundle
/// dell'app), poi si ricomprime l'archivio.
///
/// Non si applica alle copie dell'App Store: il binario e' cifrato con
/// FairPlay e nessuna firma lo rende leggibile a un altro Apple ID.
enum IPAResigner {
    private static let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
    private static let zip = URL(fileURLWithPath: "/usr/bin/zip")
    private static let codesign = URL(fileURLWithPath: "/usr/bin/codesign")

    struct Request: Sendable {
        let archive: URL
        let identity: SigningIdentity
        let profile: ProvisioningProfile
        /// Identificativo che l'app deve avere dopo la firma: diverso da quello
        /// originale solo quando il profilo non e' jolly e copre un'altra app.
        let bundleIdentifier: String
        /// File .ipa da scrivere.
        let destination: URL
        /// Profili per le estensioni che il profilo dell'app non copre, per
        /// identificativo: con i profili espliciti ogni bundle vuole il suo,
        /// come nei target di Xcode.
        var extensionProfiles: [String: ProvisioningProfile] = [:]
        /// Versione da scrivere al posto di quella dell'archivio, quando serve
        /// distinguere due rifirme della stessa app; `nil` lascia l'originale.
        var shortVersion: String?
        var buildVersion: String?
    }

    enum ResignError: LocalizedError {
        case noAppBundle
        case fairPlayProtected
        case unreadableInfoPlist(String)
        case notCovered(bundle: String, profile: String)
        case commandFailed(tool: String, detail: String)

        var errorDescription: String? {
            switch self {
            case .noAppBundle:
                return String.ui("The archive does not contain Payload/<App>.app: it does not look like a valid .ipa.")
            case .fairPlayProtected:
                return String.ui("The binary is encrypted with FairPlay: an App Store copy cannot be re-signed.")
            case .unreadableInfoPlist(let name):
                return String.ui("Cannot read the Info.plist of “\(name)”.")
            case .notCovered(let bundle, let profile):
                return String.ui("The profile “\(profile)” does not cover “\(bundle)”.")
            case .commandFailed(let tool, let detail):
                return String.ui("\(tool) failed: \(detail)")
            }
        }
    }

    // MARK: - Rifirma

    @discardableResult
    static func resign(
        _ request: Request,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "imc-resign-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        progress(String.ui("Extracting the archive…"))
        // `unzip` esce con 1 per i soli avvisi.
        try await run(unzip, ["-o", "-q", request.archive.path, "-d", work.path], accepting: [0, 1])

        let app = try appBundle(in: work)
        guard !fm.fileExists(atPath: app.appending(path: "SC_Info").path) else {
            throw ResignError.fairPlayProtected
        }

        progress(String.ui("Preparing the bundle…"))
        try strip(work: work, app: app)
        try setVersion(of: app, short: request.shortVersion, build: request.buildVersion)
        // Il profilo di ogni bundle si risolve prima di firmare: meglio
        // fermarsi subito che a meta' dell'albero.
        let plan = try rename(app: app, to: request.bundleIdentifier).map {
            (url: $0.url, bundleIdentifier: $0.bundleIdentifier, profile: try profile(for: $0.bundleIdentifier, in: request))
        }

        progress(String.ui("Signing with \(request.identity.name)…"))
        try await sign(plan: plan, app: app, identity: request.identity, in: work)

        progress(String.ui("Rebuilding the archive…"))
        let archive = work.appending(path: "signed.ipa")
        // Lo zip si crea dalla cartella di lavoro: i percorsi dentro l'archivio
        // devono partire da Payload, non dalla radice del disco.
        try await run(zip, ["-qry", archive.path, "Payload"], accepting: [0], in: work)

        try? fm.removeItem(at: request.destination)
        try fm.moveItem(at: archive, to: request.destination)
        return request.destination
    }

    // MARK: - Preparazione

    private static func appBundle(in work: URL) throws -> URL {
        let payload = work.appending(path: "Payload")
        let contents = (try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else { throw ResignError.noAppBundle }
        return app
    }

    /// Toglie dall'archivio cio' che non deve sopravvivere alla rifirma: le
    /// firme vecchie, i metadati dell'acquisto e i resti di FairPlay.
    private static func strip(work: URL, app: URL) throws {
        let fm = FileManager.default

        for name in ["iTunesMetadata.plist", "iTunesArtwork", "iTunesArtwork@2x", "META-INF"] {
            try? fm.removeItem(at: work.appending(path: name))
        }

        guard let walker = fm.enumerator(at: app, includingPropertiesForKeys: nil) else { return }
        var doomed: [URL] = []
        for case let url as URL in walker {
            switch url.lastPathComponent {
            case "_CodeSignature", "SC_Info", ".DS_Store": doomed.append(url)
            default: break
            }
        }
        for url in doomed { try? fm.removeItem(at: url) }
    }

    /// Riscrive la versione dichiarata dall'app.
    ///
    /// Tocca solo il bundle principale: e' la versione che il dispositivo
    /// mostra e con cui distingue due installazioni della stessa app, mentre
    /// quelle di estensioni e framework non arrivano fino all'utente.
    private static func setVersion(of app: URL, short: String?, build: String?) throws {
        guard short != nil || build != nil else { return }
        try updateInfoPlist(of: app) { info in
            if let short { info["CFBundleShortVersionString"] = short }
            if let build { info["CFBundleVersion"] = build }
        }
    }

    /// Allinea gli identificativi al profilo e restituisce i bundle da
    /// firmare, dal piu' annidato fino al bundle dell'app.
    ///
    /// Le estensioni devono restare prefissate dall'identificativo dell'app,
    /// quindi quando l'app cambia nome cambiano anche loro.
    private static func rename(
        app: URL,
        to bundleIdentifier: String
    ) throws -> [(url: URL, bundleIdentifier: String)] {
        let original = try infoPlist(of: app).string("CFBundleIdentifier") ?? bundleIdentifier

        var result: [(url: URL, bundleIdentifier: String)] = []
        for nested in nestedBundles(in: app) {
            let current = try infoPlist(of: nested).string("CFBundleIdentifier") ?? ""
            let renamed = current.hasPrefix(original + ".")
                ? bundleIdentifier + current.dropFirst(original.count)
                : current
            if renamed != current {
                try updateInfoPlist(of: nested) { $0["CFBundleIdentifier"] = renamed }
            }
            result.append((nested, renamed))
        }

        if bundleIdentifier != original {
            try updateInfoPlist(of: app) { $0["CFBundleIdentifier"] = bundleIdentifier }
        }
        result.append((app, bundleIdentifier))
        return result
    }

    /// Estensioni e app annidate (per esempio quella di watchOS), dalla piu'
    /// profonda in su: `codesign` rifiuta un bundle che ne contiene uno non
    /// ancora firmato.
    private static func nestedBundles(in app: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where ["appex", "app"].contains(url.pathExtension) {
            found.append(url)
        }
        return found.sorted { $0.pathComponents.count > $1.pathComponents.count }
    }

    /// Librerie e framework: non hanno entitlements, ma vanno firmati prima dei
    /// bundle che li contengono.
    private static func nestedCode(in app: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where ["framework", "dylib"].contains(url.pathExtension) {
            found.append(url)
        }
        return found.sorted { $0.pathComponents.count > $1.pathComponents.count }
    }

    // MARK: - Firma

    /// Il profilo dell'app, oppure quello scelto per l'estensione quando il
    /// primo non la copre.
    private static func profile(for bundleIdentifier: String, in request: Request) throws -> ProvisioningProfile {
        if request.profile.covers(bundleIdentifier: bundleIdentifier) { return request.profile }
        if let other = request.extensionProfiles[bundleIdentifier],
           other.covers(bundleIdentifier: bundleIdentifier) {
            return other
        }
        throw ResignError.notCovered(bundle: bundleIdentifier, profile: request.profile.name)
    }

    private static func sign(
        plan: [(url: URL, bundleIdentifier: String, profile: ProvisioningProfile)],
        app: URL,
        identity: SigningIdentity,
        in work: URL
    ) async throws {
        for code in nestedCode(in: app) {
            try await sign(code, identity: identity, entitlements: nil)
        }
        for bundle in plan {
            let profileCopy = bundle.url.appending(path: "embedded.mobileprovision")
            try? FileManager.default.removeItem(at: profileCopy)
            try FileManager.default.copyItem(at: bundle.profile.url, to: profileCopy)

            let entitlements = work.appending(path: "\(bundle.bundleIdentifier).entitlements")
            try bundle.profile.entitlements(for: bundle.bundleIdentifier).write(to: entitlements)
            try await sign(bundle.url, identity: identity, entitlements: entitlements)
        }
    }

    /// `--generate-entitlement-der` aggiunge la copia DER degli entitlements,
    /// che iOS 15 e successivi pretendono.
    private static func sign(_ url: URL, identity: SigningIdentity, entitlements: URL?) async throws {
        var arguments = ["--force", "--sign", identity.sha1, "--generate-entitlement-der"]
        if let entitlements { arguments += ["--entitlements", entitlements.path] }
        arguments.append(url.path)
        try await run(codesign, arguments, accepting: [0])
    }

    // MARK: - Dettagli

    private static func infoPlist(of bundle: URL) throws -> [String: Any] {
        let url = bundle.appending(path: "Info.plist")
        guard let data = try? Data(contentsOf: url),
              let dictionary = try? PlistParsing.dictionary(from: data) else {
            throw ResignError.unreadableInfoPlist(bundle.lastPathComponent)
        }
        return dictionary
    }

    /// Riscrive l'Info.plist conservando il formato originale, che nelle .ipa
    /// e' quasi sempre binario.
    private static func updateInfoPlist(of bundle: URL, _ change: (inout [String: Any]) -> Void) throws {
        let url = bundle.appending(path: "Info.plist")
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let data = try? Data(contentsOf: url),
              var dictionary = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: &format
              ) as? [String: Any] else {
            throw ResignError.unreadableInfoPlist(bundle.lastPathComponent)
        }
        change(&dictionary)
        let updated = try PropertyListSerialization.data(fromPropertyList: dictionary, format: format, options: 0)
        try updated.write(to: url)
    }

    private static func run(
        _ executable: URL,
        _ arguments: [String],
        accepting: Set<Int32>,
        in directory: URL? = nil
    ) async throws {
        let result = try await ProcessRunner.run(executable, arguments, currentDirectory: directory)
        guard accepting.contains(result.exitCode) else {
            throw ResignError.commandFailed(tool: executable.lastPathComponent, detail: result.failureMessage)
        }
    }
}
