import Foundation
import Testing
@testable import IMC

/// Verifica che il catalogo arrivi davvero nel bundle del modulo: senza, l'app
/// compila e funziona ma resta in inglese.
///
/// Le stringhe si leggono con `LocalizedStringResource(locale:)`: la variante
/// `String(localized:locale:)` usa la lingua preferita del bundle e ignorerebbe
/// il locale richiesto.
struct LocalizationTests {
    private let bundle = LocalizedResources.bundle

    private func text(_ key: String.LocalizationValue, _ identifier: String) -> String {
        String(localized: LocalizedStringResource(
            key,
            locale: Locale(identifier: identifier),
            bundle: .atURL(bundle.bundleURL)
        ))
    }

    @Test func shipsBothLanguages() {
        #expect(Set(bundle.localizations).isSuperset(of: ["en", "it"]))
    }

    @Test func translatesInterfaceTextToItalian() {
        #expect(text("Library", "it") == "Libreria")
        #expect(text("Install on \("iPhone")", "it") == "Installa su iPhone")
    }

    @Test func usesEnglishAsSourceLanguage() {
        #expect(text("Library", "en") == "Library")
        #expect(text("Install on \("iPhone")", "en") == "Install on iPhone")
    }

    @Test func appliesPluralRules() {
        #expect(text("\(1) items selected.", "en") == "1 item selected.")
        #expect(text("\(3) items selected.", "en") == "3 items selected.")
        #expect(text("\(3) items selected.", "it") == "3 elementi selezionati.")
    }
}
