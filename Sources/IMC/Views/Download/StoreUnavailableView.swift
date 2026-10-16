import SwiftUI

struct StoreUnavailableView: View {
    private let command = "brew install ipatool"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(.ui("ipatool not found"))
                .font(.title3.weight(.semibold))
            Text(.ui("Downloading from the App Store uses ipatool. Install it and reopen IMC, or rebuild the app: the build script embeds it in the bundle when present."))
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
                Button(.ui("Copy the command"), systemImage: "doc.on.doc", action: copyCommand)
                    .labelStyle(.iconOnly)
                    .help(Text(.ui("Copy the command")))
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
