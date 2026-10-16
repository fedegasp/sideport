import SwiftUI

struct TransfersView: View {
    @EnvironmentObject private var queue: TransferQueue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Attivita'").font(.headline)
                Spacer()
                if queue.hasActivity {
                    Button("Annulla tutto") { queue.cancelAll() }
                        .buttonStyle(.link)
                }
                Button("Pulisci") { queue.clearFinished() }
                    .buttonStyle(.link)
                    .disabled(queue.jobs.allSatisfy { !$0.status.isFinished })
            }
            .padding(12)

            Divider()

            if queue.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Nessun trasferimento")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(queue.jobs.reversed()) { job in
                            JobRow(job: job)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 340)
    }
}

private struct JobRow: View {
    let job: TransferJob
    @EnvironmentObject private var queue: TransferQueue
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
            Button {
                queue.cancel(job)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
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
