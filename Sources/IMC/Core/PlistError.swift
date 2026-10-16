import Foundation

enum PlistError: LocalizedError {
    case unexpectedShape

    var errorDescription: String? { "Formato property list non riconosciuto." }
}
