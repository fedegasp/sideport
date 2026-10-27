import Foundation

/// Confronto numerico di versioni puntate ("1.10" > "1.9").
enum VersionCompare {
    static func isLower(_ lhs: String, than rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedAscending
    }

    static func isHigher(_ lhs: String, than rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }
}
