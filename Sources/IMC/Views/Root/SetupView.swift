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
                .accessibilityHidden(true)

            Text(.ui("Missing components"))
                .font(.title2.weight(.semibold))

            Text(.ui("IMC talks to iOS devices through libimobiledevice. These tools were not found:"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(missing) { tool in
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(tool.rawValue).font(.system(.body, design: .monospaced))
                        (Text(verbatim: "— ") + Text(tool.purpose)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 8) {
                Text(.ui("Install them with Homebrew:")).foregroundStyle(.secondary)
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

            Button(.ui("I installed them, check again"), action: onRecheck)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
