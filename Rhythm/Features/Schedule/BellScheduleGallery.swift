import RhythmCore
import SwiftData
import SwiftUI

/// The four school bell schedule templates students can copy: Mon/Wed/Fri, Tue/Thu (Advisory),
/// Collaboration Day, and Finals. Copies are ordinary schedules: assign them to weekdays, or use
/// them for specific dates under Date Changes.
struct BellScheduleSection: View {
    var body: some View {
        Section {
            ForEach(BellSchedulePreset.Kind.allCases) { kind in
                NavigationLink(value: kind) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.displayName)
                        Text(kind.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("bellPreset-\(kind.rawValue)")
            }
        } header: {
            Text("School Bell Schedules")
        } footer: {
            Text("Copy a template to use it every week or on specific dates. You can edit your copy without changing the template.")
        }
    }
}

/// Preview and copy one bell schedule template.
struct BellScheduleDetailView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    let kind: BellSchedulePreset.Kind

    @State private var lunch: LunchGroup = .a
    @State private var assignWeekdays = true
    @State private var didLoad = false

    private var definition: TemplateDefinition { kind.template(lunch: lunch) }
    private var existingCopy: ScheduleTemplate? { templates.first { $0.name == definition.name } }

    var body: some View {
        List {
            Section {
                if kind.dependsOnLunch {
                    Picker("Lunch", selection: $lunch) {
                        ForEach(LunchGroup.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("bellPresetLunchPicker")
                }
                if !kind.defaultWeekdays.isEmpty {
                    Toggle("Use every \(weekdayList)", isOn: $assignWeekdays)
                }
                Button(existingCopy == nil ? "Copy to My Schedules" : "Update Weekdays and Open Copy", action: copy)
                    .accessibilityIdentifier("copyBellPresetButton")
            } footer: {
                Text(footer)
            }

            Section("Periods") {
                ForEach(definition.periods) { period in
                    HStack {
                        Image(systemName: period.resolvedSymbolName)
                            .foregroundStyle(RhythmPalette.color(for: period.kind))
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(period.title)
                            if !period.isEnabled {
                                Text("Off by default; turn it on in your copy if it applies to you")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(period.start.formatted(calendar: model.calendar)) – \(period.end.formatted(calendar: model.calendar))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            lunch = model.preferences.lunchGroup
        }
    }

    private var weekdayList: String {
        kind.defaultWeekdays.map { $0.shortName(in: model.calendar) }.joined(separator: "/")
    }

    private var footer: String {
        if let existingCopy {
            return "You already have “\(existingCopy.name)” in My Schedules."
        }
        if kind.defaultWeekdays.isEmpty {
            return "After copying, use it on specific days: Schedule → Change a Date → Special → Based On."
        }
        return "Copying adds “\(definition.name)” to My Schedules."
    }

    private func copy() {
        let assign = assignWeekdays && !kind.defaultWeekdays.isEmpty
        if let copied = model.copyBellSchedule(kind, lunch: lunch, assignWeekdays: assign) {
            model.router.pendingTemplateID = copied.id
        }
    }
}
