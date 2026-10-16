import Foundation

enum ToolError: LocalizedError {
    case missing(ExternalTool)

    var errorDescription: String? {
        switch self {
        case .missing(let tool):
            String.ui("Tool \u{201C}\(tool.rawValue)\u{201D} not found. Install libimobiledevice with: brew install libimobiledevice ideviceinstaller")
        }
    }
}
