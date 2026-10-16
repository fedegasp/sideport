import SwiftUI

struct DeviceHeader: View {
    let device: Device

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: device.symbolName)
                .font(.system(size: 40, weight: .light))
                .frame(width: 56)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName).font(.title2.weight(.semibold))
                Text(.ui("\(device.marketingName) · \(device.systemVersionLabel)"))
                    .foregroundStyle(.secondary)
                if let used = device.usedDiskCapacity, let total = device.totalDiskCapacity, total > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: Double(used), total: Double(total))
                            .frame(width: 240)
                        Text(.ui("\(Format.bytes(used)) used of \(Format.bytes(total))"))
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
                    Text((Double(level) / 100).formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .monospacedDigit()
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
