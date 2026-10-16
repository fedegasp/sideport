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
        var label: LocalizedStringResource {
            self == .search ? .ui("Search") : .ui("My purchases")
        }
    }

    private var apps: [StoreApp] {
        mode == .search ? store.searchResults : store.purchases
    }

    private var purchasesLabel: LocalizedStringResource {
        let loaded = store.purchases.count
        guard loaded > 0 else { return .ui("Apps linked to your Apple ID") }
        if store.purchasesTotal > loaded { return .ui("\(loaded) of \(store.purchasesTotal) apps") }
        return .ui("\(loaded) apps")
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
                    Button(.ui("Sign out")) { Task { await store.signOut() } }
                } label: {
                    Label(.ui("Account"), systemImage: "person.crop.circle")
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
            Picker(.ui("Mode"), selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                if mode == .search {
                    TextField(text: $term, prompt: Text(.ui("Search the App Store"))) {
                        Text(.ui("Search the App Store"))
                    }
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit(runSearch)
                } else {
                    Text(purchasesLabel).foregroundStyle(.secondary)
                    Spacer()
                }

                Picker(.ui("Platform"), selection: $platform) {
                    ForEach(StorePlatform.allCases) { Text(verbatim: $0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                .help(Text(.ui("Filter by device type")))

                if mode == .search {
                    Stepper(.ui("\(limit) results"), value: $limit, in: 1...50, step: 5)
                        .frame(width: 150)
                    Button(.ui("Search"), action: runSearch)
                        .buttonStyle(.borderedProminent)
                        .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty || store.isSearching)
                } else {
                    Button(.ui("Refresh")) {
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
                Text(mode == .search ? .ui("Searching…") : .ui("Reading purchases…"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apps.isEmpty {
            let symbol = mode == .search ? "magnifyingglass" : "bag"
            let title: LocalizedStringResource = mode == .search ? .ui("No results") : .ui("No purchases")
            if let error = store.lastError {
                EmptyStateView(symbol: symbol, title: title, error: error)
            } else {
                EmptyStateView(
                    symbol: symbol,
                    title: title,
                    message: mode == .search
                        ? .ui("Search for an app by name to download its .ipa package.")
                        : .ui("No apps are linked to this Apple ID.")
                )
            }
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
