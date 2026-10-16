import Foundation
import SwiftUI
import AppKit

enum Format {
    static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(from start: Date?, to end: Date?) -> String? {
        guard let start, let end else { return nil }
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 1 else { return "meno di 1 s" }
        return "\(Int(seconds.rounded())) s"
    }
}

/// Icona di un'app estratta dal .ipa, con segnaposto quando non disponibile.
struct AppIconView: View {
    let data: Data?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                    Image(systemName: "app.dashed")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var action: (title: String, handler: () -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
