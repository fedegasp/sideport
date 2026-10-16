import Foundation

enum ExternalTool: String, CaseIterable, Identifiable {
    case ideviceID = "idevice_id"
    case ideviceInfo = "ideviceinfo"
    case idevicePair = "idevicepair"
    case ideviceInstaller = "ideviceinstaller"
    case ideviceName = "idevicename"
    case ideviceDiagnostics = "idevicediagnostics"
    case ipatool = "ipatool"
    /// Helper incluso nel progetto (`Helpers/imc-icon`), non disponibile in Homebrew.
    case iconHelper = "imc-icon"

    var id: String { rawValue }

    /// Senza questi l'app non puo' fare nulla di utile.
    var isRequired: Bool {
        switch self {
        case .ideviceID, .ideviceInfo, .idevicePair, .ideviceInstaller: true
        case .ideviceName, .ideviceDiagnostics, .ipatool, .iconHelper: false
        }
    }

    var purpose: String {
        switch self {
        case .ideviceID: "Rileva i dispositivi collegati"
        case .ideviceInfo: "Legge modello, versione iOS e spazio disco"
        case .idevicePair: "Gestisce l'abbinamento (Autorizza questo computer)"
        case .ideviceInstaller: "Elenca, installa e rimuove le app"
        case .ideviceName: "Rinomina il dispositivo"
        case .ideviceDiagnostics: "Legge lo stato della batteria"
        case .ipatool: "Scarica le .ipa dall'App Store"
        case .iconHelper: "Legge le icone delle app installate"
        }
    }
}
