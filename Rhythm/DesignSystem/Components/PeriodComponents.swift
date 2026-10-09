import RhythmCore
import SwiftUI

/// The category symbol for a period on a tinted, rounded background. Decorative: the
/// accompanying text always states the category, so VoiceOver skips the symbol.
struct PeriodSymbol: View {
    var symbolName: String
    var tint: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: RhythmRadius.control, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A small capsule tag used for semantic labels such as "Now" or "Sample".
struct TagLabel: View {
    var text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, RhythmSpacing.sm)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
