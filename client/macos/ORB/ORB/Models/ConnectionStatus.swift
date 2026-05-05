import AppKit
import SwiftUI

enum ConnectionStatus: String, Codable {
    case notFound
    case offline
    case online

    var labelKey: String {
        switch self {
        case .notFound:
            return "connection.status.not_found_short"
        case .offline:
            return "connection.status.offline"
        case .online:
            return "connection.status.online"
        }
    }

    var systemImage: String {
        switch self {
        case .notFound:
            return "questionmark.circle"
        case .offline:
            return "wifi.slash"
        case .online:
            return "checkmark.seal.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .notFound:
            return Color.orange
        case .offline:
            return Color.red
        case .online:
            return Color.green
        }
    }

    var nsColor: NSColor {
        switch self {
        case .notFound:
            return .systemOrange
        case .offline:
            return .systemRed
        case .online:
            return .systemGreen
        }
    }
}
