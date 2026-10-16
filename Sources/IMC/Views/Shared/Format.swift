import Foundation

enum Format {
    static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(from start: Date?, to end: Date?) -> String? {
        guard let start, let end else { return nil }
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 1 else { return "meno di 1 s" }
        return "\(Int(seconds.rounded())) s"
    }
}
