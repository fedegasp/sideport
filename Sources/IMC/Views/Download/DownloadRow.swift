import SwiftUI

struct DownloadRow: View {
    let job: StoreDownload

    @Environment(StoreService.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(UIState.self) private var ui

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.app.trackName).lineLimit(1)
                switch job.status {
                case .running(let bytes, let fraction):
                    if let fraction {
                        ProgressView(value: fraction).frame(maxWidth: 260)
                    } else {
                        ProgressView().progressViewStyle(.linear).frame(maxWidth: 260)
                    }
                    Text(bytes > 0 ? "Scaricati \(Format.bytes(bytes))" : "Avvio del download…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished(let url):
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                case .cancelled:
                    Text("Annullato").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            switch job.status {
            case .running:
                Button("Annulla") { store.cancelDownload(job) }
                    .buttonStyle(.link)
            case .finished(let url):
                if let package = library.packages.first(where: { $0.url == url }) {
                    Button("Installa su…") { ui.installSheet = .init(packages: [package]) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .failed, .cancelled:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
