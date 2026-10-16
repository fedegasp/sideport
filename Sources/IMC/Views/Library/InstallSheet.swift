import SwiftUI

/// Scelta dei dispositivi di destinazione per una o piu' .ipa.
struct InstallSheet: View {
    let packages: [IPAPackage]

    @Environment(DeviceMonitor.self) private var devices
    @Environment(TransferQueue.self) private var queue
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var selectedUDIDs = Set<String>()

    private var targets: [Device] { devices.devices.filter(\.isReady) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            deviceList
            Divider()
            footer
        }
        .frame(width: 520, height: 420)
        .onAppear {
            // Preseleziona l'unico dispositivo disponibile.
            if targets.count == 1, let only = targets.first {
                selectedUDIDs = [only.udid]
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(packages.count == 1 ? "Installa \(packages[0].name)" : "Installa \(packages.count) app")
                .font(.headline)

            if packages.count == 1, let package = packages.first {
                HStack(spacing: 10) {
                    AppIconView(data: package.iconData, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.bundleIdentifier)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Versione \(package.versionLabel) · \(Format.bytes(package.fileSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(packages.map(\.name).joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
    }

    private var deviceList: some View {
        Group {
            if targets.isEmpty {
                EmptyStateView(
                    symbol: "cable.connector",
                    title: "Nessun dispositivo pronto",
                    message: "Collega un iPhone o iPad con il cavo, sbloccalo e tocca Autorizza."
                )
            } else {
                List {
                    ForEach(targets) { device in
                        DeviceTargetRow(
                            device: device,
                            packages: packages,
                            isSelected: $selectedUDIDs[contains: device.udid]
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if targets.count > 1 {
                Button(selectedUDIDs.count == targets.count ? "Deseleziona tutti" : "Seleziona tutti") {
                    selectedUDIDs = selectedUDIDs.count == targets.count ? [] : Set(targets.map(\.udid))
                }
                .buttonStyle(.link)
            }
            Spacer()
            Button("Annulla") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(installLabel) { startInstall() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedUDIDs.isEmpty || packages.isEmpty)
        }
        .padding(16)
    }

    private var installLabel: String {
        let count = packages.count * max(selectedUDIDs.count, 1)
        return selectedUDIDs.isEmpty || count == 1 ? "Installa" : "Installa (\(count))"
    }

    private func startInstall() {
        let selected = targets.filter { selectedUDIDs.contains($0.udid) }
        for device in selected {
            for package in packages {
                queue.enqueueInstall(package, on: device)
            }
        }
        dismiss()
        ui.showTransfers = true
    }
}
