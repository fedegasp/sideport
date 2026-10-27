import Foundation
import Observation

/// Icone delle app installate, lette dal dispositivo con l'helper `sideport-icon`.
///
/// Un'icona cambia solo con una nuova versione dell'app, quindi resta in cache
/// su disco per bundle ID e versione: alle aperture successive non serve
/// un'altra sessione SpringBoard.
@MainActor
@Observable
final class AppIconStore {
    private(set) var icons: [String: Data] = [:]

    /// Evita richieste doppie quando piu' task chiedono lo stesso elenco.
    @ObservationIgnored private var inFlight: Set<String> = []

    func icon(for app: InstalledApp) -> Data? {
        icons[Self.cacheKey(for: app)]
    }

    func load(_ apps: [InstalledApp], udid: String) async {
        let requests = apps
            .map { IconRequest(key: Self.cacheKey(for: $0), bundleIdentifier: $0.bundleIdentifier) }
            .filter { icons[$0.key] == nil && !inFlight.contains($0.key) }
        guard !requests.isEmpty else { return }

        let keys = Set(requests.map(\.key))
        inFlight.formUnion(keys)
        defer { inFlight.subtract(keys) }

        let found = await Self.fetch(requests, udid: udid)
        if !found.isEmpty {
            icons.merge(found) { _, new in new }
        }
    }

    // MARK: - Lettura

    struct IconRequest: Sendable {
        let key: String
        let bundleIdentifier: String
    }

    nonisolated static func cacheKey(for app: InstalledApp) -> String {
        let raw = "\(app.bundleIdentifier)_\(app.shortVersion)_\(app.buildVersion)"
        return raw.replacing("/", with: "-").replacing(":", with: "-")
    }

    /// Bundle ID per cui l'helper ha scritto un'icona (righe `OK <bundleid>`).
    nonisolated static func fetchedBundleIdentifiers(in output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix("OK ") ? String(line.dropFirst(3)) : nil
        })
    }

    /// Prima la cache su disco, poi il dispositivo per le icone mancanti. Gli
    /// errori non si propagano: senza icona la riga mostra il segnaposto.
    nonisolated private static func fetch(_ requests: [IconRequest], udid: String) async -> [String: Data] {
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        var result: [String: Data] = [:]
        var missing: [IconRequest] = []
        for request in requests {
            if let data = try? Data(contentsOf: cacheURL(for: request.key)) {
                result[request.key] = data
            } else {
                missing.append(request)
            }
        }

        guard !missing.isEmpty, let tool = ToolLocator.shared.url(for: .iconHelper) else { return result }

        let staging = fm.temporaryDirectory.appending(path: "sideport-icons-\(UUID().uuidString)", directoryHint: .isDirectory)
        guard (try? fm.createDirectory(at: staging, withIntermediateDirectories: true)) != nil else { return result }
        defer { try? fm.removeItem(at: staging) }

        let arguments = ["-u", udid, "-o", staging.path] + missing.map(\.bundleIdentifier)
        guard let output = try? await ProcessRunner.run(tool, arguments) else { return result }

        // Anche con un'uscita non nulla le icone gia' scritte sono valide.
        let fetched = fetchedBundleIdentifiers(in: output.stdout)
        for request in missing where fetched.contains(request.bundleIdentifier) {
            let file = staging.appending(path: request.bundleIdentifier + ".png")
            guard let data = try? Data(contentsOf: file) else { continue }
            try? data.write(to: cacheURL(for: request.key), options: .atomic)
            result[request.key] = data
        }
        return result
    }

    nonisolated private static var cacheDirectory: URL {
        URL.cachesDirectory.appending(path: "Sideport/Icone", directoryHint: .isDirectory)
    }

    nonisolated private static func cacheURL(for key: String) -> URL {
        cacheDirectory.appending(path: key + ".png")
    }
}
