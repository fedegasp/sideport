import SwiftUI

/// Pastiglia "Wi-Fi" per i dispositivi raggiunti via rete.
///
/// Via cavo non mostra niente: e' il caso normale e un'etichetta su ogni riga
/// sarebbe solo rumore. In rete invece cambia cosa aspettarsi, perche' le
/// operazioni sono piu' lente e il dispositivo puo' sparire addormentandosi.
struct TransportBadge: View {
    let device: Device

    @ViewBuilder
    var body: some View {
        if device.isOnNetwork {
            Label(device.transportLabel, systemImage: device.transportSymbolName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .help(Text(.ui("Reachable over Wi-Fi: transfers are slower than over cable.")))
        }
    }
}
