import SwiftUI

struct StoreAppRow: View {
    let app: StoreApp
    let platform: StorePlatform
    let onDownload: (Bool) -> Void

    @Environment(StoreService.self) private var store

    private var isDownloading: Bool {
        store.downloads.contains { $0.app.id == app.id && !$0.status.isFinished }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.trackName).lineLimit(1)
                HStack(spacing: 6) {
                    Text(app.bundleId)
                    Text("·")
                    Text("v\(app.version)")
                    if let purchased = app.purchaseDateLabel {
                        Text("·")
                        Text("acquistata il \(purchased)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(app.priceLabel)
                .font(.callout)
                .foregroundStyle(.secondary)

            if isDownloading {
                ProgressView().controlSize(.small)
            } else if app.isOwned {
                Button("Scarica") { onDownload(false) }
                    .buttonStyle(.bordered)
            } else if app.isFree {
                Button("Ottieni e scarica") { onDownload(true) }
                    .buttonStyle(.bordered)
                    .help("Acquisisce la licenza gratuita sul tuo account, poi scarica il pacchetto")
            } else {
                // La ricerca non riporta la data d'acquisto, quindi non si puo'
                // sapere se l'app e' gia' posseduta: si tenta e, se la licenza
                // manca, ipatool lo dice.
                Button("Scarica") { onDownload(false) }
                    .buttonStyle(.bordered)
                    .help("App a pagamento: si scarica solo se gia' acquistata con questo Apple ID, altrimenti va comprata dall'App Store")
            }
        }
        .padding(.vertical, 3)
    }
}
