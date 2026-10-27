import Foundation

/// Riconosce i prompt interattivi di ipatool nel flusso di stderr.
///
/// I prompt non terminano con newline, quindi il testo va accumulato e ogni
/// richiesta va riconosciuta una sola volta.
final class PromptWatcher: @unchecked Sendable {
    enum Action {
        case needsPassword
        case needsAuthCode
    }

    private let lock = NSLock()
    private var buffer = ""
    private var passwordRequested = false
    private var codeRequested = false

    func consume(_ chunk: String) -> [Action] {
        lock.lock()
        defer { lock.unlock() }
        buffer += chunk.lowercased()
        var actions: [Action] = []
        if !passwordRequested, buffer.contains("enter password") {
            passwordRequested = true
            actions.append(.needsPassword)
        }
        if !codeRequested, buffer.contains("2fa code") || buffer.contains("verification code") {
            codeRequested = true
            actions.append(.needsAuthCode)
        }
        return actions
    }
}
