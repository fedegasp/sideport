import Foundation

/// Una singola operazione di installazione/rimozione su un dispositivo.
struct TransferJob: Identifiable, Equatable {
    enum Kind: Equatable {
        case install(IPAPackage)
        case uninstall(bundleIdentifier: String, appName: String)

        var title: String {
            switch self {
            case .install(let package): return package.name
            case .uninstall(_, let name): return name
            }
        }
    }

    enum Status: Equatable {
        case queued
        case running(stage: String, fraction: Double?)
        case succeeded
        case failed(String)
        case cancelled

        var isFinished: Bool {
            switch self {
            case .succeeded, .failed, .cancelled: return true
            case .queued, .running: return false
            }
        }

        var isActive: Bool {
            if case .running = self { return true }
            return false
        }
    }

    let id = UUID()
    let kind: Kind
    let deviceUDID: String
    let deviceName: String
    var status: Status = .queued
    var startedAt: Date?
    var finishedAt: Date?
    /// Ultime righe di output del tool, usate per diagnosticare i fallimenti.
    var log: [String] = []

    var title: String { kind.title }

    var subtitle: LocalizedStringResource {
        switch kind {
        case .install: .ui("Install on \(deviceName)")
        case .uninstall: .ui("Remove from \(deviceName)")
        }
    }

    static func == (lhs: TransferJob, rhs: TransferJob) -> Bool { lhs.id == rhs.id }
}
