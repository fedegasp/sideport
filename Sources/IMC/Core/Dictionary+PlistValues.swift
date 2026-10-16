import Foundation

/// Lettura tollerante dei valori di plist e JSON, che possono riportare lo
/// stesso campo come stringa o come numero.
extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSNumber { return value.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? NSNumber { return value.intValue }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? NSNumber { return value.boolValue }
        return nil
    }
}
