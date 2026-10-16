import SwiftUI

struct DeviceDetailView: View {
    let device: Device

    @EnvironmentObject private var devices: DeviceMonitor
    @EnvironmentObject private var installedApps: InstalledAppsService
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: TransferQueue
    @EnvironmentObject private var ui: UIState

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
        .confirmationDialog(
            pendingUninstall.map { "Rimuovere \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
            titleVisibility: .visible
        ) {
            Button("Rimuovi", role: .destructive) {
                if let app = pendingUninstall {
                    queue.enqueueUninstall(app, on: device)
                    ui.showTransfers = true
                }
                pendingUninstall = nil
            }
            Button("Annulla", role: .cancel) { pendingUninstall = nil }
        } message: {
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
                        upgrade: library.upgradeCandidate(for: app),
                        onInstallUpgrade: { package in
                            queue.enqueueInstall(package, on: device)
                            ui.showTransfers = true
                        },
                        onUninstall: { pendingUninstall = app }
                    )
                }
            }
            .listStyle(.inset)
            .searchable(text: $appSearch, prompt: "Cerca tra le app installate")
        }
    }

    private func reloadApps() async {
        guard device.isReady else { return }
        await installedApps.load(udid: device.udid, scope: ui.appScope)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .disabled(!device.isReady)
        }
        ToolbarItemGroup {
            Picker("Tipo", selection: $ui.appScope) {
                ForEach(InstalledAppsService.Scope.allCases) { Text($0.label).tag($0) }
            }
            .help("Filtra app utente o di sistema")
            .disabled(!device.isReady || tab != .apps)

            Button { Task { await reloadApps(); await devices.refreshNow() } } label: {
                Label("Aggiorna", systemImage: "arrow.clockwise")
            }
            .disabled(installedApps.isLoading(device.udid))
        }
    }
}

// MARK: - Intestazione

private struct DeviceHeader: View {
    let device: Device

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: device.symbolName)
                .font(.system(size: 40, weight: .light))
                .frame(width: 56)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName).font(.title2.weight(.semibold))
                Text("\(device.marketingName) · \(device.systemVersionLabel)")
                    .foregroundStyle(.secondary)
                if let used = device.usedDiskCapacity, let total = device.totalDiskCapacity, total > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: Double(used), total: Double(total))
                            .frame(width: 240)
                        Text("\(Format.bytes(used)) usati di \(Format.bytes(total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            if let level = device.batteryLevel {
                VStack(spacing: 2) {
                    Image(systemName: device.isCharging == true ? "battery.100.bolt" : batterySymbol(level))
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                    Text("\(level)%").font(.caption).monospacedDigit()
                }
                .foregroundStyle(level <= 20 && device.isCharging != true ? .red : .secondary)
            }
        }
        .padding(16)
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Riga app

private struct InstalledAppRow: View {
    let app: InstalledApp
    let upgrade: IPAPackage?
    let onInstallUpgrade: (IPAPackage) -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(data: upgrade?.iconData, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)

            if let upgrade {
                Button {
                    onInstallUpgrade(upgrade)
                } label: {
                    Label("Aggiorna a \(upgrade.versionLabel)", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Installa la versione presente in libreria")
            }

            Text(app.versionLabel)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)

            Text(Format.bytes(app.diskUsage))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Button(role: .destructive, action: onUninstall) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!app.isRemovable)
            .help(app.isRemovable ? "Rimuovi dal dispositivo" : "Le app di sistema non sono rimovibili")
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Informazioni

private struct DeviceInfoList: View {
    let device: Device
    @EnvironmentObject private var devices: DeviceMonitor
    @State private var newName = ""
    @State private var isRenaming = false

    var body: some View {
        Form {
            Section("Dispositivo") {
                InfoRow(label: "Nome", value: device.name)
                InfoRow(label: "Modello", value: "\(device.marketingName) (\(device.productType))")
                InfoRow(label: "Numero di serie", value: device.serialNumber)
                InfoRow(label: "UDID", value: device.udid)
            }
            Section("Sistema") {
                InfoRow(label: "Versione", value: device.systemVersionLabel)
                InfoRow(label: "Build", value: device.buildVersion)
                InfoRow(label: "Classe", value: device.deviceClass)
            }
            Section("Archiviazione") {
                InfoRow(label: "Capacita' totale", value: Format.bytes(device.totalDiskCapacity))
                InfoRow(label: "Spazio disponibile", value: Format.bytes(device.availableDiskCapacity))
                InfoRow(label: "Spazio usato", value: Format.bytes(device.usedDiskCapacity))
            }
            Section {
                Button("Rinomina dispositivo…") {
                    newName = device.name
                    isRenaming = true
                }
                .disabled(ToolLocator.shared.url(for: .ideviceName) == nil)
            }
        }
        .formStyle(.grouped)
        .alert("Rinomina dispositivo", isPresented: $isRenaming) {
            TextField("Nome", text: $newName)
            Button("Annulla", role: .cancel) {}
            Button("Rinomina") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { try? await devices.rename(udid: device.udid, to: name) }
            }
        }
    }
}
