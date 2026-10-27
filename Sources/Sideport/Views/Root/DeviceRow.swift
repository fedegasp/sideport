import SwiftUI

struct DeviceRow: View {
    let device: Device

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName)
                    .lineLimit(1)
                statusText
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: device.symbolName)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch device.state {
        case .ready: Text(device.systemVersionLabel)
        case .untrusted: Text(.ui("Awaiting trust"))
        case .locked: Text(.ui("Locked"))
        case .error: Text(.ui("Connection error"))
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
