import ActivityKit
import RhythmCore
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island presentation of the current period. Countdowns are rendered by
/// the system from absolute dates; after the stale date, the view shows what's next instead of
/// a finished timer.
struct RhythmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RhythmActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(nil)
                .widgetURL(context.state.deepLink)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(phaseLabel(state.phase))
                    } icon: {
                        Image(systemName: state.symbolName)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale {
                        Text(timerInterval: safeRange(.now, state.endDate), countsDown: true)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.phase == .freeTime ? "Free Time" : state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let next = state.nextTitle, let start = state.nextStartDate, state.phase == .inPeriod || context.isStale {
                        Text("Next: \(next) at \(start.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if state.phase != .inPeriod {
                        Text("\(state.title) starts at \(state.endDate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(state.title)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                } else {
                    Text(timerInterval: safeRange(.now, state.endDate), countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                }
            } minimal: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(state.title)
            }
            .widgetURL(state.deepLink)
        }
    }
}

private func phaseLabel(_ phase: RhythmActivityAttributes.ContentState.Phase) -> String {
    switch phase {
    case .inPeriod: "Now"
    case .freeTime: "Free Time"
    case .upcoming: "Up Next"
    }
}

private struct LockScreenActivityView: View {
    let state: RhythmActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: state.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phaseLabel(state.phase))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if isStale {
                    Text("Open Rhythm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timerInterval: safeRange(.now, state.endDate), countsDown: true)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                        Text(state.phase == .inPeriod
                             ? "ends \(state.endDate.formatted(date: .omitted, time: .shortened))"
                             : "starts \(state.endDate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !isStale {
                ProgressView(timerInterval: safeRange(state.startDate, state.endDate), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(.accentColor)
            }
            if state.phase == .inPeriod, let next = state.nextTitle, let start = state.nextStartDate {
                Text("Next: \(next) at \(start.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
