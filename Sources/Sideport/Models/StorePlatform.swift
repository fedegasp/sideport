enum StorePlatform: String, CaseIterable, Identifiable {
    case iphone
    case ipad

    var id: String { rawValue }
    var label: String { self == .iphone ? "iPhone" : "iPad" }
}
