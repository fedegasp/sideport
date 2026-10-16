import SwiftUI

struct RootView: View {
    @EnvironmentObject private var devices: DeviceMonitor
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var installedApps: InstalledAppsService
    @EnvironmentObject private var queue: TransferQueue
    @EnvironmentObject private var ui: UIState

    @State private var missingTools: [ExternalTool] = []

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 940, idealWidth: 1180, minHeight: 600, idealHeight: 760)
        .task {
            missingTools = ToolLocator.shared.missingRequiredTools
            guard missingTools.isEmpty else { return }
            // Al termine di un'installazione o rimozione si rilegge l'elenco
            // app del dispositivo interessato.
            queue.onJobSucceeded = { [weak installedApps, weak devices] udid in
                Task { @MainActor in
                    await installedApps?.load(udid: udid, scope: ui.appScope)
                    await devices?.refreshNow()
                }
            }
            devices.start()
            await library.refresh()
        }
        .onDisappear { devices.stop() }
        .sheet(item: $ui.installSheet) { request in
            InstallSheet(packages: request.packages)
        }
        .alert(item: $ui.alert) { content in
            Alert(title: Text(content.title), message: Text(content.message), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !missingTools.isEmpty {
            SetupView(missing: missingTools) {
                ToolLocator.shared.invalidateCache()
                missingTools = ToolLocator.shared.missingRequiredTools
                if missingTools.isEmpty {
                    devices.start()
                    Task { await library.refresh() }
                }
            }
        } else {
            switch ui.route {
            case .library, .none:
                LibraryView()
            case .download:
                DownloadView()
            case .device(let udid):
                if let device = devices.device(withUDID: udid) {
                    DeviceDetailView(device: device)
                } else {
                    EmptyStateView(
                        symbol: "cable.connector.slash",
                        title: "Dispositivo scollegato",
                        message: "Ricollega il dispositivo con il cavo per continuare."
                    )
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                ui.showTransfers.toggle()
            } label: {
                Label("Attivita'", systemImage: queue.hasActivity ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .symbolRenderingMode(queue.hasActivity ? .multicolor : .monochrome)
            }
            .help("Mostra la coda dei trasferimenti")
            .overlay(alignment: .topTrailing) {
                if queue.hasActivity {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -2)
                }
            }
            .popover(isPresented: $ui.showTransfers, arrowEdge: .bottom) {
                TransfersView()
            }
        }
    }
}
