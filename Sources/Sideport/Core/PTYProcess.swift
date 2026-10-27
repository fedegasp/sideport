import Foundation
import Darwin

/// Processo con lo standard input collegato a uno pseudo-terminale.
///
/// Serve per `ipatool auth login`: la password viene letta con `term.ReadPassword`,
/// che pretende un vero terminale e rifiuta una pipe. Collegare solo stdin alla pty
/// (lasciando stdout e stderr su pipe normali) soddisfa quel controllo e permette di
/// scrivere la password nel processo invece di passarla in `argv`, dove sarebbe
/// visibile a chiunque esegua `ps`.
final class PTYProcess: @unchecked Sendable {
    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private var master: Int32 = -1
    private var slave: Int32 = -1
    private let lock = NSLock()
    private var stdoutText = ""
    private var stderrText = ""
    private var exitContinuation: CheckedContinuation<Int32, Never>?

    /// Invocati con i blocchi di testo via via che arrivano, su coda arbitraria.
    var onStdout: (@Sendable (String) -> Void)?
    var onStderr: (@Sendable (String) -> Void)?

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
    }

    var collectedStdout: String { lock.withLock { stdoutText } }
    var collectedStderr: String { lock.withLock { stderrText } }
    var isRunning: Bool { process.isRunning }

    func start() throws {
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw ProcessError.launchFailed(String.ui("cannot create the pseudo-terminal"))
        }

        process.standardInput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, toStdout: true)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, toStdout: false)
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.outPipe.fileHandleForReading.readabilityHandler = nil
            self.errPipe.fileHandleForReading.readabilityHandler = nil
            self.append(self.outPipe.fileHandleForReading.readDataToEndOfFile(), toStdout: true)
            self.append(self.errPipe.fileHandleForReading.readDataToEndOfFile(), toStdout: false)
            self.closeDescriptors()
            let continuation = self.lock.withLock { () -> CheckedContinuation<Int32, Never>? in
                defer { self.exitContinuation = nil }
                return self.exitContinuation
            }
            continuation?.resume(returning: proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            closeDescriptors()
            throw ProcessError.launchFailed(error.localizedDescription)
        }
        // Il lato slave resta aperto nel figlio: chiuderlo qui evita che la pty
        // rimanga aperta all'uscita del processo.
        close(slave)
        slave = -1
    }

    /// Scrive nel terminale del processo (es. la password seguita da newline).
    func send(_ text: String) {
        lock.lock()
        let fd = master
        lock.unlock()
        guard fd >= 0, let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let n = write(fd, base.advanced(by: written), buffer.count - written)
                if n <= 0 { break }
                written += n
            }
        }
    }

    func waitUntilExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if !process.isRunning {
                lock.unlock()
                continuation.resume(returning: process.terminationStatus)
            } else {
                exitContinuation = continuation
                lock.unlock()
            }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    private func append(_ data: Data, toStdout: Bool) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        if toStdout { stdoutText += text } else { stderrText += text }
        lock.unlock()
        if toStdout { onStdout?(text) } else { onStderr?(text) }
    }

    private func closeDescriptors() {
        lock.lock()
        if master >= 0 { close(master); master = -1 }
        if slave >= 0 { close(slave); slave = -1 }
        lock.unlock()
    }
}
