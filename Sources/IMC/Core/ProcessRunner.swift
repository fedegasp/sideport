import Foundation

/// Esecuzione di tool a riga di comando con streaming riga per riga.
///
/// `ideviceinstaller` emette l'avanzamento usando sia `\n` sia `\r`, quindi lo
/// splitting delle righe tratta entrambi come terminatori.
enum ProcessRunner {

    static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]? = nil,
        onStdoutLine: (@Sendable (String) -> Void)? = nil,
        onStderrLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = OutputCollector(onStdoutLine: onStdoutLine, onStderrLine: onStderrLine)

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStdout(data)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStderr(data)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
                process.terminationHandler = { proc in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    // Drena quanto rimasto nei buffer dopo l'uscita del processo.
                    collector.appendStdout(outPipe.fileHandleForReading.readDataToEndOfFile())
                    collector.appendStderr(errPipe.fileHandleForReading.readDataToEndOfFile())
                    collector.flush()
                    continuation.resume(returning: CommandResult(
                        exitCode: proc.terminationStatus,
                        stdout: collector.stdoutText,
                        stderr: collector.stderrText
                    ))
                }
                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    process.terminationHandler = nil
                    continuation.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Variante che cattura stdout come dati grezzi: serve per i plist binari e
    /// le immagini estratte dagli archivi .ipa, che una decodifica UTF-8 corromperebbe.
    static func runData(
        _ executable: URL,
        _ arguments: [String]
    ) async throws -> (exitCode: Int32, stdout: Data, stderr: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Le letture fino a EOF sono bloccanti: girano in un task staccato per
        // non occupare l'executor del chiamante. L'annullamento termina il
        // processo, che chiude le pipe e sblocca le letture.
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                do {
                    try process.run()
                } catch {
                    throw ProcessError.launchFailed(error.localizedDescription)
                }
                // Legge prima stdout: gli archivi possono superare la capacita' della pipe.
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, out, String(data: err, encoding: .utf8) ?? "")
            }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Variante che lancia un errore se il comando esce con codice diverso da zero.
    @discardableResult
    static func runChecked(
        _ executable: URL,
        _ arguments: [String],
        toolName: String? = nil,
        onStdoutLine: (@Sendable (String) -> Void)? = nil,
        onStderrLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> CommandResult {
        let result = try await run(executable, arguments, onStdoutLine: onStdoutLine, onStderrLine: onStderrLine)
        guard result.succeeded else {
            throw ProcessError.commandFailed(tool: toolName ?? executable.lastPathComponent, result: result)
        }
        return result
    }
}
