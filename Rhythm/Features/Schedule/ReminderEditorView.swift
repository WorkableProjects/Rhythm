import RhythmCore
import SwiftUI

/// Edits one schedule-linked reminder: before every occurrence of the period, or once on a date.
struct ReminderEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ReminderDefinition
    @State private var isOneOff: Bool
    @State private var minutesBefore: Int
    @State private var oneOffDate: Date
    private let onSave: (ReminderDefinition) -> Void

    static let offsetChoices = [0, 5, 10, 15, 20, 30, 45, 60]

    init(reminder: ReminderDefinition, onSave: @escaping (ReminderDefinition) -> Void) {
        _draft = State(initialValue: reminder)
        self.onSave = onSave
        switch reminder.trigger {
        case .beforeStart(let minutes):
            _isOneOff = State(initialValue: false)
            _minutesBefore = State(initialValue: minutes)
            _oneOffDate = State(initialValue: Date.now.addingTimeInterval(3600))
        case .oneOff(let date, let time):
            _isOneOff = State(initialValue: true)
            _minutesBefore = State(initialValue: 10)
            let calendar = Calendar.autoupdatingCurrent
            _oneOffDate = State(initialValue: date.date(at: time, in: calendar) ?? .now)
        case .standalone(let date, let time):
            _isOneOff = State(initialValue: false)
            _minutesBefore = State(initialValue: 10)
            let calendar = Calendar.autoupdatingCurrent
            if let date, let time {
                _oneOffDate = State(initialValue: date.date(at: time, in: calendar) ?? .now)
            } else {
                _oneOffDate = State(initialValue: Date.now.addingTimeInterval(3600))
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reminder, e.g. Bring gym clothes", text: $draft.title)
                        .accessibilityIdentifier("reminderTitleField")
                    TextField("Note (optional)", text: Binding(
                        get: { draft.body ?? "" },
                        set: { draft.body = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section {
                    Picker("Repeat", selection: $isOneOff) {
                        Text("Every Time").tag(false)
                        Text("Once").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isOneOff {
                        DatePicker("Date and Time", selection: $oneOffDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    } else {
                        Picker("When", selection: $minutesBefore) {
                            ForEach(Self.offsetChoices, id: \.self) { minutes in
                                Text(minutes == 0 ? "At start" : "\(minutes) min before").tag(minutes)
                            }
                        }
                    }
                } footer: {
                    Text(isOneOff
                         ? "Alerts once, only if this period is on the schedule that day."
                         : "Alerts before this period each day it’s scheduled. Days with no school are skipped.")
                }
                Section {
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var saved = draft
                        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if isOneOff {
                            let calendar = model.calendar
                            saved.trigger = .oneOff(date: LocalDate(oneOffDate, calendar: calendar),
                                                    time: ClockTime(referenceDate: oneOffDate, calendar: calendar))
                        } else {
                            saved.trigger = .beforeStart(minutes: minutesBefore)
                        }
                        onSave(saved)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveReminderButton")
                }
            }
        }
    }
}
