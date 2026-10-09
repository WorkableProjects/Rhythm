import SwiftUI
import UIKit

/// Rhythm's spacing scale. Use these values instead of arbitrary numbers.
enum RhythmSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

/// Corner radii for content surfaces.
enum RhythmRadius {
    /// Small controls and tags.
    static let control: CGFloat = 10
    /// Rows and grouped content.
    static let row: CGFloat = 14
    /// The main live-event module.
    static let module: CGFloat = 24
}

/// Animation durations and curves. Always gate through `RhythmMotion.animation(_:reduceMotion:)`.
enum RhythmMotion {
    static let quick: Double = 0.16
    static let standard: Double = 0.25

    static var stateChange: Animation { .smooth(duration: standard) }
    static var selection: Animation { .easeOut(duration: quick) }

    /// Returns `nil` when Reduce Motion is on so changes apply without animation.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Semantic surface colours mapped to adaptive system colours.
enum RhythmSurface {
    static var background: Color { Color(uiColor: .systemGroupedBackground) }
    static var content: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var separator: Color { Color(uiColor: .separator) }
}

/// Minimum touch target from Apple's accessibility guidance.
enum RhythmLayout {
    static let minimumTouchTarget: CGFloat = 44
}
