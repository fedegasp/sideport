import SwiftUI

struct TransfersView: View {
    @Environment(TransferQueue.self) private var queue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(.ui("Activity")).font(.headline)
                Spacer()
                if queue.hasActivity {
                    Button(.ui("Cancel all"), action: queue.cancelAll)
                        .buttonStyle(.link)
                }
                Button(.ui("Clear"), action: queue.clearFinished)
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
                        .accessibilityHidden(true)
                    Text(.ui("No transfers"))
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
