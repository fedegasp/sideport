import Foundation

/// Estrazione di voci da un .ipa tramite `unzip`.
///
/// Le estrazioni parziali passano per una cartella temporanea: `unzip` ricrea
/// sempre l'intero percorso dell'archivio, mentre nella cartella scelta
/// dall'utente serve solo l'elemento, con il suo nome.
enum IPAExtractor {
    private static let unzip = URL(fileURLWithPath: "/usr/bin/unzip")

    enum ExtractError: LocalizedError {
        case failed(String)
        case nothingExtracted(String)

        var errorDescription: String? {
            switch self {
            case .failed(let detail): return String.ui("Extraction failed: \(detail)")
            case .nothingExtracted(let path): return String.ui("The archive does not contain “\(path)”.")
            }
        }
    }

    /// Estrae tutto in una sottocartella di `destination` chiamata come la .ipa.
    @discardableResult
    static func extractAll(from archive: URL, to destination: URL) async throws -> URL {
        let folder = try makeDirectory(named: archive.deletingPathExtension().lastPathComponent, in: destination)
        try await run(["-o", "-q", archive.path, "-d", folder.path])
        return folder
    }

    /// Estrae le voci indicate in `destination`, ognuna con il proprio nome.
    @discardableResult
    static func extract(_ entries: [IPAEntry], from archive: URL, to destination: URL) async throws -> [URL] {
        var extracted: [URL] = []
        for entry in entries {
            let temporary = try await extractToTemporary(path: entry.path, isDirectory: entry.isDirectory, from: archive)
            let target = uniqueURL(for: temporary.lastPathComponent, in: destination)
            try FileManager.default.moveItem(at: temporary, to: target)
            try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent())
            extracted.append(target)
        }
        return extracted
    }

    /// Estrae una sola voce in una cartella temporanea e ne restituisce il percorso.
    static func extractToTemporary(path: String, isDirectory: Bool, from archive: URL) async throws -> URL {
        let staging = try makeStaging()
        try await run(
            ["-o", "-q", archive.path] + patterns(for: path, isDirectory: isDirectory) + ["-d", staging.path],
            toleratingUnmatched: true
        )
        return try verify(path: path, in: staging)
    }

    /// Variante sincrona per il trascinamento: `onDrag` deve restituire subito
    /// l'elemento da trascinare, e consegnare un file gia' estratto evita le
    /// promesse, che il Finder in questo caso non arriva a richiedere.
    static func extractToTemporarySync(path: String, isDirectory: Bool, from archive: URL) throws -> URL {
        let staging = try makeStaging()

        let process = Process()
        process.executableURL = unzip
        process.arguments = ["-o", "-q", archive.path] + patterns(for: path, isDirectory: isDirectory) + ["-d", staging.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        return try verify(path: path, in: staging)
    }

    private static func makeStaging() throws -> URL {
        purgeStaleStaging()
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(stagingPrefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    private static let stagingPrefix = "imc-extract-"

    /// Dopo un trascinamento la cartella d'appoggio resta sul disco: il Finder
    /// sposta solo l'elemento. Si ripuliscono quelle di piu' di un'ora fa.
    private static func purgeStaleStaging() {
        let fm = FileManager.default
        let contents = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        for url in contents ?? [] where url.lastPathComponent.hasPrefix(stagingPrefix) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, Date().timeIntervalSince(modified) > 3600 else { continue }
            try? fm.removeItem(at: url)
        }
    }

    /// Per una cartella servono due pattern: la voce stessa (negli zip ha la
    /// barra finale) e il suo contenuto. Se l'archivio non elenca le cartelle il
    /// primo non trova nulla, quindi il risultato si verifica sul disco.
    private static func patterns(for path: String, isDirectory: Bool) -> [String] {
        isDirectory ? [escape(path) + "/", escape(path) + "/*"] : [escape(path)]
    }

    private static func verify(path: String, in staging: URL) throws -> URL {
        let extracted = staging.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            try? FileManager.default.removeItem(at: staging)
            throw ExtractError.nothingExtracted(path)
        }
        return extracted
    }

    // MARK: - Dettagli

    /// `unzip` esce con 1 per i soli avvisi e con 11 quando uno dei pattern
    /// indicati non ha corrispondenze, anche se gli altri hanno estratto tutto.
    private static func run(_ arguments: [String], toleratingUnmatched: Bool = false) async throws {
        let result = try await ProcessRunner.run(unzip, arguments)
        let accepted: Set<Int32> = toleratingUnmatched ? [0, 1, 11] : [0, 1]
        guard accepted.contains(result.exitCode) else {
            throw ExtractError.failed(result.failureMessage)
        }
    }

    /// `unzip` interpreta i nomi come pattern shell: i metacaratteri vanno protetti.
    private static func escape(_ path: String) -> String {
        var escaped = ""
        for character in path {
            if "*?[]\\".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    private static func makeDirectory(named name: String, in parent: URL) throws -> URL {
        let url = uniqueURL(for: name, in: parent)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Aggiunge un progressivo se nella cartella esiste gia' un elemento con quel nome.
    private static func uniqueURL(for name: String, in parent: URL) -> URL {
        let candidate = parent.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 2...999 {
            let attempt = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let url = parent.appendingPathComponent(attempt)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return parent.appendingPathComponent("\(base) \(UUID().uuidString)")
    }
}
