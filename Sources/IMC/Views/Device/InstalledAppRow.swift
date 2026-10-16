import SwiftUI

struct InstalledAppRow: View {
    let app: InstalledApp
    /// Icona letta dal dispositivo; in sua assenza quella della .ipa in libreria.
    let icon: Data?
    let upgrade: IPAPackage?
    let onInstallUpgrade: (IPAPackage) -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(data: icon ?? upgrade?.iconData, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)

            if let upgrade {
                Button("Aggiorna a \(upgrade.versionLabel)", systemImage: "arrow.up.circle") {
                    onInstallUpgrade(upgrade)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Installa la versione presente in libreria")
            }

            Text(app.versionLabel)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)

            Text(Format.bytes(app.diskUsage))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
                .help(diskUsageDetail)

            Button("Rimuovi", systemImage: "trash", role: .destructive, action: onUninstall)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!app.isRemovable)
                .help(app.isRemovable ? "Rimuovi dal dispositivo" : "Le app di sistema non sono rimovibili")
        }
        .padding(.vertical, 3)
    }

    private var diskUsageDetail: String {
        "App \(Format.bytes(app.appDiskUsage)) · Documenti e dati \(Format.bytes(app.dataDiskUsage))"
    }
}
