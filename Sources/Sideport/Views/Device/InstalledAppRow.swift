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
                Button(.ui("Update to \(upgrade.versionLabel)"), systemImage: "arrow.up.circle") {
                    onInstallUpgrade(upgrade)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(Text(.ui("Install the version in the library")))
            }

            Text(app.versionLabel)
                .multilineTextAlignment(.trailing)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)

            Text(Format.bytes(app.diskUsage))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
                .help(Text(diskUsageDetail))

            Button(.ui("Remove"), systemImage: "trash", role: .destructive, action: onUninstall)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!app.isRemovable)
                .help(Text(app.isRemovable ? .ui("Remove from the device") : .ui("System apps cannot be removed")))
        }
        .padding(.vertical, 3)
    }

    private var diskUsageDetail: LocalizedStringResource {
        .ui("App \(Format.bytes(app.appDiskUsage)) · Documents and data \(Format.bytes(app.dataDiskUsage))")
    }
}
