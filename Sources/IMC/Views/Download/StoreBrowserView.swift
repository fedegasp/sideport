import SwiftUI

struct StoreBrowserView: View {
    @Environment(StoreService.self) private var store
    @Environment(LibraryStore.self) private var library

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
            Picker("Modalita'", selection: $mode) {
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
