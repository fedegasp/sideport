import SwiftUI

/// Ricerca e download delle .ipa dall'App Store tramite ipatool.
struct DownloadView: View {
    @Environment(StoreService.self) private var store
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Group {
            if !store.isAvailable {
                StoreUnavailableView()
            } else {
                switch store.authState {
                case .unknown:
                    ProgressView("Verifica dell'account…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .signedOut, .signingIn, .awaitingAuthCode:
                    SignInView()
                case .signedIn:
                    StoreBrowserView()
                }
            }
        }
        .navigationTitle("Download")
        .navigationSubtitle(store.authState.account?.email ?? "")
        .task {
            if store.authState == .unknown { await store.refreshAccount() }
        }
        .onChange(of: store.completedDownloadsCount) {
            Task { await library.refresh() }
        }
    }
}
