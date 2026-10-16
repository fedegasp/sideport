import SwiftUI

struct JobRow: View {
    let job: TransferJob
    @Environment(TransferQueue.self) private var queue
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.title).lineLimit(1)
                    Text(job.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailingControl
            }

            if case .running(let stage, let fraction) = job.status {
                VStack(alignment: .leading, spacing: 3) {
                    if let fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text(stage).font(.caption).foregroundStyle(.secondary)
                }
            }

            if case .failed(let message) = job.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Riprova") { queue.retry(job) }
                        .buttonStyle(.link)
                    if !job.log.isEmpty {
                        Button(showLog ? "Nascondi log" : "Mostra log") { showLog.toggle() }
                            .buttonStyle(.link)
                    }
                }
                .font(.caption)
            }

            if showLog {
                ScrollView {
                    Text(job.log.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch job.status {
        case .queued, .running:
            Button("Annulla", systemImage: "xmark.circle.fill") { queue.cancel(job) }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
                .help("Annulla")
        case .succeeded:
            if let duration = Format.duration(from: job.startedAt, to: job.finishedAt) {
                Text(duration).font(.caption).foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }
}
