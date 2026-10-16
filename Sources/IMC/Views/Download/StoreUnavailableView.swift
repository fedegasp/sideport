import SwiftUI

struct StoreUnavailableView: View {
    private let command = "brew install ipatool"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("ipatool non trovato")
                .font(.title3.weight(.semibold))
            Text("Il download dall'App Store usa ipatool. Installalo e riapri IMC, oppure ricompila l'app: lo script di build lo incorpora nel bundle quando e' presente.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Button("Copia il comando", systemImage: "doc.on.doc", action: copyCommand)
                    .labelStyle(.iconOnly)
                    .help("Copia il comando")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
