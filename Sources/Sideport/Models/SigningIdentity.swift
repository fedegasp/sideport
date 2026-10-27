import Foundation

/// Identita' di firma presente nel portachiavi, come la elenca
/// `security find-identity -v -p codesigning`.
struct SigningIdentity: Identifiable, Hashable, Sendable {
    /// Impronta SHA-1 del certificato: e' anche l'argomento piu' preciso da
    /// passare a `codesign -s`, perche' i nomi si ripetono.
    let sha1: String
    let name: String

    var id: String { sha1 }

    /// "Apple Development: Federico Gasperini (9LNABE2FAA)" → "9LNABE2FAA".
    var teamIdentifier: String? {
        guard let range = name.range(of: #"\(([A-Z0-9]+)\)$"#, options: .regularExpression) else { return nil }
        return String(name[range].dropFirst().dropLast())
    }

    /// Solo i certificati che firmano app iOS: il portachiavi contiene anche
    /// quelli per macOS e certificati aziendali che `codesign` rifiuterebbe.
    var signsIOSApps: Bool {
        Self.iosPrefixes.contains { name.hasPrefix($0) }
    }

    private static let iosPrefixes = [
        "Apple Development:",
        "Apple Distribution:",
        "iPhone Developer:",
        "iPhone Distribution:",
    ]

    /// Righe nella forma `  1) <SHA-1> "<nome>"`, chiuse dal totale finale.
    static func parse(findIdentityOutput output: String) -> [SigningIdentity] {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(.+)"\s*$"#) else {
            return []
        }
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let sha1 = Range(match.range(at: 1), in: text).map({ String(text[$0]) }),
                  let name = Range(match.range(at: 2), in: text).map({ String(text[$0]) }),
                  seen.insert(sha1).inserted else { return nil }
            return SigningIdentity(sha1: sha1.uppercased(), name: name)
        }
    }
}
