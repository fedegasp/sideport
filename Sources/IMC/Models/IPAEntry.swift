import Foundation

/// Una voce dell'archivio .ipa, come la riporta `unzip -l`.
struct IPAEntry: Hashable {
    let path: String
    let size: Int64
    let isDirectory: Bool

    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}
