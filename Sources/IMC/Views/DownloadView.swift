import SwiftUI

/// Ricerca e download delle .ipa dall'App Store tramite ipatool.
struct DownloadView: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        Group {
            if !store.isAvailable {
                StoreUnavailableView()
            } else {
                switch store.authState {
                case .unknown:
                    ProgressView("Verifica dell'account…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .signedOut, .signingIn, .awaitingAuthCode:
                    SignInView()
                case .signedIn:
                    StoreBrowserView()
                }
            }
        }
        .navigationTitle("Download")
        .navigationSubtitle(store.authState.account?.email ?? "")
        .task {
            if store.authState == .unknown { await store.refreshAccount() }
        }
        .onChange(of: store.downloads.filter { if case .finished = $0.status { return true } else { return false } }.count) {
            Task { await library.refresh() }
        }
    }
}

// MARK: - ipatool mancante

private struct StoreUnavailableView: View {
    private let command = "brew install ipatool"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("ipatool non trovato")
                .font(.title3.weight(.semibold))
            Text("Il download dall'App Store usa ipatool. Installalo e riapri IMC, oppure ricompila l'app: lo script di build lo incorpora nel bundle quando e' presente.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copia il comando")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Accesso

private struct SignInView: View {
    @EnvironmentObject private var store: StoreService

    @State private var email = ""
    @State private var password = ""
    @State private var authCode = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password, code }

    private var awaitingCode: Bool { store.authState == .awaitingAuthCode }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                    Text("Accedi all'App Store")
                        .font(.title3.weight(.semibold))
                    Text("Servono le credenziali dell'Apple ID con cui hai ottenuto le app: si possono scaricare solo app gratuite o gia' acquistate da quell'account.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }

                VStack(spacing: 10) {
                    TextField("Apple ID", text: $email)
                        .textContentType(.username)
                        .focused($focus, equals: .email)
                        .disabled(awaitingCode || store.authState.isBusy)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .disabled(awaitingCode || store.authState.isBusy)
                        .onSubmit(submit)

                    if awaitingCode {
                        VStack(alignment: .leading, spacing: 6) {
                            Divider()
                            Text("Apple ha inviato un codice di verifica ai tuoi dispositivi.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Codice a 6 cifre", text: $authCode)
                                .focused($focus, equals: .code)
                                .onSubmit { store.submitAuthCode(authCode) }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)

                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }

                HStack(spacing: 10) {
                    if store.authState.isBusy || awaitingCode {
                        Button("Annulla") { store.cancelSignIn() }
                    }
                    if awaitingCode {
                        Button("Verifica") { store.submitAuthCode(authCode) }
                            .buttonStyle(.borderedProminent)
                            .disabled(authCode.trimmingCharacters(in: .whitespaces).count < 4)
                    } else {
                        Button {
                            submit()
                        } label: {
                            if store.authState.isBusy {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Accesso…")
                                }
                            } else {
                                Text("Accedi")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || password.isEmpty || store.authState.isBusy)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("La password viene passata a ipatool attraverso uno pseudo-terminale, non sulla riga di comando: non compare in `ps` e IMC non la salva da nessuna parte.", systemImage: "lock")
                        Label("Il token di sessione lo gestisce ipatool nel portachiavi di macOS. Alla prima richiesta macOS puo' chiedere l'autorizzazione di accesso.", systemImage: "key")
                        Label("Il download usa un'API privata di Apple, la stessa di iTunes: puo' cambiare senza preavviso.", systemImage: "info.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                }
                .frame(maxWidth: 480)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { focus = .email }
        .onChange(of: awaitingCode) { _, isAwaiting in
            if isAwaiting { focus = .code }
        }
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task {
            await store.signIn(email: email, password: password)
            if store.authState.account != nil {
                password = ""
                authCode = ""
            }
        }
    }
}

// MARK: - Ricerca e acquisti

private struct StoreBrowserView: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState

    @State private var mode: Mode = .search
    @State private var term = ""
    @State private var limit = 10
    @State private var platform: StorePlatform = .iphone

    private enum Mode: String, CaseIterable, Identifiable {
        case search, purchases
        var id: String { rawValue }
        var label: String { self == .search ? "Cerca" : "I miei acquisti" }
    }

    private var apps: [StoreApp] {
        mode == .search ? store.searchResults : store.purchases
    }

    private var purchasesLabel: String {
        let loaded = store.purchases.count
        guard loaded > 0 else { return "App associate al tuo Apple ID" }
        if store.purchasesTotal > loaded { return "\(loaded) di \(store.purchasesTotal) app" }
        return "\(loaded) app"
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            list
            if !store.downloads.isEmpty {
                Divider()
                DownloadsPanel()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let account = store.authState.account {
                        Text(account.displayName)
                    }
                    Divider()
                    Button("Esci dall'account") { Task { await store.signOut() } }
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
        }
        .task(id: mode) {
            if mode == .purchases && store.purchases.isEmpty {
                await store.loadPurchases(platform: platform)
            }
        }
        .onChange(of: platform) { _, newValue in
            // Il filtro piattaforma viene applicato da ipatool lato server:
            // cambiarlo richiede di rileggere l'elenco.
            guard mode == .purchases else { return }
            Task { await store.loadPurchases(platform: newValue) }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                if mode == .search {
                    TextField("Cerca nell'App Store", text: $term)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(runSearch)
                } else {
                    Text(purchasesLabel).foregroundStyle(.secondary)
                    Spacer()
                }

                Picker("Piattaforma", selection: $platform) {
                    ForEach(StorePlatform.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                .help("Filtra per tipo di dispositivo")

                if mode == .search {
                    Stepper("\(limit) risultati", value: $limit, in: 1...50, step: 5)
                        .frame(width: 150)
                    Button("Cerca", action: runSearch)
                        .buttonStyle(.borderedProminent)
                        .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty || store.isSearching)
                } else {
                    Button("Aggiorna") {
                        Task { await store.loadPurchases(platform: platform) }
                    }
                    .disabled(store.isLoadingPurchases)
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var list: some View {
        if store.isSearching || store.isLoadingPurchases {
            VStack(spacing: 8) {
                ProgressView()
                Text(mode == .search ? "Ricerca in corso…" : "Lettura acquisti…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apps.isEmpty {
            EmptyStateView(
                symbol: mode == .search ? "magnifyingglass" : "bag",
                title: mode == .search ? "Nessun risultato" : "Nessun acquisto",
                message: store.lastError ?? (mode == .search
                    ? "Cerca un'app per nome per scaricarne il pacchetto .ipa."
                    : "Non risultano app associate a questo Apple ID.")
            )
        } else {
            List {
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                ForEach(apps) { app in
                    StoreAppRow(app: app, platform: platform) { acquireLicense in
                        store.download(app, to: library.libraryURL, platform: platform, acquireLicense: acquireLicense)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func runSearch() {
        let query = term
        Task { await store.search(term: query, limit: limit, platform: platform) }
    }
}

private struct StoreAppRow: View {
    let app: StoreApp
    let platform: StorePlatform
    let onDownload: (Bool) -> Void

    @EnvironmentObject private var store: StoreService

    private var isDownloading: Bool {
        store.downloads.contains { $0.app.id == app.id && !$0.status.isFinished }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.trackName).lineLimit(1)
                HStack(spacing: 6) {
                    Text(app.bundleId)
                    Text("·")
                    Text("v\(app.version)")
                    if let purchased = app.purchaseDateLabel {
                        Text("·")
                        Text("acquistata il \(purchased)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(app.priceLabel)
                .font(.callout)
                .foregroundStyle(.secondary)

            if isDownloading {
                ProgressView().controlSize(.small)
            } else if app.isOwned {
                Button("Scarica") { onDownload(false) }
                    .buttonStyle(.bordered)
            } else if app.isFree {
                Button("Ottieni e scarica") { onDownload(true) }
                    .buttonStyle(.bordered)
                    .help("Acquisisce la licenza gratuita sul tuo account, poi scarica il pacchetto")
            } else {
                // La ricerca non riporta la data d'acquisto, quindi non si puo'
                // sapere se l'app e' gia' posseduta: si tenta e, se la licenza
                // manca, ipatool lo dice.
                Button("Scarica") { onDownload(false) }
                    .buttonStyle(.bordered)
                    .help("App a pagamento: si scarica solo se gia' acquistata con questo Apple ID, altrimenti va comprata dall'App Store")
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Pannello download

private struct DownloadsPanel: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Download").font(.headline)
                Spacer()
                Button("Pulisci") { store.clearFinishedDownloads() }
                    .buttonStyle(.link)
                    .disabled(store.downloads.allSatisfy { !$0.status.isFinished })
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.downloads) { job in
                        DownloadRow(job: job)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 170)
        }
        .background(.bar)
    }
}

private struct DownloadRow: View {
    let job: StoreDownload

    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.app.trackName).lineLimit(1)
                switch job.status {
                case .running(let bytes, let fraction):
                    if let fraction {
                        ProgressView(value: fraction).frame(maxWidth: 260)
                    } else {
                        ProgressView().progressViewStyle(.linear).frame(maxWidth: 260)
                    }
                    Text(bytes > 0 ? "Scaricati \(Format.bytes(bytes))" : "Avvio del download…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished(let url):
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                case .cancelled:
                    Text("Annullato").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            switch job.status {
            case .running:
                Button("Annulla") { store.cancelDownload(job) }
                    .buttonStyle(.link)
            case .finished(let url):
                if let package = library.packages.first(where: { $0.url == url }) {
                    Button("Installa su…") { ui.installSheet = .init(packages: [package]) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .failed, .cancelled:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
