import Foundation

enum ProcessError: LocalizedError {
    case launchFailed(String)
    case commandFailed(tool: String, result: CommandResult)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            "Impossibile avviare il processo: \(message)"
        case .commandFailed(let tool, let result):
            "\(tool): \(result.failureMessage)"
        }
    }
}
