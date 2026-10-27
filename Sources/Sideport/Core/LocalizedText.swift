import Foundation

/// Accesso al catalogo di stringhe (`Resources/Localizable.xcstrings`).
///
/// `#bundle` si espande nel bundle del modulo in cui e' scritto, che nel target
/// dell'app e' `Bundle.main`: li' Xcode compila il catalogo. Queste due funzioni
/// risolvono il bundle in un punto solo invece di lasciarlo implicito in ognuna
/// delle 349 chiamate.
extension LocalizedStringResource {
    static func ui(_ key: String.LocalizationValue) -> Self {
        LocalizedStringResource(key, bundle: #bundle)
    }
}

extension String {
    /// Variante per il testo conservato come `String`: messaggi d'errore e stati
    /// dei job, che si mescolano all'output grezzo dei tool esterni.
    static func ui(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: #bundle)
    }
}

/// Bundle che contiene il catalogo, per chi non puo' usare `#bundle`: si espande
/// nel modulo in cui e' scritto, quindi dal target di test darebbe il bundle
/// sbagliato.
enum LocalizedResources {
    static var bundle: Bundle { #bundle }
}
