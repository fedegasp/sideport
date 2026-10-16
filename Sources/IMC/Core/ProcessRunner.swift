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

enum ProcessError: LocalizedError {
    case launchFailed(String)
    case commandFailed(tool: String, result: CommandResult)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Impossibile avviare il processo: \(message)"
        case .commandFailed(let tool, let result):
            return "\(tool): \(result.failureMessage)"
        }
    }
}

/// Esecuzione di tool a riga di comando con streaming riga per riga.
///
/// `ideviceinstaller` emette l'avanzamento usando sia `\n` sia `\r`, quindi lo
/// splitting delle righe tratta entrambi come terminatori.
enum ProcessRunner {

    static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]? = nil,
        onStdoutLine: ((String) -> Void)? = nil,
        onStderrLine: ((String) -> Void)? = nil
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

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int32, Data, String), Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
                        return
                    }
                    // Legge prima stdout: gli archivi possono superare la capacita' della pipe.
                    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: (
                        process.terminationStatus,
                        out,
                        String(data: err, encoding: .utf8) ?? ""
                    ))
                }
            }
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
        onStdoutLine: ((String) -> Void)? = nil,
        onStderrLine: ((String) -> Void)? = nil
    ) async throws -> CommandResult {
        let result = try await run(executable, arguments, onStdoutLine: onStdoutLine, onStderrLine: onStderrLine)
        guard result.succeeded else {
            throw ProcessError.commandFailed(tool: toolName ?? executable.lastPathComponent, result: result)
        }
        return result
    }
}

/// Accumula l'output e lo consegna riga per riga. `readabilityHandler` viene
/// invocato su una coda interna di Foundation, quindi lo stato e' protetto da lock.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var stdoutAll = ""
    private var stderrAll = ""
    private let onStdoutLine: ((String) -> Void)?
    private let onStderrLine: ((String) -> Void)?

    init(onStdoutLine: ((String) -> Void)?, onStderrLine: ((String) -> Void)?) {
        self.onStdoutLine = onStdoutLine
        self.onStderrLine = onStderrLine
    }

    var stdoutText: String { lock.withLock { stdoutAll } }
    var stderrText: String { lock.withLock { stderrAll } }

    func appendStdout(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        let lines: [String] = lock.withLock {
            stdoutAll += text
            stdoutBuffer += text
            return Self.drainLines(from: &stdoutBuffer)
        }
        lines.forEach { onStdoutLine?($0) }
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        let lines: [String] = lock.withLock {
            stderrAll += text
            stderrBuffer += text
            return Self.drainLines(from: &stderrBuffer)
        }
        lines.forEach { onStderrLine?($0) }
    }

    /// Consegna le righe residue prive di terminatore.
    func flush() {
        let (out, err): (String, String) = lock.withLock {
            let o = stdoutBuffer, e = stderrBuffer
            stdoutBuffer = ""
            stderrBuffer = ""
            return (o, e)
        }
        if !out.trimmingCharacters(in: .whitespaces).isEmpty { onStdoutLine?(out) }
        if !err.trimmingCharacters(in: .whitespaces).isEmpty { onStderrLine?(err) }
    }

    private static func drainLines(from buffer: inout String) -> [String] {
        var lines: [String] = []
        while let index = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(buffer[buffer.startIndex..<index])
            buffer = String(buffer[buffer.index(after: index)...])
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
