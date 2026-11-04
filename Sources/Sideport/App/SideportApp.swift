import SwiftUI

@main
struct SideportApp: App {
    @State private var devices = DeviceMonitor()
    @State private var localNetwork = LocalNetworkAccess()
    @State private var library = LibraryStore()
    @State private var installedApps = InstalledAppsService()
    @State private var appIcons = AppIconStore()
    @State private var queue = TransferQueue()
    @State private var store = StoreService()
    @State private var ui = UIState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(devices)
                .environment(localNetwork)
                .environment(library)
                .environment(installedApps)
                .environment(appIcons)
                .environment(queue)
                .environment(store)
                .environment(ui)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(.ui("Refresh Devices"), action: refreshDevices)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button(.ui("Show Library")) { ui.route = .library }
                    .keyboardShortcut("1", modifiers: .command)
                Button(.ui("Show Downloads")) { ui.route = .download }
                    .keyboardShortcut("2", modifiers: .command)
                Button(.ui("Show Activity")) { ui.showTransfers.toggle() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }

    private func refreshDevices() {
        Task { await devices.refreshNow() }
    }
}
