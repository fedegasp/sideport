import Foundation
import Observation

/// Stato condiviso fra piu' viste.
///
/// Qui sta solo cio' che serve a piu' viste: campi di ricerca e selezioni
/// restano `@State` locali. Legarli a un modello condiviso fa si' che
/// `.searchable` e `Table(selection:)`, che li riscrivono mentre SwiftUI
/// smonta la vista durante un cambio di scheda, pubblichino modifiche nel
/// bel mezzo di un aggiornamento.
@MainActor
@Observable
final class UIState {
    var route: Route? = .library
    var showTransfers = false
    var appScope: InstalledAppsService.Scope = .user
    var installSheet: InstallRequest?
    var inspectPackage: IPAPackage?
    var resignPackage: IPAPackage?
    var alert: AlertContent?

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
