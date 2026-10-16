import Foundation

/// Accumula l'output e lo consegna riga per riga. `readabilityHandler` viene
/// invocato su una coda interna di Foundation e serve un accesso sincrono,
/// quindi lo stato e' protetto da lock invece che da un actor.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var stdoutAll = ""
    private var stderrAll = ""
    private let onStdoutLine: (@Sendable (String) -> Void)?
    private let onStderrLine: (@Sendable (String) -> Void)?

    init(onStdoutLine: (@Sendable (String) -> Void)?, onStderrLine: (@Sendable (String) -> Void)?) {
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

    /// `ideviceinstaller` emette l'avanzamento usando sia `\n` sia `\r`.
    /// `isNewline` copre anche `\r\n`, che in Swift e' un unico `Character`.
    static func drainLines(from buffer: inout String) -> [String] {
        var lines: [String] = []
        while let index = buffer.firstIndex(where: \.isNewline) {
            let line = String(buffer[buffer.startIndex..<index])
            buffer = String(buffer[buffer.index(after: index)...])
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
