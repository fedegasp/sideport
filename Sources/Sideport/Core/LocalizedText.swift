import Foundation

/// Accesso al catalogo di stringhe del modulo (`Resources/Localizable.xcstrings`).
///
/// Il catalogo non sta nel bundle principale dell'app: con SwiftPM le risorse
/// finiscono in `Sideport_Sideport.bundle`, copiato accanto all'eseguibile e poi dentro
/// `Sideport.app/Contents/Resources`. `Text("…")` e simili cercano le stringhe in
/// `Bundle.main`, quindi senza indicare il bundle l'interfaccia resterebbe in
/// inglese: queste due funzioni lo indicano una volta sola.
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
