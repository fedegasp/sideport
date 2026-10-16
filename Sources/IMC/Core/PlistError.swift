import Foundation

enum PlistError: LocalizedError {
    case unexpectedShape

    var errorDescription: String? { String.ui("Unrecognized property list format.") }
}
