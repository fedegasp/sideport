import Foundation

/// Risolve i binari di libimobiledevice: prima quelli inclusi nel bundle
/// (`Sideport.app/Contents/Resources/tools`), poi le installazioni Homebrew note.
///
/// Viene interrogato sia dal main actor sia dai task dei servizi, con accesso
/// sincrono: la cache e' protetta da lock.
final class ToolLocator: @unchecked Sendable {
    static let shared = ToolLocator()

    private var cache: [ExternalTool: URL] = [:]
    private let lock = NSLock()

    private let searchPaths: [URL] = {
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
