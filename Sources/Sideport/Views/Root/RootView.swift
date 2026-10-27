import SwiftUI

struct RootView: View {
    @Environment(DeviceMonitor.self) private var devices
    @Environment(LibraryStore.self) private var library
    @Environment(InstalledAppsService.self) private var installedApps
    @Environment(TransferQueue.self) private var queue
    @Environment(UIState.self) private var ui

    @State private var missingTools: [ExternalTool] = []

    var body: some View {
        @Bindable var ui = ui

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 940, idealWidth: 1180, minHeight: 600, idealHeight: 760)
        .task { await start() }
        .onDisappear { devices.stop() }
        .sheet(item: $ui.installSheet) { request in
            InstallSheet(packages: request.packages)
        }
        // Il titolo dipende dal contenuto: la variante `item:` accetta solo un
        // titolo fisso, quindi serve il binding booleano derivato.
        .alert(
            ui.alert?.title ?? "",
            isPresented: Binding(get: { ui.alert != nil }, set: { if !$0 { ui.alert = nil } }),
            presenting: ui.alert
        ) { _ in
            Button(.ui("OK")) {}
        } message: { content in
            Text(content.message)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !missingTools.isEmpty {
            SetupView(missing: missingTools, onRecheck: recheckTools)
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
                        title: .ui("Device disconnected"),
                        message: .ui("Reconnect the device with the cable to continue.")
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
                Label(.ui("Activity"), systemImage: queue.hasActivity ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .symbolRenderingMode(queue.hasActivity ? .multicolor : .monochrome)
            }
            .help(Text(.ui("Show the transfer queue")))
            .overlay(alignment: .topTrailing) {
                if queue.hasActivity {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -2)
                        .accessibilityHidden(true)
                }
            }
            .popover(isPresented: Bindable(ui).showTransfers, arrowEdge: .bottom) {
                TransfersView()
            }
        }
    }

    private func start() async {
        missingTools = ToolLocator.shared.missingRequiredTools
        guard missingTools.isEmpty else { return }
        // Al termine di un'installazione o rimozione si rilegge l'elenco
        // app del dispositivo interessato.
        queue.onJobSucceeded = { [weak installedApps, weak devices, weak ui] udid in
            Task { @MainActor in
                await installedApps?.load(udid: udid, scope: ui?.appScope ?? .user)
                await devices?.refreshNow()
            }
        }
        devices.start()
        await library.refresh()
    }

    private func recheckTools() {
        ToolLocator.shared.invalidateCache()
        missingTools = ToolLocator.shared.missingRequiredTools
        guard missingTools.isEmpty else { return }
        devices.start()
        Task { await library.refresh() }
    }
}
