import SwiftUI

struct DownloadsPanel: View {
    @Environment(StoreService.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Download").font(.headline)
                Spacer()
                Button("Pulisci", action: store.clearFinishedDownloads)
                    .buttonStyle(.link)
                    .disabled(store.downloads.allSatisfy { !$0.status.isFinished })
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.downloads) { job in
                        DownloadRow(job: job)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 170)
        }
        .background(.bar)
    }
}
