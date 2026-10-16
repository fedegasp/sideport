import SwiftUI

enum Route: Hashable {
    case library
    case download
    case device(String)
}

/// Stato condiviso fra piu' viste.
///
/// Qui sta solo cio' che serve a vista: campi di ricerca e selezioni restano
/// `@State` locali. Legarli a un `ObservableObject` condiviso fa si' che
/// `.searchable` e `Table(selection:)`, che li riscrivono mentre SwiftUI
/// smonta la vista durante un cambio di scheda, pubblichino modifiche nel
/// bel mezzo di un aggiornamento.
@MainActor
final class UIState: ObservableObject {
    @Published var route: Route? = .library
    @Published var showTransfers = false
    @Published var appScope: InstalledAppsService.Scope = .user
    @Published var installSheet: InstallRequest?
    @Published var inspectPackage: IPAPackage?
    @Published var alert: AlertContent?

    struct InstallRequest: Identifiable {
        let id = UUID()
        let packages: [IPAPackage]
    }

    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func present(title: String, message: String) {
        alert = AlertContent(title: title, message: message)
    }
}
