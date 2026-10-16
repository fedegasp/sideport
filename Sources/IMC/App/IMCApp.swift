import SwiftUI

@main
struct IMCApp: App {
    @StateObject private var devices = DeviceMonitor()
    @StateObject private var library = LibraryStore()
    @StateObject private var installedApps = InstalledAppsService()
    @StateObject private var queue = TransferQueue()
    @StateObject private var store = StoreService()
    @StateObject private var ui = UIState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(devices)
                .environmentObject(library)
                .environmentObject(installedApps)
                .environmentObject(queue)
                .environmentObject(store)
                .environmentObject(ui)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Aggiorna dispositivi") {
                    Task { await devices.refreshNow() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Mostra libreria") { ui.route = .library }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Mostra download") { ui.route = .download }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Mostra attivita'") { ui.showTransfers.toggle() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}
