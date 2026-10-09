import RhythmCore
import SwiftUI

/// The main live-event module. Its countdown is recomputed from absolute dates on every tick, so
/// it is always correct after backgrounding or relaunch. `TimelineView` only ticks while the view
/// is on screen and the app is active.
struct LiveStatusModule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LiveStatusContent(snapshot: model.snapshot(at: context.date))
        }
    }
}

struct LiveStatusContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 56
    let snapshot: ScheduleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: RhythmSpacing.md) {
            TagLabel(text: snapshot.stateLabel, tint: .accentColor)

            HStack(alignment: .top, spacing: RhythmSpacing.md) {
                if let focus {
                    PeriodSymbol(symbolName: focus.symbolName, tint: RhythmPalette.tint(kind: focus.kind, colorKey: focus.colorKey), size: 40)
                }
                VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let remaining = snapshot.remaining {
                VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                    Text(CountdownFormat.clock(remaining))
                        .font(.system(size: countdownSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityIdentifier("countdown")
                    Text(countdownCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = snapshot.progress {
                VStack(spacing: RhythmSpacing.xs) {
                    ProgressView(value: progress)
                        .tint(.accentColor)
                        .accessibilityHidden(true)
                    if let range = progressRange {
                        HStack {
                            Text(range.lowerBound.shortTime)
                            Spacer()
                            Text(range.upperBound.shortTime)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                    }
                }
            }

            if snapshot.state == .inProgress, let next = snapshot.nextPeriod {
                Divider()
                HStack(spacing: RhythmSpacing.sm) {
                    Text("Up Next")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(next.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: RhythmSpacing.sm)
                    Text(next.startDate.shortTime)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RhythmSpacing.xl)
        .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.module, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: RhythmRadius.module, style: .continuous))
        .onTapGesture { presentFocus() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAction(named: "Show details") { presentFocus() }
        .accessibilityIdentifier("liveStatus")
        .animation(RhythmMotion.animation(RhythmMotion.stateChange, reduceMotion: reduceMotion), value: snapshot.state)
        .animation(RhythmMotion.animation(RhythmMotion.stateChange, reduceMotion: reduceMotion), value: focus?.id)
    }

    // MARK: Derived text

    /// The period the module is about: the active one, or the next one.
    private var focus: ResolvedPeriod? {
        snapshot.activePeriod ?? snapshot.nextPeriod
    }

    private var title: String {
        switch snapshot.state {
        case .inProgress, .upcoming: focus?.title ?? ""
        case .freeTime: snapshot.stateLabel
        case .dayComplete: "That’s a wrap for today"
        case .noSchool: "No School"
        case .scheduleNeeded: "Schedule Needed"
        }
    }

    private var subtitle: String {
        switch snapshot.state {
        case .inProgress, .upcoming:
            guard let focus else { return "" }
            return [focus.kind.displayName, focus.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .freeTime:
            return snapshot.nextPeriod.map { "Next: \($0.title) at \($0.startDate.shortTime)" } ?? ""
        case .dayComplete:
            if let last = snapshot.previousPeriod { return "\(last.title) ended at \(last.endDate.shortTime)." }
            return "All periods have ended."
        case .noSchool, .scheduleNeeded:
            return ""
        }
    }

    private var countdownCaption: String {
        switch snapshot.state {
        case .inProgress:
            snapshot.activePeriod.map { "remaining · ends at \($0.endDate.shortTime)" } ?? ""
        case .upcoming, .freeTime:
            snapshot.nextPeriod.map { "until \($0.title)" } ?? ""
        default:
            ""
        }
    }

    private var progressRange: ClosedRange<Date>? {
        if let active = snapshot.activePeriod { return active.startDate...active.endDate }
        if snapshot.state == .freeTime, let previous = snapshot.previousPeriod, let next = snapshot.nextPeriod,
           previous.endDate <= next.startDate {
            return previous.endDate...next.startDate
        }
        return nil
    }

    /// e.g. "In Progress. Biology, 12 minutes remaining, ends at 10:42 AM."
    private var accessibilityText: String {
        switch snapshot.state {
        case .inProgress:
            guard let active = snapshot.activePeriod else { return title }
            var text = "In progress. \(active.title), \(CountdownFormat.spoken(active.remaining(at: snapshot.now))) remaining, ends at \(active.endDate.shortTime)."
            if let next = snapshot.nextPeriod { text += " Up next: \(next.title) at \(next.startDate.shortTime)." }
            return text
        case .freeTime, .upcoming:
            guard let next = snapshot.nextPeriod else { return title }
            let prefix = snapshot.state == .freeTime ? "\(snapshot.stateLabel). " : "Up next. "
            return prefix + "\(next.title) starts in \(CountdownFormat.spoken(next.startDate.timeIntervalSince(snapshot.now))), at \(next.startDate.shortTime)."
        default:
            return "\(title). \(subtitle)"
        }
    }

    private func presentFocus() {
        guard let focus else { return }
        model.router.presentedPeriod = PeriodPresentation(periodID: focus.id, date: snapshot.day.date)
    }
}
