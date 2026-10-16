import Foundation

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }

    /// Messaggio d'errore piu' utile disponibile: stderr se presente, altrimenti stdout.
    var failureMessage: String {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { return err }
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return out }
        return "Il comando e' terminato con codice \(exitCode)."
    }
}
