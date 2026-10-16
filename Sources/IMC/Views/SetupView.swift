import SwiftUI
import AppKit

/// Mostrata quando mancano i binari di libimobiledevice.
struct SetupView: View {
    let missing: [ExternalTool]
    let onRecheck: () -> Void

    private let command = "brew install libimobiledevice ideviceinstaller"

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("Componenti mancanti")
                .font(.title2.weight(.semibold))

            Text("IMC comunica con i dispositivi iOS tramite libimobiledevice. Questi strumenti non sono stati trovati:")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(missing) { tool in
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(tool.rawValue).font(.system(.body, design: .monospaced))
                        Text("— \(tool.purpose)").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 8) {
                Text("Installali con Homebrew:").foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copia il comando")
                }
            }

            Button("Ho installato, verifica di nuovo", action: onRecheck)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
