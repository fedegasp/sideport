import Foundation
import Observation

/// Accesso all'App Store tramite `ipatool`.
///
/// ipatool parla con l'API privata dell'iTunes Store: ricerca, elenco acquisti e
/// download delle .ipa associate a un Apple ID. Le credenziali di sessione le
/// conserva lui nel portachiavi di macOS; questa classe non le memorizza mai.
@MainActor
@Observable
final class StoreService {

    enum AuthState: Equatable {
        case unknown
        case signedOut
        case signingIn
        /// ipatool ha chiesto il codice di verifica: il processo di login resta
        /// vivo in attesa, cosi' non serve una seconda richiesta ad Apple.
        case awaitingAuthCode
        case signedIn(StoreAccount)

        var account: StoreAccount? {
            if case .signedIn(let account) = self { return account }
            return nil
        }

        var isBusy: Bool { self == .signingIn }
    }

    private(set) var authState: AuthState = .unknown
    private(set) var searchResults: [StoreApp] = []
    private(set) var purchases: [StoreApp] = []
    private(set) var downloads: [StoreDownload] = []
    private(set) var isSearching = false
    private(set) var isLoadingPurchases = false
    private(set) var purchasesPage = 1
    private(set) var purchasesTotal = 0
    var lastError: String?

    /// Processo di login vivo mentre attendiamo il codice 2FA.
    @ObservationIgnored private var loginProcess: PTYProcess?
    @ObservationIgnored private var downloadTasks: [UUID: Task<Void, Never>] = [:]

    var isAvailable: Bool { ToolLocator.shared.url(for: .ipatool) != nil }

    /// Download conclusi con successo: quando cambia la libreria va riletta.
    var completedDownloadsCount: Int {
        downloads.count { if case .finished = $0.status { true } else { false } }
    }

    // MARK: - Autenticazione

    /// Legge l'account gia' autenticato, se c'e'.
    func refreshAccount() async {
        guard let tool = ToolLocator.shared.url(for: .ipatool) else {
            authState = .signedOut
            return
        }
        guard let result = try? await ProcessRunner.run(tool, ["auth", "info", "--format", "json", "--non-interactive"]) else {
            authState = .signedOut
            return
        }
        if result.succeeded, let account = Self.parseAccount(from: result.stdout) {
            authState = .signedIn(account)
        } else {
            authState = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        guard let tool = ToolLocator.shared.url(for: .ipatool) else {
            lastError = ToolError.missing(.ipatool).localizedDescription
            return
        }
        guard !email.isEmpty, !password.isEmpty else { return }

        lastError = nil
        authState = .signingIn

        let process = PTYProcess(
            executable: tool,
            arguments: ["auth", "login", "-e", email, "--format", "json"]
        )
        loginProcess = process

        // ipatool scrive i prompt su stderr e non li termina con newline,
        // quindi si accumula il testo e si cercano le frasi chiave.
        let prompts = PromptWatcher()
        process.onStderr = { [weak self] chunk in
            let actions = prompts.consume(chunk)
            Task { @MainActor [weak self] in
                guard let self else { return }
                for action in actions {
                    switch action {
                    case .needsPassword:
                        process.send(password + "\n")
                    case .needsAuthCode:
                        self.authState = .awaitingAuthCode
                    }
                }
            }
        }

        do {
            try process.start()
        } catch {
            loginProcess = nil
            authState = .signedOut
            lastError = error.localizedDescription
            return
        }

        let exitCode = await process.waitUntilExit()
        loginProcess = nil

        if exitCode == 0 {
            await refreshAccount()
            if authState.account == nil {
                // ipatool ha chiuso senza errori ma l'account non risulta.
                authState = .signedOut
                lastError = String.ui("Sign-in failed: ipatool does not report an active account.")
            }
        } else {
            authState = .signedOut
            lastError = Self.errorMessage(
                stdout: process.collectedStdout,
                stderr: process.collectedStderr
            )
        }
    }

    /// Invia il codice 2FA al processo di login in attesa.
    func submitAuthCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let process = loginProcess else { return }
        authState = .signingIn
        process.send(trimmed + "\n")
    }

    func cancelSignIn() {
        loginProcess?.terminate()
        loginProcess = nil
        authState = .signedOut
    }

    func signOut() async {
        guard let tool = ToolLocator.shared.url(for: .ipatool) else { return }
        _ = try? await ProcessRunner.run(tool, ["auth", "revoke", "--format", "json", "--non-interactive"])
        searchResults = []
        purchases = []
        authState = .signedOut
    }

    // MARK: - Ricerca e acquisti

    func search(term: String, limit: Int, platform: StorePlatform) async {
        let query = term.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let tool = ToolLocator.shared.url(for: .ipatool) else { return }

        isSearching = true
        defer { isSearching = false }
        lastError = nil

        do {
            let result = try await ProcessRunner.run(tool, [
                "search", query,
                "-l", String(limit),
                "--platform", platform.rawValue,
                "--format", "json", "--non-interactive"
            ])
            guard result.succeeded else {
                searchResults = []
                lastError = Self.errorMessage(stdout: result.stdout, stderr: result.stderr)
                return
            }
            searchResults = Self.parseApps(from: result.stdout)
            if searchResults.isEmpty {
                lastError = String.ui("No results for \u{201C}\(query)\u{201D}.")
            }
        } catch {
            searchResults = []
            lastError = error.localizedDescription
        }
    }

    /// Carica l'elenco completo degli acquisti, scorrendo le pagine finche'
    /// non si raggiunge il totale dichiarato da ipatool.
    func loadPurchases(platform: StorePlatform?) async {
        guard let tool = ToolLocator.shared.url(for: .ipatool) else { return }

        isLoadingPurchases = true
        defer { isLoadingPurchases = false }
        lastError = nil
        purchases = []
        purchasesTotal = 0

        let pageSize = 100
        let maxPages = 20
        var collected: [StoreApp] = []
        var seen = Set<Int>()

        for page in 1...maxPages {
            var arguments = [
                "list-purchases",
                "-p", String(page),
                "-l", String(pageSize),
                "--format", "json", "--non-interactive"
            ]
            if let platform {
                arguments.append(contentsOf: ["--platform", platform.rawValue])
            }

            let result: CommandResult
            do {
                result = try await ProcessRunner.run(tool, arguments)
            } catch {
                lastError = error.localizedDescription
                return
            }
            guard result.succeeded else {
                // Le pagine gia' lette restano visibili: meglio un elenco
                // parziale che nessun elenco.
                lastError = Self.errorMessage(stdout: result.stdout, stderr: result.stderr)
                return
            }

            let batch = Self.parseApps(from: result.stdout)
            if let total = Self.parseInt(key: "totalCount", from: result.stdout) {
                purchasesTotal = total
            }
            let fresh = batch.filter { seen.insert($0.trackId).inserted }
            collected.append(contentsOf: fresh)
            purchases = collected
            purchasesPage = page

            // Fine elenco: pagina vuota, nessuna novita', o totale raggiunto.
            if batch.isEmpty || fresh.isEmpty { break }
            if purchasesTotal > 0 && collected.count >= purchasesTotal { break }
        }

        if purchasesTotal == 0 { purchasesTotal = purchases.count }
    }

    // MARK: - Download

    /// Scarica l'app nella cartella indicata. `acquireLicense` aggiunge `--purchase`,
    /// che ottiene la licenza gratuita quando l'app non risulta ancora acquisita.
    func download(_ app: StoreApp, to directory: URL, platform: StorePlatform, acquireLicense: Bool) {
        guard let tool = ToolLocator.shared.url(for: .ipatool) else {
            lastError = ToolError.missing(.ipatool).localizedDescription
            return
        }
        guard !downloads.contains(where: { $0.app.id == app.id && !$0.status.isFinished }) else { return }

        let destination = directory.appendingPathComponent(app.suggestedFileName)
        var job = StoreDownload(app: app, destination: destination)
        job.status = .running(bytes: 0, fraction: nil)
        downloads.append(job)
        let jobID = job.id

        var arguments = [
            "download",
            "-b", app.bundleId,
            "-o", destination.path,
            "--platform", platform.rawValue,
            "--format", "json", "--non-interactive"
        ]
        if acquireLicense { arguments.append("--purchase") }

        downloadTasks[jobID] = Task { [weak self] in
            guard let self else { return }
            // ipatool non espone un avanzamento affidabile: si osserva la
            // percentuale su stderr quando c'e', altrimenti i byte sul file.
            let progressWatcher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard let size = try? FileManager.default
                        .attributesOfItem(atPath: destination.path)[.size] as? NSNumber else { continue }
                    self?.updateDownloadBytes(jobID, bytes: size.int64Value)
                }
            }
            defer { progressWatcher.cancel() }

            do {
                let result = try await ProcessRunner.run(
                    tool,
                    arguments,
                    onStderrLine: { [weak self] line in
                        guard let fraction = Self.parsePercentage(line) else { return }
                        Task { @MainActor in self?.updateDownloadFraction(jobID, fraction: fraction) }
                    }
                )
                if Task.isCancelled {
                    self.finishDownload(jobID, status: .cancelled)
                    try? FileManager.default.removeItem(at: destination)
                } else if result.succeeded {
                    let output = Self.parseString(key: "output", from: result.stdout)
                    let finalURL = output.map { URL(fileURLWithPath: $0) } ?? destination
                    self.finishDownload(jobID, status: .finished(finalURL))
                } else {
                    self.finishDownload(jobID, status: .failed(
                        Self.errorMessage(stdout: result.stdout, stderr: result.stderr)
                    ))
                    try? FileManager.default.removeItem(at: destination)
                }
            } catch {
                self.finishDownload(jobID, status: .failed(error.localizedDescription))
            }
            self.downloadTasks.removeValue(forKey: jobID)
        }
    }

    func cancelDownload(_ job: StoreDownload) {
        downloadTasks[job.id]?.cancel()
    }

    func clearFinishedDownloads() {
        downloads.removeAll { $0.status.isFinished }
    }

    private func updateDownloadBytes(_ id: UUID, bytes: Int64) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        guard case .running(_, let fraction) = downloads[index].status else { return }
        downloads[index].status = .running(bytes: bytes, fraction: fraction)
    }

    private func updateDownloadFraction(_ id: UUID, fraction: Double) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        guard case .running(let bytes, _) = downloads[index].status else { return }
        downloads[index].status = .running(bytes: bytes, fraction: fraction)
    }

    private func finishDownload(_ id: UUID, status: StoreDownload.Status) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].status = status
        downloads[index].finishedAt = Date()
    }

    // MARK: - Parsing dell'output di ipatool

    /// ipatool emette una riga JSON per ogni evento di log piu' il risultato:
    /// si cerca l'oggetto che contiene la chiave attesa.
    nonisolated private static func jsonObjects(in output: String) -> [[String: Any]] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                guard let data = line.trimmingCharacters(in: .whitespaces).data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
    }

    /// Decodifica una voce alla volta: se ipatool restituisce un elemento
    /// inatteso si perde quello, non l'intero elenco.
    nonisolated static func parseApps(from output: String) -> [StoreApp] {
        for object in jsonObjects(in: output) {
            guard let apps = object["apps"] as? [[String: Any]] else { continue }
            let decoder = JSONDecoder()
            return apps.compactMap { element in
                guard let data = try? JSONSerialization.data(withJSONObject: element) else { return nil }
                return try? decoder.decode(StoreApp.self, from: data)
            }
        }
        return []
    }

    nonisolated static func parseAccount(from output: String) -> StoreAccount? {
        for object in jsonObjects(in: output) {
            // Forma attesa: {"account":{"email":...,"name":...}}; alcune versioni
            // mettono i campi direttamente nell'oggetto radice.
            if let account = object["account"] as? [String: Any],
               let email = account.string("email") {
                return StoreAccount(email: email, name: account.string("name"))
            }
            if let email = object.string("email") {
                return StoreAccount(email: email, name: object.string("name"))
            }
        }
        return nil
    }

    nonisolated static func parseString(key: String, from output: String) -> String? {
        jsonObjects(in: output).compactMap { $0.string(key) }.last
    }

    nonisolated static func parseInt(key: String, from output: String) -> Int? {
        jsonObjects(in: output).compactMap { $0.int(key) }.last
    }

    /// Estrae il messaggio d'errore dalle righe di log di ipatool.
    nonisolated static func errorMessage(stdout: String, stderr: String) -> String {
        let reported = jsonObjects(in: stdout + "\n" + stderr)
            .compactMap { $0.string("error") }
            .last
        guard let reported else {
            let fallback = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? String.ui("ipatool exited with an error.") : fallback
        }
        return humanize(reported)
    }

    /// Errori ricorrenti di ipatool. Il riconoscimento e' separato dal testo
    /// mostrato: quello cambia con la lingua, i messaggi del tool no.
    enum Failure {
        case noAccount
        case missingLicense
        case wrongCredentials
        case invalidAuthCode
        case rateLimited

        var message: String {
            switch self {
            case .noAccount:
                String.ui("No authenticated account: sign in with your Apple ID.")
            case .missingLicense:
                String.ui("No license for this app. If it is free use \u{201C}Get and download\u{201D}; if it is paid, buy it from the App Store with this Apple ID.")
            case .wrongCredentials:
                String.ui("Incorrect Apple ID or password.")
            case .invalidAuthCode:
                String.ui("Invalid or expired verification code.")
            case .rateLimited:
                String.ui("Too many attempts: Apple has temporarily blocked requests. Try again later.")
            }
        }
    }

    /// Interno per i test.
    nonisolated static func failure(in message: String) -> Failure? {
        let lowered = message.lowercased()
        if lowered.contains("could not be found in the keyring") || lowered.contains("failed to get account") {
            return .noAccount
        }
        if lowered.contains("license") {
            return .missingLicense
        }
        if lowered.contains("password") && lowered.contains("incorrect") {
            return .wrongCredentials
        }
        if lowered.contains("2fa") || lowered.contains("verification code") {
            return .invalidAuthCode
        }
        if lowered.contains("too many") || lowered.contains("rate") {
            return .rateLimited
        }
        return nil
    }

    nonisolated static func humanize(_ message: String) -> String {
        failure(in: message)?.message ?? message
    }

    /// Percentuali eventualmente stampate dalla barra di avanzamento.
    nonisolated static func parsePercentage(_ line: String) -> Double? {
        guard let match = line.range(of: #"(\d{1,3})\s*%"#, options: .regularExpression) else { return nil }
        let digits = line[match].filter(\.isNumber)
        guard let value = Double(digits) else { return nil }
        return min(max(value / 100, 0), 1)
    }
}
