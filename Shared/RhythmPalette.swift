import RhythmCore
import SwiftUI

/// The user-selectable accent colours. Each maps to an adaptive system colour so it stays
/// legible in light and dark appearances and with Increase Contrast.
enum RhythmAccent: String, CaseIterable, Identifiable {
    case system, blue, indigo, teal, orange, purple, pink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Default"
        default: rawValue.capitalized
        }
    }

    var color: Color {
        switch self {
        case .system: .accentColor
        case .blue: .blue
        case .indigo: .indigo
        case .teal: .teal
        case .orange: .orange
        case .purple: .purple
        case .pink: .pink
        }
    }

    init(key: String?) {
        self = key.flatMap(RhythmAccent.init(rawValue:)) ?? .system
    }
}

/// Muted, consistent colours for period categories and optional per-period colour keys.
/// Colour is always paired with a symbol and text; it never carries meaning on its own.
enum RhythmPalette {
    /// Keys users can pick for an individual period.
    static let periodColorKeys = ["blue", "indigo", "teal", "green", "orange", "pink", "purple", "gray"]

    static func color(forKey key: String?) -> Color? {
        switch key {
        case "blue": .blue
        case "indigo": .indigo
        case "teal": .teal
        case "green": .green
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "gray": .gray
        default: nil
        }
    }

    static func color(for kind: PeriodKind) -> Color {
        switch kind {
        case .classPeriod: .blue
        case .lunch: .orange
        case .breakTime: .green
        case .passing: .gray
        case .other: .purple
        }
    }

    /// The tint for a period: its custom colour if set, otherwise its category colour.
    static func tint(kind: PeriodKind, colorKey: String?) -> Color {
        color(forKey: colorKey) ?? color(for: kind)
    }
}
