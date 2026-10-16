import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var devices: DeviceMonitor
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
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

private struct DeviceRow: View {
    let device: Device

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName)
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: device.symbolName)
        }
    }

    private var statusLine: String {
        switch device.state {
        case .ready: return device.systemVersionLabel
        case .untrusted: return "Da autorizzare"
        case .locked: return "Bloccato"
        case .error: return "Errore di connessione"
        }
    }

    private var statusColor: Color {
        switch device.state {
        case .ready: return .secondary
        case .untrusted, .locked: return .orange
        case .error: return .red
        }
    }
}
