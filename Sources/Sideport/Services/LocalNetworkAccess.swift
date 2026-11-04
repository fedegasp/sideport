import AppKit
import Foundation
import Network
import Observation

/// Chiede a macOS l'accesso alla rete locale a nome dell'app.
///
/// Per un dispositivo in Wi-Fi i tool di libimobiledevice non passano dal socket
/// di usbmuxd: aprono una connessione TCP diretta verso l'IP del dispositivo
/// (porta 62078). macOS la attribuisce a Sideport e la blocca, ma la richiesta
/// non compare, perche' a tentare e' un processo figlio e non l'app. Una ricerca
/// Bonjour avviata qui dentro la fa comparire, e il permesso concesso vale poi
/// anche per i processi figli.
///
/// Si cerca `_apple-mobdev2._tcp`, lo stesso servizio con cui usbmuxd trova i
/// dispositivi in rete: se il permesso c'e', la ricerca trova quello che l'app
/// si aspetta di poter raggiungere.
@MainActor
@Observable
final class LocalNetworkAccess {
    /// `true` quando macOS ha negato l'accesso: finche' resta cosi' nessun
    /// dispositivo in Wi-Fi rispondera'.
    private(set) var isDenied = false

    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_apple-mobdev2._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.update(for: state) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Apre il pannello dove si concede il permesso.
    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func update(for state: NWBrowser.State) {
        switch state {
        case .ready:
            isDenied = false
        case .waiting(let error), .failed(let error):
            isDenied = Self.isPolicyDenial(error)
        default:
            break
        }
    }

    /// `kDNSServiceErr_PolicyDenied` e' la risposta di mDNSResponder quando il
    /// permesso manca. Interno per i test.
    nonisolated static func isPolicyDenial(_ error: NWError) -> Bool {
        guard case .dns(let code) = error else { return false }
        return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
    }
}
