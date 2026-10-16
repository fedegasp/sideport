import SwiftUI

struct SidebarView: View {
    @Environment(DeviceMonitor.self) private var devices
    @Environment(LibraryStore.self) private var library
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui

        List(selection: $ui.route) {
            Section("Libreria") {
                Label("App (.ipa)", systemImage: "square.stack.3d.down.right")
                    .badge(library.packages.count)
                    .tag(Route.library)
                Label("Download", systemImage: "arrow.down.app")
                    .tag(Route.download)
            }

            Section("Dispositivi") {
                if devices.devices.isEmpty {
                    Label("Nessun dispositivo", systemImage: "cable.connector")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                } else {
                    ForEach(devices.devices) { device in
                        DeviceRow(device: device)
                            .tag(Route.device(device.udid))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let error = devices.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
            }
        }
    }
}
