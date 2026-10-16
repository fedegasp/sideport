import Foundation

enum PlistParsing {
    /// Converte dati plist (XML o binario) in dizionario.
    static func dictionary(from data: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = object as? [String: Any] else {
            throw PlistError.unexpectedShape
        }
        return dict
    }

    /// Converte dati plist in array di dizionari (output di `ideviceinstaller list --xml`).
    static func dictionaryArray(from data: Data) throws -> [[String: Any]] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        if let array = object as? [[String: Any]] { return array }
        if let dict = object as? [String: Any] { return [dict] }
        throw PlistError.unexpectedShape
    }

    /// `ideviceinstaller` puo' anteporre righe di log al plist; isola il documento.
    static func extractPlistData(from output: String) -> Data? {
        guard let start = output.range(of: "<?xml") ?? output.range(of: "<plist") else { return nil }
        guard let end = output.range(of: "</plist>", options: .backwards) else { return nil }
        return String(output[start.lowerBound..<end.upperBound]).data(using: .utf8)
    }
}
