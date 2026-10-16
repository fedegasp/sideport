import Foundation

enum ToolError: LocalizedError {
    case missing(ExternalTool)

    var errorDescription: String? {
        switch self {
        case .missing(let tool):
            "Strumento '\(tool.rawValue)' non trovato. Installa libimobiledevice con: brew install libimobiledevice ideviceinstaller"
        }
    }
}
