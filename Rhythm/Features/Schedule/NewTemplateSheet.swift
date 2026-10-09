import RhythmCore
import SwiftUI

/// Names a new schedule and picks the weekdays it applies to.
struct NewTemplateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var weekdays: Set<Weekday> = []
    @FocusState private var nameFocused: Bool

    let onCreated: (ScheduleTemplate) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Regular Day", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("newTemplateNameField")
                } footer: {
                    Text("You can add more schedules later for late starts, minimum days, or block days.")
                }
                Section {
                    let calendar = model.calendar
                    ForEach(Weekday.ordered(for: calendar)) { weekday in
                        Toggle(isOn: Binding(
                            get: { weekdays.contains(weekday) },
                            set: { isOn in
                                if isOn { weekdays.insert(weekday) } else { weekdays.remove(weekday) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(weekday.name(in: calendar))
                                if let current = currentTemplateName(for: weekday) {
                                    Text("Currently \(current)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Use On")
                }
            }
            .navigationTitle("New Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("createTemplateButton")
                }
            }
            .onAppear {
                nameFocused = true
                // The first schedule defaults to the school week; later ones to unassigned days.
                let assigned = Set(model.configuration.weekdayAssignments.keys)
                weekdays = Set(Weekday.schoolWeek).subtracting(assigned)
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func currentTemplateName(for weekday: Weekday) -> String? {
        guard let id = model.configuration.weekdayAssignments[weekday] else { return nil }
        return model.configuration.templates[id]?.name
    }

    private func create() {
        var created: ScheduleTemplate?
        let saved = model.commit {
            created = model.repository.createTemplate(name: trimmedName, weekdays: weekdays)
        }
        model.preferences.hasCompletedOnboarding = true
        dismiss()
        if saved, let created { onCreated(created) }
    }
}
