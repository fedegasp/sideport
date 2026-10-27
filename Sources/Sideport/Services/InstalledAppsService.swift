import Foundation
import Observation

/// Elenca le app presenti su un dispositivo tramite `installation_proxy`.
@MainActor
@Observable
final class InstalledAppsService {
    private(set) var appsByDevice: [String: [InstalledApp]] = [:]
    private(set) var loadingUDIDs: Set<String> = []
    private(set) var errorsByDevice: [String: String] = [:]

    enum Scope: String, CaseIterable, Identifiable {
        case user, system, all
        var id: String { rawValue }

        var flag: String { "--\(rawValue)" }
        var label: LocalizedStringResource {
            switch self {
            case .user: .ui("User apps")
            case .system: .ui("System apps")
            case .all: .ui("All")
            }
        }
    }

    func apps(for udid: String) -> [InstalledApp] { appsByDevice[udid] ?? [] }
    func isLoading(_ udid: String) -> Bool { loadingUDIDs.contains(udid) }

    func load(udid: String, scope: Scope = .user) async {
        guard let tool = ToolLocator.shared.url(for: .ideviceInstaller) else {
            errorsByDevice[udid] = ToolError.missing(.ideviceInstaller).localizedDescription
            return
        }

        loadingUDIDs.insert(udid)
        defer { loadingUDIDs.remove(udid) }

        do {
            let attributes = InstalledApp.requestedAttributes.flatMap { ["-a", $0] }
            let result = try await ProcessRunner.run(tool, ["-u", udid, "list", scope.flag, "--xml"] + attributes)
            guard result.succeeded else {
                errorsByDevice[udid] = result.failureMessage
                return
            }
            guard let data = PlistParsing.extractPlistData(from: result.stdout) else {
                // Nessun plist in output significa, di norma, zero app installate.
                appsByDevice[udid] = []
                errorsByDevice[udid] = nil
                return
            }
            let entries = try PlistParsing.dictionaryArray(from: data)
            appsByDevice[udid] = entries
                .map(InstalledApp.init(plist:))
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            errorsByDevice[udid] = nil
        } catch {
            errorsByDevice[udid] = error.localizedDescription
        }
    }

    func forget(udid: String) {
        appsByDevice.removeValue(forKey: udid)
        errorsByDevice.removeValue(forKey: udid)
    }
}
