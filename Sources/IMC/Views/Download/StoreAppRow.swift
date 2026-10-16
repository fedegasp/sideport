import SwiftUI

struct StoreAppRow: View {
    let app: StoreApp
    let platform: StorePlatform
    let onDownload: (Bool) -> Void

    @Environment(StoreService.self) private var store
    @Environment(\.locale) private var locale

    private var isDownloading: Bool {
        store.downloads.contains { $0.app.id == app.id && !$0.status.isFinished }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.trackName).lineLimit(1)
                HStack(spacing: 6) {
                    Text(app.bundleId)
                    Text(verbatim: "·")
                    Text(.ui("v\(app.version)"))
                    if let purchased = app.purchaseDateLabel {
                        Text(verbatim: "·")
                        Text(.ui("purchased on \(purchased)"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(app.priceLabel(locale: locale))
                .font(.callout)
                .foregroundStyle(.secondary)

            if isDownloading {
                ProgressView().controlSize(.small)
            } else if app.isOwned {
                Button(.ui("Download")) { onDownload(false) }
                    .buttonStyle(.bordered)
            } else if app.isFree {
                Button(.ui("Get and download")) { onDownload(true) }
                    .buttonStyle(.bordered)
                    .help(Text(.ui("Acquires the free license on your account, then downloads the package")))
            } else {
                // La ricerca non riporta la data d'acquisto, quindi non si puo'
                // sapere se l'app e' gia' posseduta: si tenta e, se la licenza
                // manca, ipatool lo dice.
                Button(.ui("Download")) { onDownload(false) }
                    .buttonStyle(.bordered)
                    .help(Text(.ui("Paid app: it downloads only if already purchased with this Apple ID, otherwise buy it from the App Store")))
            }
        }
        .padding(.vertical, 3)
    }
}
