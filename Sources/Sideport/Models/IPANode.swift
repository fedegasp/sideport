import Foundation

/// Nodo dell'albero dei contenuti: per le cartelle `size` e' la somma dei figli.
struct IPANode: Identifiable, Hashable {
    let id: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let children: [IPANode]?
}
