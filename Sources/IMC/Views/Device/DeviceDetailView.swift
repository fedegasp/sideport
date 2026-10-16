import SwiftUI

struct DeviceDetailView: View {
    let device: Device

    @Environment(DeviceMonitor.self) private var devices
    @Environment(InstalledAppsService.self) private var installedApps
    @Environment(AppIconStore.self) private var appIcons
    @Environment(LibraryStore.self) private var library
    @Environment(TransferQueue.self) private var queue
    @Environment(UIState.self) private var ui

    @State private var tab: Tab = .apps
    @State private var appSearch = ""
    @State private var pendingUninstall: InstalledApp?

    private enum Tab: String, CaseIterable, Identifiable {
        case apps, info
        var id: String { rawValue }
        var label: String { self == .apps ? "App installate" : "Informazioni" }
    }

    var body: some View {
        VStack(spacing: 0) {
            DeviceHeader(device: device)
            Divider()
            content
        }
        .navigationTitle(device.displayName)
        .navigationSubtitle(device.isReady ? "\(device.marketingName) · \(device.systemVersionLabel)" : "")
        .toolbar { toolbarContent }
        .task(id: device.udid) { await reloadApps() }
        .task(id: ui.appScope) { await reloadApps() }
        // Rilancia anche dopo installazioni e rimozioni, che ricaricano l'elenco.
        .task(id: installedApps.apps(for: device.udid)) { await loadIcons() }
        .confirmationDialog(
            "Rimuovere \(pendingUninstall?.name ?? "")?",
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
            titleVisibility: .visible,
            presenting: pendingUninstall
        ) { app in
            Button("Rimuovi", role: .destructive) { uninstall(app) }
            Button("Annulla", role: .cancel) {}
        } message: { _ in
            Text("L'app e tutti i suoi dati verranno eliminati dal dispositivo.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch device.state {
        case .untrusted:
            EmptyStateView(
                symbol: "lock.shield",
                title: "Autorizza questo computer",
                message: "Sblocca il dispositivo e tocca Autorizza nella richiesta che appare, poi premi il pulsante qui sotto.",
                action: ("Avvia abbinamento", { Task { await devices.pair(udid: device.udid) } })
            )
        case .locked:
            EmptyStateView(
                symbol: "lock.iphone",
                title: "Dispositivo bloccato",
                message: "Sblocca il dispositivo con il codice per consentire la comunicazione.",
                action: ("Riprova", { Task { await devices.refreshNow() } })
            )
        case .error(let message):
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "Errore di comunicazione",
                message: message,
                action: ("Riprova", { Task { await devices.refreshNow() } })
            )
        case .ready:
            switch tab {
            case .apps: appsList
            case .info: DeviceInfoList(device: device)
            }
        }
    }

    // MARK: - App installate

    private var filteredApps: [InstalledApp] {
        let apps = installedApps.apps(for: device.udid)
        let query = appSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private var appsList: some View {
        if let error = installedApps.errorsByDevice[device.udid] {
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "Impossibile leggere l'elenco app",
                message: error,
                action: ("Riprova", { Task { await reloadApps() } })
            )
        } else if installedApps.isLoading(device.udid) && filteredApps.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Lettura app installate…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredApps.isEmpty {
            EmptyStateView(
                symbol: "app.dashed",
                title: appSearch.isEmpty ? "Nessuna app" : "Nessun risultato",
                message: appSearch.isEmpty
                    ? "Su questo dispositivo non risultano app installate dall'utente."
                    : "Nessuna app corrisponde a “\(appSearch)”."
            )
        } else {
            List {
                ForEach(filteredApps) { app in
                    InstalledAppRow(
                        app: app,
                        icon: appIcons.icon(for: app),
                        upgrade: library.upgradeCandidate(for: app),
                        onInstallUpgrade: install,
                        onUninstall: { pendingUninstall = app }
                    )
                }
            }
            .listStyle(.inset)
            .searchable(text: $appSearch, prompt: "Cerca tra le app installate")
        }
    }

    private func install(_ package: IPAPackage) {
        queue.enqueueInstall(package, on: device)
        ui.showTransfers = true
    }

    private func uninstall(_ app: InstalledApp) {
        queue.enqueueUninstall(app, on: device)
        ui.showTransfers = true
    }

    private func refreshAll() {
        Task {
            await reloadApps()
            await devices.refreshNow()
        }
    }

    private func loadIcons() async {
        guard device.isReady else { return }
        await appIcons.load(installedApps.apps(for: device.udid), udid: device.udid)
    }

    private func reloadApps() async {
        guard device.isReady else { return }
        await installedApps.load(udid: device.udid, scope: ui.appScope)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Sezione", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .disabled(!device.isReady)
        }
        ToolbarItemGroup {
            Picker("Tipo", selection: Bindable(ui).appScope) {
                ForEach(InstalledAppsService.Scope.allCases) { Text($0.label).tag($0) }
            }
            .help("Filtra app utente o di sistema")
            .disabled(!device.isReady || tab != .apps)

            Button("Aggiorna", systemImage: "arrow.clockwise", action: refreshAll)
                .disabled(installedApps.isLoading(device.udid))
        }
    }
}
