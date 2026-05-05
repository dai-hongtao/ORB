import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String {
        rawValue
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }

    var locale: Locale {
        if let localeIdentifier {
            return Locale(identifier: localeIdentifier)
        }
        return .autoupdatingCurrent
    }

    var titleKey: String {
        switch self {
        case .system:
            return "language.system"
        case .zhHans:
            return "language.zh-Hans"
        case .en:
            return "language.en"
        }
    }
}
