import Foundation

/// Coda delle installazioni e rimozioni.
///
/// I job vengono serializzati per dispositivo (una sessione `installation_proxy`
/// alla volta) ma eseguiti in parallelo su dispositivi diversi, cosi' da poter
/// distribuire la stessa .ipa su piu' device contemporaneamente.
@MainActor
final class TransferQueue: ObservableObject {
    @Published private(set) var jobs: [TransferJob] = []

    /// Invocato quando un job si conclude con successo, con l'UDID del
    /// dispositivo coinvolto. Serve a ricaricare l'elenco app senza che una
    /// vista debba osservare `jobs` e scriverci dentro per tenerne traccia.
    var onJobSucceeded: ((String) -> Void)?

    private var drainTasks: [String: Task<Void, Never>] = [:]
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    var activeJobs: [TransferJob] { jobs.filter { !$0.status.isFinished } }
    var hasActivity: Bool { !activeJobs.isEmpty }

    // MARK: - Inserimento

    @discardableResult
    func enqueueInstall(_ package: IPAPackage, on device: Device) -> TransferJob {
        let job = TransferJob(kind: .install(package), deviceUDID: device.udid, deviceName: device.displayName)
        enqueue(job)
        return job
    }

    @discardableResult
    func enqueueUninstall(_ app: InstalledApp, on device: Device) -> TransferJob {
        let job = TransferJob(
            kind: .uninstall(bundleIdentifier: app.bundleIdentifier, appName: app.name),
            deviceUDID: device.udid,
            deviceName: device.displayName
        )
        enqueue(job)
        return job
    }

    private func enqueue(_ job: TransferJob) {
        jobs.append(job)
        startDrainIfNeeded(for: job.deviceUDID)
    }

    // MARK: - Esecuzione

    private func startDrainIfNeeded(for udid: String) {
        guard drainTasks[udid] == nil else { return }
        drainTasks[udid] = Task { [weak self] in
            await self?.drain(udid: udid)
            self?.drainTasks[udid] = nil
        }
    }

    private func drain(udid: String) async {
        while let index = jobs.firstIndex(where: { $0.deviceUDID == udid && $0.status == .queued }) {
            let jobID = jobs[index].id
            let task = Task { [weak self] in
                guard let self else { return }
                await self.execute(jobID: jobID)
            }
            activeTasks[jobID] = task
            await task.value
            activeTasks.removeValue(forKey: jobID)
        }
    }

    private func execute(jobID: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let job = jobs[index]

        guard let tool = ToolLocator.shared.url(for: .ideviceInstaller) else {
            update(jobID) { $0.status = .failed(ToolError.missing(.ideviceInstaller).localizedDescription) }
            return
        }

        update(jobID) {
            $0.status = .running(stage: "Preparazione", fraction: nil)
            $0.startedAt = Date()
        }

        let arguments: [String]
        switch job.kind {
        case .install(let package):
            guard FileManager.default.fileExists(atPath: package.url.path) else {
                finish(jobID, with: .failed("Il file \(package.url.lastPathComponent) non esiste piu'."))
                return
            }
            arguments = ["-u", job.deviceUDID, "install", package.url.path]
        case .uninstall(let bundleIdentifier, _):
            arguments = ["-u", job.deviceUDID, "uninstall", bundleIdentifier]
        }

        do {
            let result = try await ProcessRunner.run(
                tool,
                arguments,
                onStdoutLine: { [weak self] line in
                    Task { @MainActor in self?.handleOutput(line, for: jobID) }
                },
                onStderrLine: { [weak self] line in
                    Task { @MainActor in self?.handleOutput(line, for: jobID) }
                }
            )

            if Task.isCancelled {
                finish(jobID, with: .cancelled)
            } else if result.succeeded {
                finish(jobID, with: .succeeded)
            } else {
                finish(jobID, with: .failed(Self.humanize(result.failureMessage)))
            }
        } catch is CancellationError {
            finish(jobID, with: .cancelled)
        } catch {
            finish(jobID, with: .failed(error.localizedDescription))
        }
    }

    private func handleOutput(_ line: String, for jobID: UUID) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        update(jobID) { job in
            job.log.append(trimmed)
            if job.log.count > 200 { job.log.removeFirst(job.log.count - 200) }
            guard !job.status.isFinished else { return }
            if let progress = Self.parseProgress(trimmed) {
                job.status = .running(stage: progress.stage, fraction: progress.fraction)
            } else if trimmed.lowercased().hasPrefix("copying") {
                job.status = .running(stage: "Copia sul dispositivo", fraction: nil)
            }
        }
    }

    /// Righe del tipo ` - ExtractingPackage (15%)`. Interno per i test.
    nonisolated static func parseProgress(_ line: String) -> (stage: String, fraction: Double?)? {
        guard let match = line.range(of: #"([A-Za-z]+)\s*\((\d{1,3})%\)"#, options: .regularExpression) else {
            return nil
        }
        let fragment = String(line[match])
        let stage = fragment.components(separatedBy: " (").first ?? fragment
        let percentText = fragment
            .components(separatedBy: "(").last?
            .replacingOccurrences(of: "%)", with: "") ?? ""
        let fraction = Double(percentText).map { min(max($0 / 100, 0), 1) }
        return (stageLabel(for: stage), fraction)
    }

    nonisolated private static func stageLabel(for stage: String) -> String {
        switch stage {
        case "CreatingStagingDirectory": return "Creazione area di staging"
        case "ExtractingPackage": return "Estrazione pacchetto"
        case "InspectingPackage": return "Analisi pacchetto"
        case "TakingInstallLock": return "Blocco installazione"
        case "PreflightingApplication": return "Verifica preliminare"
        case "InstallingEmbeddedProfile": return "Installazione profilo"
        case "VerifyingApplication": return "Verifica firma"
        case "CreatingContainer": return "Creazione container"
        case "InstallingApplication": return "Installazione"
        case "PostflightingApplication": return "Finalizzazione"
        case "SandboxingApplication": return "Applicazione sandbox"
        case "GeneratingApplicationMap": return "Aggiornamento indice app"
        case "RemovingOldApplication": return "Rimozione versione precedente"
        default: return stage
        }
    }

    /// Traduce gli errori piu' comuni di installation_proxy in indicazioni utili. Interno per i test.
    nonisolated static func humanize(_ message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("applicationverificationfailed") || lowered.contains("mismatchedapplicationidentifierentitlement") {
            return "Firma non valida per questo dispositivo. Una .ipa dell'App Store si installa solo se e' stata acquistata con l'Apple ID configurato sul dispositivo."
        }
        if lowered.contains("devicefamilynotsupported") {
            return "Questa app non supporta il tipo di dispositivo selezionato."
        }
        if lowered.contains("incorrectarchitecture") {
            return "Architettura non compatibile con questo dispositivo."
        }
        if lowered.contains("notentitled") || lowered.contains("missingentitlement") {
            return "L'app richiede entitlement non concessi dal profilo di firma."
        }
        if lowered.contains("could not connect to lockdownd") || lowered.contains("no device found") {
            return "Dispositivo non raggiungibile: verifica il cavo e che sia sbloccato e autorizzato."
        }
        if lowered.contains("passcode") {
            return "Sblocca il dispositivo con il codice e riprova."
        }
        return message
    }

    // MARK: - Controllo

    func cancel(_ job: TransferJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        switch jobs[index].status {
        case .queued:
            finish(job.id, with: .cancelled)
        case .running:
            activeTasks[job.id]?.cancel()
        default:
            break
        }
    }

    func cancelAll() {
        for job in activeJobs { cancel(job) }
    }

    func clearFinished() {
        jobs.removeAll { $0.status.isFinished }
    }

    func retry(_ job: TransferJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index].status = .queued
        jobs[index].log.removeAll()
        jobs[index].startedAt = nil
        jobs[index].finishedAt = nil
        startDrainIfNeeded(for: job.deviceUDID)
    }

    private func finish(_ jobID: UUID, with status: TransferJob.Status) {
        update(jobID) {
            $0.status = status
            $0.finishedAt = Date()
        }
        if status == .succeeded, let job = jobs.first(where: { $0.id == jobID }) {
            onJobSucceeded?(job.deviceUDID)
        }
    }

    private func update(_ jobID: UUID, _ transform: (inout TransferJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        transform(&jobs[index])
    }
}
