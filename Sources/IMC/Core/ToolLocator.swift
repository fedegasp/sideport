import Foundation

enum ExternalTool: String, CaseIterable, Identifiable {
    case ideviceID = "idevice_id"
    case ideviceInfo = "ideviceinfo"
    case idevicePair = "idevicepair"
    case ideviceInstaller = "ideviceinstaller"
    case ideviceName = "idevicename"
    case ideviceDiagnostics = "idevicediagnostics"
    case ipatool = "ipatool"

    var id: String { rawValue }

    /// Senza questi l'app non puo' fare nulla di utile.
    var isRequired: Bool {
        switch self {
        case .ideviceID, .ideviceInfo, .idevicePair, .ideviceInstaller: return true
        case .ideviceName, .ideviceDiagnostics, .ipatool: return false
        }
    }

    var purpose: String {
        switch self {
        case .ideviceID: return "Rileva i dispositivi collegati"
        case .ideviceInfo: return "Legge modello, versione iOS e spazio disco"
        case .idevicePair: return "Gestisce l'abbinamento (Autorizza questo computer)"
        case .ideviceInstaller: return "Elenca, installa e rimuove le app"
        case .ideviceName: return "Rinomina il dispositivo"
        case .ideviceDiagnostics: return "Legge lo stato della batteria"
        case .ipatool: return "Scarica le .ipa dall'App Store"
        }
    }
}

/// Risolve i binari di libimobiledevice: prima quelli inclusi nel bundle
/// (`IMC.app/Contents/Resources/tools`), poi le installazioni Homebrew note.
final class ToolLocator {
    static let shared = ToolLocator()

    private var cache: [ExternalTool: URL] = [:]
    private let lock = NSLock()

    private lazy var searchPaths: [URL] = {
        var paths: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("tools") {
            paths.append(bundled)
        }
        paths.append(URL(fileURLWithPath: "/opt/homebrew/bin"))
        paths.append(URL(fileURLWithPath: "/usr/local/bin"))
        paths.append(URL(fileURLWithPath: "/usr/bin"))
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: envPath.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }
        return paths
    }()

    func url(for tool: ExternalTool) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[tool] { return cached }
        let fm = FileManager.default
        for directory in searchPaths {
            let candidate = directory.appendingPathComponent(tool.rawValue)
            if fm.isExecutableFile(atPath: candidate.path) {
                cache[tool] = candidate
                return candidate
            }
        }
        return nil
    }

    func require(_ tool: ExternalTool) throws -> URL {
        guard let url = url(for: tool) else { throw ToolError.missing(tool) }
        return url
    }

    var missingRequiredTools: [ExternalTool] {
        ExternalTool.allCases.filter { $0.isRequired && url(for: $0) == nil }
    }

    func invalidateCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}

enum ToolError: LocalizedError {
    case missing(ExternalTool)

    var errorDescription: String? {
        switch self {
        case .missing(let tool):
            return "Strumento '\(tool.rawValue)' non trovato. Installa libimobiledevice con: brew install libimobiledevice ideviceinstaller"
        }
    }
}
