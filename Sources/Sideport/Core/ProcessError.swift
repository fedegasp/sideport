import Foundation

enum ProcessError: LocalizedError {
    case launchFailed(String)
    case commandFailed(tool: String, result: CommandResult)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            String.ui("Cannot start the process: \(message)")
        case .commandFailed(let tool, let result):
            String.ui("\(tool): \(result.failureMessage)")
        }
    }
}
