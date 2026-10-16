import SwiftUI

struct DeviceTargetRow: View {
    let device: Device
    let packages: [IPAPackage]
    @Binding var isSelected: Bool

    /// Avvisi di compatibilita' raccolti su tutte le app selezionate.
    private var warnings: [String] {
        packages.compactMap { package in
            guard let reason = package.compatibility(with: device).reason else { return nil }
            return packages.count == 1 ? reason : "\(package.name): \(reason)"
        }
    }

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: 10) {
                Image(systemName: device.symbolName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                    Text("\(device.marketingName) · \(device.systemVersionLabel) · \(Format.bytes(device.availableDiskCapacity)) liberi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 2)
    }
}
