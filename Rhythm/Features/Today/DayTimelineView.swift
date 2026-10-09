import RhythmCore
import SwiftUI

/// An ordered list of the day's periods with past, current, and upcoming states distinguished
/// by text, symbol, and weight — not by colour alone. Gaps between periods are shown as free time.
struct DayTimelineView: View {
    @Environment(AppModel.self) private var model
    let day: ResolvedDay
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(day.periods.enumerated()), id: \.element.id) { index, period in
                if index > 0 {
                    let previous = day.periods[index - 1]
                    let gap = period.startDate.timeIntervalSince(previous.endDate)
                    if gap >= 60 {
                        GapRow(gap: gap, isCurrent: previous.endDate <= now && now < period.startDate)
                    } else {
                        Divider().padding(.leading, 72)
                    }
                }
                Button {
                    model.router.presentedPeriod = PeriodPresentation(periodID: period.id, date: day.date)
                } label: {
                    TimelineRow(period: period, phase: phase(of: period))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timelineRow-\(period.title)")
            }
        }
        .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
    }

    private func phase(of period: ResolvedPeriod) -> TimelineRow.Phase {
        if period.contains(now) { return .current }
        return period.endDate <= now ? .past : .upcoming
    }
}

private struct TimelineRow: View {
    enum Phase { case past, current, upcoming }

    let period: ResolvedPeriod
    let phase: Phase

    var body: some View {
        HStack(alignment: .center, spacing: RhythmSpacing.md) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(period.startDate.shortTime)
                    .font(.subheadline.weight(phase == .current ? .semibold : .regular))
                Text(period.endDate.shortTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(minWidth: 56, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(phase == .current ? Color.accentColor : RhythmPalette.tint(kind: period.kind, colorKey: period.colorKey).opacity(phase == .past ? 0.3 : 0.7))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: RhythmSpacing.sm) {
                    Text(period.title)
                        .font(.body.weight(phase == .current ? .semibold : .regular))
                    if phase == .current {
                        TagLabel(text: "Now", tint: .accentColor)
                    }
                }
                HStack(spacing: RhythmSpacing.xs) {
                    Image(systemName: period.symbolName).accessibilityHidden(true)
                    Text([period.kind.displayName, period.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if phase == .past {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, RhythmSpacing.md)
        .padding(.horizontal, RhythmSpacing.lg)
        .frame(minHeight: RhythmLayout.minimumTouchTarget)
        .foregroundStyle(phase == .past ? Color.secondary : Color.primary)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows period details")
    }

    private var accessibilityText: String {
        let state = switch phase {
        case .past: "finished"
        case .current: "in progress"
        case .upcoming: "upcoming"
        }
        return "\(period.title), \(period.kind.displayName), \(period.startDate.shortTime) to \(period.endDate.shortTime), \(state)"
    }
}

private struct GapRow: View {
    let gap: TimeInterval
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: RhythmSpacing.sm) {
            Image(systemName: "ellipsis")
                .accessibilityHidden(true)
            Text("Free · \(CountdownFormat.short(gap))")
            if isCurrent {
                TagLabel(text: "Now", tint: .accentColor)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 72)
        .padding(.vertical, RhythmSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}
