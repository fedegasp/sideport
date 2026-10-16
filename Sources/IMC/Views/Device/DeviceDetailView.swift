import SwiftUI

struct DeviceDetailView: View {
    let device: Device

    @Environment(DeviceMonitor.self) private var devices
    @Environment(InstalledAppsService.self) private var installedApps
    @Environment(AppIconStore.self) private var appIcons
    @Environment(LibraryStore.self) private var library
    @Environment(TransferQueue.self) private var queue
    @Environment(UIState.self) private var ui

    @State private var appSearch = ""
    @State private var pendingUninstall: InstalledApp?
    @State private var showInfo = false

    var body: some View {
        VStack(spacing: 0) {
            DeviceHeader(device: device) { showInfo = true }
            Divider()
            content
        }
        .navigationTitle(device.displayName)
        .navigationSubtitle(device.isReady ? "\(device.marketingName) · \(device.systemVersionLabel)" : "")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showInfo) { DeviceInfoSheet(device: device) }
        .task(id: device.udid) { await reloadApps() }
        .task(id: ui.appScope) { await reloadApps() }
        // Rilancia anche dopo installazioni e rimozioni, che ricaricano l'elenco.
        .task(id: installedApps.apps(for: device.udid)) { await loadIcons() }
        .confirmationDialog(
            Text(.ui("Remove \(pendingUninstall?.name ?? "")?")),
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
            titleVisibility: .visible,
            presenting: pendingUninstall
        ) { app in
            Button(.ui("Remove"), role: .destructive) { uninstall(app) }
            Button(.ui("Cancel"), role: .cancel) {}
        } message: { _ in
            Text(.ui("The app and all its data will be deleted from the device."))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch device.state {
        case .untrusted:
            EmptyStateView(
                symbol: "lock.shield",
                title: .ui("Trust this computer"),
                message: .ui("Unlock the device and tap Trust in the prompt that appears, then press the button below."),
                action: (.ui("Start pairing"), { Task { await devices.pair(udid: device.udid) } })
            )
        case .locked:
            EmptyStateView(
                symbol: "lock.iphone",
                title: .ui("Device locked"),
                message: .ui("Unlock the device with its passcode to allow communication."),
                action: (.ui("Try again"), { Task { await devices.refreshNow() } })
            )
        case .error(let message):
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: .ui("Communication error"),
                error: message,
                action: (.ui("Try again"), { Task { await devices.refreshNow() } })
            )
        case .ready:
            appsList
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
                title: .ui("Cannot read the app list"),
                error: error,
                action: (.ui("Try again"), { Task { await reloadApps() } })
            )
        } else if installedApps.isLoading(device.udid) && filteredApps.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text(.ui("Reading installed apps…")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredApps.isEmpty {
            EmptyStateView(
                symbol: "app.dashed",
                title: appSearch.isEmpty ? .ui("No apps") : .ui("No results"),
                message: appSearch.isEmpty
                    ? .ui("No user-installed apps were found on this device.")
                    : .ui("No app matches “\(appSearch)”.")
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
            .searchable(text: $appSearch, prompt: Text(.ui("Search installed apps")))
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
        ToolbarItemGroup {
            Picker(.ui("Type"), selection: Bindable(ui).appScope) {
                ForEach(InstalledAppsService.Scope.allCases) { Text($0.label).tag($0) }
            }
            .help(Text(.ui("Filter user or system apps")))
            .disabled(!device.isReady)

            Button(.ui("Refresh"), systemImage: "arrow.clockwise", action: refreshAll)
                .disabled(installedApps.isLoading(device.udid))
        }
    }
}
