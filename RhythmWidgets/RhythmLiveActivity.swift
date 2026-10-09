import ActivityKit
import RhythmCore
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island presentation of the school day. Countdowns are rendered by the
/// system from absolute dates. When the current segment ends, iOS marks the activity stale and
/// re-renders it; the views then show the following segment, so the activity keeps up with the
/// bell even when Rhythm isn't running.
struct RhythmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RhythmActivityAttributes.self) { context in
            LockScreenActivityView(segment: context.state.shown(isStale: context.isStale))
                .activityBackgroundTint(nil)
                .widgetURL(context.state.deepLink)
        } dynamicIsland: { context in
            let segment = context.state.shown(isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(segment.map(label) ?? "Rhythm")
                    } icon: {
                        Image(systemName: segment?.symbolName ?? "checkmark.circle")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let segment {
                        SegmentTimer(segment: segment)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(segment.map(headline) ?? "School’s out")
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let segment {
                        Text(detail(segment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: segment?.symbolName ?? "checkmark.circle")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(segment.map(headline) ?? "School’s out")
            } compactTrailing: {
                if let segment {
                    SegmentTimer(segment: segment)
                        .frame(maxWidth: 52)
                } else {
                    Image(systemName: "checkmark")
                }
            } minimal: {
                Image(systemName: segment?.symbolName ?? "checkmark.circle")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(segment.map(headline) ?? "School’s out")
            }
            .widgetURL(context.state.deepLink)
        }
    }
}

private typealias Segment = RhythmActivityAttributes.ContentState.Segment

fileprivate extension RhythmActivityAttributes.ContentState {
    /// The segment to display: the current one, or after it ends (stale) the following one.
    /// `nil` when the day has ended.
    func shown(isStale: Bool) -> Segment? {
        isStale ? following : current
    }
}

/// "Now", "Passing Period", "Free Time", "Up Next".
private func label(_ segment: Segment) -> String {
    switch segment.kind {
    case .period: "Now"
    case .passing: "Passing Period"
    case .freeTime: "Free Time"
    case .beforeSchool: "Up Next"
    }
}

/// The period name, or "until Period 2" for gaps.
private func headline(_ segment: Segment) -> String {
    segment.kind == .period ? segment.title : "until \(segment.title)"
}

private func detail(_ segment: Segment) -> String {
    let time = segment.endDate.formatted(date: .omitted, time: .shortened)
    return segment.kind == .period ? "Ends at \(time)" : "\(segment.title) starts at \(time)"
}

/// A system-rendered countdown to the end of the segment.
private struct SegmentTimer: View {
    let segment: Segment

    var body: some View {
        Text(timerInterval: safeRange(segment.startDate, segment.endDate), countsDown: true)
            .monospacedDigit()
    }
}

private struct LockScreenActivityView: View {
    let segment: Segment?

    var body: some View {
        Group {
            if let segment {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: segment.symbolName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(segment))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(segment.kind == .period ? segment.title : "Next: \(segment.title)")
                                .font(.headline)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            SegmentTimer(segment: segment)
                                .font(.title2.weight(.semibold))
                                .multilineTextAlignment(.trailing)
                            Text(segment.kind == .period ? "left" : "until \(segment.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    ProgressView(timerInterval: safeRange(segment.startDate, segment.endDate), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    Text(detail(segment))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("School’s out for today.")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
