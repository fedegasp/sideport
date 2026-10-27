import Foundation

struct StoreDownload: Identifiable {
    enum Status: Equatable {
        case running(bytes: Int64, fraction: Double?)
        case finished(URL)
        case failed(String)
        case cancelled

        var isFinished: Bool {
            if case .running = self { return false }
            return true
        }
    }

    let id = UUID()
    let app: StoreApp
    let destination: URL
    var status: Status = .running(bytes: 0, fraction: nil)
    var finishedAt: Date?
}
