import Foundation
import Observation

/// Coda delle installazioni e rimozioni.
///
/// I job vengono serializzati per dispositivo (una sessione `installation_proxy`
/// alla volta) ma eseguiti in parallelo su dispositivi diversi, cosi' da poter
/// distribuire la stessa .ipa su piu' device contemporaneamente.
@MainActor
@Observable
final class TransferQueue {
    private(set) var jobs: [TransferJob] = []

    /// Invocato quando un job si conclude con successo, con l'UDID del
    /// dispositivo coinvolto. Serve a ricaricare l'elenco app senza che una
    /// vista debba osservare `jobs` e scriverci dentro per tenerne traccia.
    @ObservationIgnored var onJobSucceeded: ((String) -> Void)?

    @ObservationIgnored private var drainTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeTasks: [UUID: Task<Void, Never>] = [:]

    var activeJobs: [TransferJob] { jobs.filter { !$0.status.isFinished } }
    var hasActivity: Bool { !activeJobs.isEmpty }

    // MARK: - Inserimento

    @discardableResult
    func enqueueInstall(_ package: IPAPackage, on device: Device) -> TransferJob {
        let job = TransferJob(
            kind: .install(package),
            deviceUDID: device.udid,
            deviceName: device.displayName,
            deviceTransport: device.transport
        )
        enqueue(job)
        return job
    }

    @discardableResult
    func enqueueUninstall(_ app: InstalledApp, on device: Device) -> TransferJob {
        let job = TransferJob(
            kind: .uninstall(bundleIdentifier: app.bundleIdentifier, appName: app.name),
            deviceUDID: device.udid,
            deviceName: device.displayName,
            deviceTransport: device.transport
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
            $0.status = .running(stage: String.ui("Preparing"), fraction: nil)
            $0.startedAt = Date()
        }

        let lookup = job.deviceTransport.toolArguments
        let arguments: [String]
        switch job.kind {
        case .install(let package):
            guard FileManager.default.fileExists(atPath: package.url.path) else {
                finish(jobID, with: .failed(String.ui("The file \(package.url.lastPathComponent) no longer exists.")))
                return
            }
            arguments = lookup + ["-u", job.deviceUDID, "install", package.url.path]
        case .uninstall(let bundleIdentifier, _):
            arguments = lookup + ["-u", job.deviceUDID, "uninstall", bundleIdentifier]
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
                job.status = .running(stage: Self.stageLabel(for: progress.stage), fraction: progress.fraction)
            } else if trimmed.lowercased().hasPrefix("copying") {
                job.status = .running(stage: String.ui("Copying to device"), fraction: nil)
            }
        }
    }

    /// Righe del tipo ` - ExtractingPackage (15%)`, con la fase come la
    /// chiama `installation_proxy`. Interno per i test.
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
        return (stage, fraction)
    }

    /// Le fasi sconosciute restano con il nome del tool: e' meglio di niente
    /// quando Apple ne aggiunge una.
    nonisolated static func stageLabel(for stage: String) -> String {
        switch stage {
        case "CreatingStagingDirectory": return String.ui("Creating staging area")
        case "ExtractingPackage": return String.ui("Extracting package")
        case "InspectingPackage": return String.ui("Inspecting package")
        case "TakingInstallLock": return String.ui("Taking install lock")
        case "PreflightingApplication": return String.ui("Preflight check")
        case "InstallingEmbeddedProfile": return String.ui("Installing profile")
        case "VerifyingApplication": return String.ui("Verifying signature")
        case "CreatingContainer": return String.ui("Creating container")
        case "InstallingApplication": return String.ui("Installing")
        case "PostflightingApplication": return String.ui("Finalizing")
        case "SandboxingApplication": return String.ui("Sandboxing app")
        case "GeneratingApplicationMap": return String.ui("Updating app index")
        case "RemovingOldApplication": return String.ui("Removing previous version")
        default: return stage
        }
    }

    /// Errori ricorrenti di `installation_proxy`. Il riconoscimento e' separato
    /// dal testo mostrato: quello cambia con la lingua, i messaggi del tool no.
    enum Failure {
        case invalidSignature
        case unsupportedDeviceFamily
        case incompatibleArchitecture
        case missingEntitlements
        case unreachableDevice
        case lockedDevice

        var message: String {
            switch self {
            case .invalidSignature:
                String.ui("Invalid signature for this device. An App Store .ipa installs only if it was purchased with the Apple ID configured on the device.")
            case .unsupportedDeviceFamily:
                String.ui("This app does not support the selected device type.")
            case .incompatibleArchitecture:
                String.ui("Architecture not compatible with this device.")
            case .missingEntitlements:
                String.ui("The app requires entitlements the signing profile does not grant.")
            case .unreachableDevice:
                String.ui("Device unreachable: check the cable or the network, and that it is unlocked and trusted.")
            case .lockedDevice:
                String.ui("Unlock the device with its passcode and try again.")
            }
        }
    }

    /// Interno per i test.
    nonisolated static func failure(in message: String) -> Failure? {
        let lowered = message.lowercased()
        if lowered.contains("applicationverificationfailed") || lowered.contains("mismatchedapplicationidentifierentitlement") {
            return .invalidSignature
        }
        if lowered.contains("devicefamilynotsupported") {
            return .unsupportedDeviceFamily
        }
        if lowered.contains("incorrectarchitecture") {
            return .incompatibleArchitecture
        }
        if lowered.contains("notentitled") || lowered.contains("missingentitlement") {
            return .missingEntitlements
        }
        if lowered.contains("could not connect to lockdownd") || lowered.contains("no device found") {
            return .unreachableDevice
        }
        if lowered.contains("passcode") {
            return .lockedDevice
        }
        return nil
    }

    /// Traduce gli errori piu' comuni di installation_proxy in indicazioni utili.
    nonisolated static func humanize(_ message: String) -> String {
        failure(in: message)?.message ?? message
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
