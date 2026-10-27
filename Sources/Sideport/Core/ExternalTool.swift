import Foundation

enum ExternalTool: String, CaseIterable, Identifiable {
    case ideviceID = "idevice_id"
    case ideviceInfo = "ideviceinfo"
    case idevicePair = "idevicepair"
    case ideviceInstaller = "ideviceinstaller"
    case ideviceName = "idevicename"
    case ideviceDiagnostics = "idevicediagnostics"
    case ipatool = "ipatool"
    /// Helper incluso nel progetto (`Helpers/sideport-icon`), non disponibile in Homebrew.
    case iconHelper = "sideport-icon"

    var id: String { rawValue }

    /// Senza questi l'app non puo' fare nulla di utile.
    var isRequired: Bool {
        switch self {
        case .ideviceID, .ideviceInfo, .idevicePair, .ideviceInstaller: true
        case .ideviceName, .ideviceDiagnostics, .ipatool, .iconHelper: false
        }
    }

    var purpose: LocalizedStringResource {
        switch self {
        case .ideviceID: .ui("Detects connected devices")
        case .ideviceInfo: .ui("Reads model, iOS version and disk space")
        case .idevicePair: .ui("Manages pairing (Trust This Computer)")
        case .ideviceInstaller: .ui("Lists, installs and removes apps")
        case .ideviceName: .ui("Renames the device")
        case .ideviceDiagnostics: .ui("Reads the battery level")
        case .ipatool: .ui("Downloads .ipa files from the App Store")
        case .iconHelper: .ui("Reads the icons of installed apps")
        }
    }
}
