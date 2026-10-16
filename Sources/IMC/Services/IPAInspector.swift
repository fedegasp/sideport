import Foundation
import AppKit

/// Legge i metadati da un archivio .ipa senza estrarlo del tutto.
///
/// Un .ipa e' uno zip con struttura `Payload/<Nome>.app/`. Si leggono solo
/// `Info.plist` e l'icona, estratti su stdout da `unzip -p`.
enum IPAInspector {
    private static let unzip = URL(fileURLWithPath: "/usr/bin/unzip")

    enum InspectError: LocalizedError {
        case notAnArchive(String)
        case missingInfoPlist

        var errorDescription: String? {
            switch self {
            case .notAnArchive(let detail): return String.ui("Cannot read the .ipa archive: \(detail)")
            case .missingInfoPlist: return String.ui("The archive does not contain Payload/<App>.app/Info.plist: it does not look like a valid .ipa.")
            }
        }
    }

    static func inspect(url: URL) async throws -> IPAPackage {
        let entries = try await listEntries(in: url)

        guard let infoPlistEntry = entries.first(where: isAppInfoPlist) else {
            throw InspectError.missingInfoPlist
        }
        let appDirectory = String(infoPlistEntry.dropLast("Info.plist".count))

        let plistData = try await extract(entry: infoPlistEntry, from: url)
        let info = try PlistParsing.dictionary(from: plistData)

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date) ?? Date()

        let signing: IPAPackage.Signing
        if entries.contains("iTunesMetadata.plist") {
            signing = .appStore
        } else if entries.contains(appDirectory + "embedded.mobileprovision") {
            signing = .provisioned
        } else {
            signing = .unknown
        }

        let icon = await extractIcon(from: url, appDirectory: appDirectory, info: info, entries: entries)

        return IPAPackage(
            url: url,
            bundleIdentifier: info.string("CFBundleIdentifier") ?? "sconosciuto",
            name: info.string("CFBundleDisplayName")
                ?? info.string("CFBundleName")
                ?? url.deletingPathExtension().lastPathComponent,
            shortVersion: info.string("CFBundleShortVersionString") ?? "",
            buildVersion: info.string("CFBundleVersion") ?? "",
            minimumOSVersion: info.string("MinimumOSVersion") ?? "",
            supportedPlatforms: info["CFBundleSupportedPlatforms"] as? [String] ?? [],
            supportedDeviceFamilies: (info["UIDeviceFamily"] as? [NSNumber])?.map(\.intValue) ?? [],
            fileSize: fileSize,
            modificationDate: modified,
            signing: signing,
            iconData: icon
        )
    }

    // MARK: - Lettura dell'archivio

    private static func listEntries(in url: URL) async throws -> [String] {
        let result = try await ProcessRunner.run(unzip, ["-Z1", url.path])
        guard result.succeeded else {
            throw InspectError.notAnArchive(result.failureMessage)
        }
        return result.stdout.split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func extract(entry: String, from url: URL) async throws -> Data {
        let (code, data, stderr) = try await ProcessRunner.runData(unzip, ["-p", url.path, entry])
        guard code == 0, !data.isEmpty else {
            throw InspectError.notAnArchive(stderr.isEmpty ? String.ui("entry “\(entry)” could not be extracted") : stderr)
        }
        return data
    }

    /// Accetta solo `Payload/<Qualcosa>.app/Info.plist`, escludendo quelli di
    /// estensioni e framework annidati.
    private static func isAppInfoPlist(_ entry: String) -> Bool {
        let components = entry.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 3
            && components[0] == "Payload"
            && components[1].hasSuffix(".app")
            && components[2] == "Info.plist"
    }

    // MARK: - Contenuto dell'archivio

    /// Elenco completo delle voci con le dimensioni non compresse.
    static func contents(of url: URL) async throws -> [IPAEntry] {
        let result = try await ProcessRunner.run(unzip, ["-l", url.path])
        guard result.succeeded else {
            throw InspectError.notAnArchive(result.failureMessage)
        }
        return parseListing(result.stdout)
    }

    /// Una riga di `unzip -l` e' "dimensione data ora   percorso": il percorso
    /// e' separato da tre spazi e puo' contenerne a sua volta, quindi si taglia
    /// li' invece di dividere la riga sugli spazi. Intestazione, separatori e
    /// riga dei totali non corrispondono al pattern e vengono scartati.
    private static func parseListing(_ output: String) -> [IPAEntry] {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)\s+\S+\s+\S+\s{3}(.+)$"#) else { return [] }
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let sizeRange = Range(match.range(at: 1), in: text),
                  let pathRange = Range(match.range(at: 2), in: text) else { return nil }
            let path = String(text[pathRange])
            guard !path.isEmpty else { return nil }
            let isDirectory = path.hasSuffix("/")
            return IPAEntry(
                path: isDirectory ? String(path.dropLast()) : path,
                size: Int64(text[sizeRange]) ?? 0,
                isDirectory: isDirectory
            )
        }
    }

    // MARK: - Icona

    private static func extractIcon(from url: URL, appDirectory: String, info: [String: Any], entries: [String]) async -> Data? {
        for candidate in iconCandidates(appDirectory: appDirectory, info: info, entries: entries) {
            guard let data = try? await extract(entry: candidate, from: url) else { continue }
            if let normalized = await normalizePNG(data) { return normalized }
        }
        return nil
    }

    /// Ordina i candidati dalla risoluzione piu' alta alla piu' bassa.
    private static func iconCandidates(appDirectory: String, info: [String: Any], entries: [String]) -> [String] {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
            if let files = primary["CFBundleIconFiles"] as? [String] { names.append(contentsOf: files) }
            if let name = primary["CFBundleIconName"] as? String { names.append(name) }
        }
        if let legacy = info["CFBundleIconFiles"] as? [String] { names.append(contentsOf: legacy) }
        if let single = info.string("CFBundleIconFile") { names.append(single) }

        let suffixes = ["@3x.png", "@2x.png", ".png", "@2x~ipad.png", "~ipad.png"]
        var candidates: [String] = []
        for name in names {
            for suffix in suffixes {
                let entry = appDirectory + name + suffix
                if entries.contains(entry) { candidates.append(entry) }
            }
            // Le icone generate dall'asset catalog hanno nomi tipo AppIcon60x60@2x.png.
            let prefix = appDirectory + name
            candidates.append(contentsOf: entries.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".png") })
        }
        if candidates.isEmpty {
            candidates = entries.filter {
                $0.hasPrefix(appDirectory)
                    && $0.hasSuffix(".png")
                    && $0.dropFirst(appDirectory.count).contains("AppIcon")
            }
        }

        // Ordine decrescente per dimensione dichiarata nel nome (es. 60x60@3x).
        var seen = Set<String>()
        return candidates
            .filter { seen.insert($0).inserted }
            .sorted { pixelSize(of: $0) > pixelSize(of: $1) }
    }

    private static func pixelSize(of entry: String) -> Int {
        let name = entry.components(separatedBy: "/").last ?? entry
        let scale = name.contains("@3x") ? 3 : (name.contains("@2x") ? 2 : 1)
        var base = 0
        if let range = name.range(of: #"(\d+)x\1"#, options: .regularExpression) {
            base = Int(name[range].components(separatedBy: "x")[0]) ?? 0
        }
        return base * scale
    }

    /// Le icone dei .ipa dell'App Store usano il formato CgBI di Apple, che
    /// `NSImage` non decodifica. Se disponibile si usa `pngcrush` di Xcode per
    /// riconvertirle in PNG standard.
    private static func normalizePNG(_ data: Data) async -> Data? {
        if NSImage(data: data) != nil { return data }

        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("imc-icon-\(UUID().uuidString)")
        guard (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? fm.removeItem(at: directory) }

        let input = directory.appendingPathComponent("in.png")
        let output = directory.appendingPathComponent("out.png")
        guard (try? data.write(to: input)) != nil else { return nil }

        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        guard fm.isExecutableFile(atPath: xcrun.path) else { return nil }
        let result = try? await ProcessRunner.run(xcrun, [
            "-sdk", "iphoneos", "pngcrush", "-q", "-revert-iphone-optimizations",
            input.path, output.path
        ])
        guard result?.succeeded == true, let converted = try? Data(contentsOf: output) else { return nil }
        return NSImage(data: converted) != nil ? converted : nil
    }
}
