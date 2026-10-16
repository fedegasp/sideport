import SwiftUI

struct DeviceRow: View {
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
        case .ready: device.systemVersionLabel
        case .untrusted: "Da autorizzare"
        case .locked: "Bloccato"
        case .error: "Errore di connessione"
        }
    }

    private var statusColor: Color {
        switch device.state {
        case .ready: .secondary
        case .untrusted, .locked: .orange
        case .error: .red
        }
    }
}
