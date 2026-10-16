import Foundation
import AppKit

/// Libreria locale di file .ipa su disco, con cache dei metadati.
///
/// L'ispezione di un .ipa richiede di aprire lo zip, quindi i risultati sono
/// memorizzati in cache e invalidati quando cambiano dimensione o data del file.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var packages: [IPAPackage] = []
    @Published private(set) var isScanning = false
    @Published var lastError: String?
    @Published private(set) var libraryURL: URL

    private var cache: [String: CacheEntry] = [:]
    private let defaultsKey = "libraryFolderPath"

    private struct CacheEntry: Codable {
        let fileSize: Int64
        let modificationDate: Date
        let package: IPAPackage
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)
        libraryURL = stored.map { URL(fileURLWithPath: $0) } ?? Self.defaultLibraryURL
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        loadCache()
    }

    static var defaultLibraryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("IMC/Libreria", isDirectory: true)
    }

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = base.appendingPathComponent("IMC", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("metadata-cache.json")
    }

    // MARK: - Scansione

    func refresh() async {
        isScanning = true
        defer { isScanning = false }

        let fm = FileManager.default
        try? fm.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        guard let contents = try? fm.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            lastError = "Impossibile leggere la cartella \(libraryURL.path)."
            return
        }

        let ipaFiles = contents.filter { $0.pathExtension.lowercased() == "ipa" }
        var result: [IPAPackage] = []
        var failures: [String] = []

        for file in ipaFiles {
            do {
                result.append(try await package(for: file))
            } catch {
                failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        packages = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        saveCache()
    }

    private func package(for file: URL) async throws -> IPAPackage {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values.fileSize ?? 0)
        let modified = values.contentModificationDate ?? .distantPast

        if let entry = cache[file.path], entry.fileSize == size, entry.modificationDate == modified {
            return entry.package
        }

        let inspected = try await IPAInspector.inspect(url: file)
        cache[file.path] = CacheEntry(fileSize: size, modificationDate: modified, package: inspected)
        return inspected
    }

    // MARK: - Modifiche

    /// Copia i file nella cartella libreria, rinominando in caso di conflitto.
    func importPackages(from urls: [URL]) async {
        let fm = FileManager.default
        var failures: [String] = []

        for source in urls where source.pathExtension.lowercased() == "ipa" {
            var destination = libraryURL.appendingPathComponent(source.lastPathComponent)
            if destination.path == source.path { continue }

            var counter = 2
            let base = destination.deletingPathExtension().lastPathComponent
            while fm.fileExists(atPath: destination.path) {
                destination = libraryURL.appendingPathComponent("\(base) \(counter).ipa")
                counter += 1
            }
            do {
                try fm.copyItem(at: source, to: destination)
            } catch {
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        await refresh()
        if !failures.isEmpty {
            lastError = failures.joined(separator: "\n")
        }
    }

    func delete(_ package: IPAPackage) async {
        do {
            try FileManager.default.trashItem(at: package.url, resultingItemURL: nil)
            cache.removeValue(forKey: package.url.path)
            await refresh()
        } catch {
            lastError = "Impossibile spostare nel cestino: \(error.localizedDescription)"
        }
    }

    func reveal(_ package: IPAPackage) {
        NSWorkspace.shared.activateFileViewerSelecting([package.url])
    }

    func openLibraryFolder() {
        NSWorkspace.shared.open(libraryURL)
    }

    func setLibraryURL(_ url: URL) async {
        libraryURL = url
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        await refresh()
    }

    /// Versione in libreria piu' recente di quella installata, se esiste.
    func upgradeCandidate(for app: InstalledApp) -> IPAPackage? {
        packages
            .filter { $0.bundleIdentifier == app.bundleIdentifier }
            .filter { VersionCompare.isHigher($0.shortVersion, than: app.shortVersion) }
            .max { VersionCompare.isLower($0.shortVersion, than: $1.shortVersion) }
    }

    func packages(forBundleIdentifier identifier: String) -> [IPAPackage] {
        packages.filter { $0.bundleIdentifier == identifier }
    }

    // MARK: - Cache su disco

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else { return }
        cache = decoded
    }

    private func saveCache() {
        // Scarta le voci che non puntano piu' a file esistenti.
        cache = cache.filter { FileManager.default.fileExists(atPath: $0.key) }
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }
}
