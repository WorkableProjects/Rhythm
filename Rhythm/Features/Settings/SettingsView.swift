import RhythmCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Native Settings-style preferences. Every row here is functional.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var exportDocument: RhythmExportDocument?
    @State private var isImporting = false
    @State private var importPreview: ImportPreview?
    @State private var alert: SettingsAlert?
    @State private var isConfirmingDeleteAll = false
    @State private var isExplainingLiveActivities = false
    @State private var isChoosingBellScheduleLunch = false

    var body: some View {
        NavigationStack {
            withDataPresentations(withPreferenceObservers(form))
        }
    }

    private var form: some View {
        @Bindable var preferences = model.preferences
        return Form {
            appearanceSection(appearance: $preferences.appearance, accent: $preferences.accent)
            liveActivitySection(preferences: $preferences.liveActivitiesEnabled)
            notificationsSection(remindersEnabled: $preferences.remindersEnabled)
            scheduleSection
            dataSection
            Section("About") {
                LabeledContent("Version", value: Self.versionString)
                NavigationLink("Privacy") { PrivacyView() }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    /// Applies preference changes to notifications, widgets, and the Live Activity.
    private func withPreferenceObservers(_ content: some View) -> some View {
        content
            .onChange(of: model.preferences.accent) { model.preferencesDidChange() }
            .onChange(of: model.preferences.remindersEnabled) { model.preferencesDidChange() }
            .onChange(of: model.preferences.liveActivitiesEnabled) { _, isOn in
                liveActivitiesToggled(isOn)
            }
            .alert("Live Activities", isPresented: $isExplainingLiveActivities) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("During school hours, Rhythm can show the current period and time remaining on your Lock Screen and in the Dynamic Island. iOS decides when they appear and may limit them in Settings or Low Power Mode.")
            }
    }

    /// Export, import, delete-all, and result alerts.
    private func withDataPresentations(_ content: some View) -> some View {
        withResultAlert(withImportExport(content))
            .confirmationDialog("Delete All Rhythm Data?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete All Data", role: .destructive, action: deleteAllData)
            } message: {
                Text("This removes every schedule, date change, reminder, and Quicklink. It can’t be undone. Consider exporting first.")
            }
    }

    private func withImportExport(_ content: some View) -> some View {
        content
            .fileExporter(isPresented: isExportingBinding, document: exportDocument, contentType: .json,
                          defaultFilename: "Rhythm Timetable", onCompletion: handleExportResult)
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], onCompletion: handleImport)
            .sheet(item: $importPreview) { preview in
                ImportPreviewView(preview: preview, onFinish: importFinished)
            }
    }

    private func withResultAlert(_ content: some View) -> some View {
        content.alert(alert?.title ?? "", isPresented: isShowingAlertBinding, presenting: alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    private var isExportingBinding: Binding<Bool> {
        Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } })
    }

    private var isShowingAlertBinding: Binding<Bool> {
        Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })
    }

    private func liveActivitiesToggled(_ isOn: Bool) {
        if isOn && !model.preferences.hasSeenLiveActivityExplanation {
            isExplainingLiveActivities = true
            model.preferences.hasSeenLiveActivityExplanation = true
        }
        model.preferencesDidChange()
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            alert = SettingsAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func importFinished(_ success: Bool) {
        if success {
            alert = SettingsAlert(title: "Import Complete", message: "Your timetable was replaced with the imported one.")
        } else {
            alert = SettingsAlert(title: "Import Failed", message: model.saveError ?? "Your previous data was kept.")
        }
    }

    private func deleteAllData() {
        model.deleteAllData()
        alert = SettingsAlert(title: "Data Deleted", message: "All schedules, date changes, reminders, and Quicklinks were removed from this iPhone.")
    }

    // MARK: Sections

    private func appearanceSection(appearance: Binding<AppearancePreference>, accent: Binding<RhythmAccent>) -> some View {
        Section("Appearance") {
            Picker("Appearance", selection: appearance) {
                ForEach(AppearancePreference.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Accent Color", selection: accent) {
                ForEach(RhythmAccent.allCases) { option in
                    Label {
                        Text(option.displayName)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(option.color)
                    }
                    .tag(option)
                }
            }
        }
    }

    private var scheduleSection: some View {
        let zone = model.calendar.timeZone
        let zoneName = zone.localizedName(for: .generic, locale: .current) ?? zone.identifier
        return Section {
            LabeledContent("Time Format", value: "Follows iPhone Settings")
            LabeledContent("Time Zone", value: zoneName)
        } header: {
            Text("Schedule")
        } footer: {
            Text("Rhythm uses your iPhone’s current time zone and recalculates automatically when it changes.")
        }
    }

    private func liveActivitySection(preferences enabled: Binding<Bool>) -> some View {
        Section {
            Toggle("Show Current Period", isOn: enabled)
                .accessibilityIdentifier("liveActivityToggle")
            if !model.liveActivities.systemAllowsActivities {
                VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                    Text("Live Activities are turned off for Rhythm in iOS Settings.")
                        .font(.footnote)
                    Button("Open Settings") { openAppSettings() }
                        .font(.footnote.weight(.semibold))
                }
            }
            if enabled.wrappedValue {
                Button("Start Now") {
                    Task { await model.startLiveActivityNow() }
                }
                .accessibilityIdentifier("startLiveActivityButton")
                NavigationLink("Start Automatically Every Day") { LiveActivityAutomationView() }
                LabeledContent("Status", value: liveActivityStatus)
                if let start = model.liveActivities.scheduledStart {
                    LabeledContent("Next Automatic Start", value: start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                }
            }
            if let error = model.liveActivities.lastError, enabled.wrappedValue {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("liveActivityError")
            }
        } header: {
            Text("Live Activity")
        } footer: {
            Text("Shows the current period, passing periods, and a countdown on the Lock Screen and in the Dynamic Island. It starts when you open Rhythm during school hours, and iOS starts a scheduled one before the first bell.")
        }
    }

    private var liveActivityStatus: String {
        let live = model.liveActivities
        if !live.systemAllowsActivities { return "Off in iOS Settings" }
        if live.runningCount > 0 { return "Showing" }
        if live.pendingCount > 0 { return "Scheduled" }
        return "Not showing"
    }

    private func notificationsSection(remindersEnabled: Binding<Bool>) -> some View {
        Section {
            LabeledContent("Permission", value: permissionDescription)
                .accessibilityIdentifier("notificationPermissionRow")
            Toggle("Reminders", isOn: remindersEnabled)
            if model.notifications.authorization == .denied {
                Button("Turn On in iOS Settings") { model.notifications.openSystemSettings() }
            } else if model.notifications.authorization == .notDetermined && remindersEnabled.wrappedValue {
                Button("Allow Notifications") {
                    Task {
                        await model.notifications.requestAuthorizationIfNeeded()
                        model.refreshIntegrations()
                    }
                }
            }
            if let result = model.notifications.lastResult, result.status == .scheduled {
                LabeledContent("Scheduled Alerts", value: "\(result.scheduledCount)")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Reminders are set on individual periods in Schedule. Rhythm asks for permission the first time you add one.")
        }
    }

    private var dataSection: some View {
        Section {
            Button("Load School Bell Schedule…") { isChoosingBellScheduleLunch = true }
                .confirmationDialog("Which lunch do you have?", isPresented: $isChoosingBellScheduleLunch, titleVisibility: .visible) {
                    ForEach(LunchGroup.allCases) { lunch in
                        Button(lunch.displayName) {
                            model.applyBellSchedule(lunch: lunch)
                            alert = SettingsAlert(title: "Bell Schedule Added",
                                                  message: "Mon/Wed/Fri and Tue/Thu now follow the school bell schedule. Use Change This Date in Schedule for collaboration, minimum, and finals days.")
                        }
                    }
                } message: {
                    Text("Adds the school's schedules and assigns them to weekdays. Your other schedules are kept.")
                }
            Button("Export Timetable…") { prepareExport() }
            Button("Import Timetable…") { isImporting = true }
            if model.hasSampleData {
                Button("Remove Sample Schedule") { model.removeSample() }
            } else if !model.configuration.hasAnySchedule {
                Button("Add Sample Schedule") { model.insertSample() }
            }
            Button("Delete All Data", role: .destructive) { isConfirmingDeleteAll = true }
                .accessibilityIdentifier("deleteAllDataButton")
        } header: {
            Text("Data")
        } footer: {
            Text("Exports are versioned JSON files you can keep as a backup or move to another iPhone.")
        }
    }

    // MARK: Actions

    private var permissionDescription: String {
        switch model.notifications.authorization {
        case .authorized: "Allowed"
        case .provisional: "Delivered Quietly"
        case .denied: "Off"
        case .notDetermined: "Not Requested"
        }
    }

    private func prepareExport() {
        do {
            let data = try ExportImportCodec.encode(model.repository.makeExport())
            exportDocument = RhythmExportDocument(data: data)
        } catch {
            alert = SettingsAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            alert = SettingsAlert(title: "Import Failed", message: error.localizedDescription)
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                alert = SettingsAlert(title: "Import Failed", message: "Rhythm couldn’t read that file.")
                return
            }
            // Validation only decodes into temporary DTOs; nothing is written until confirmed.
            switch ExportImportCodec.decodeAndValidate(data) {
            case .success(let preview): importPreview = preview
            case .failure(let error): alert = SettingsAlert(title: "Can’t Import", message: error.message)
            }
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// A JSON file for `fileExporter`.
struct RhythmExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Shows what an import contains before replacing anything.
struct ImportPreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview
    let onFinish: (Bool) -> Void
    @State private var isConfirming = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Schedules", value: "\(preview.templateCount)")
                    LabeledContent("Periods", value: "\(preview.periodCount)")
                    LabeledContent("Date Changes", value: "\(preview.overrideCount)")
                    LabeledContent("Reminders", value: "\(preview.reminderCount)")
                    LabeledContent("Quicklinks", value: "\(preview.quicklinkCount)")
                } header: {
                    Text("This File Contains")
                } footer: {
                    Text("Exported \(preview.export.exportedAt.formatted(date: .abbreviated, time: .shortened)).")
                }
                Section {
                    ForEach(preview.export.templates) { template in
                        LabeledContent(template.name, value: "\(template.periods.count) periods")
                    }
                } header: {
                    Text("Schedules")
                }
                Section {
                    Button("Replace My Data", role: .destructive) { isConfirming = true }
                } footer: {
                    Text("Importing replaces all current schedules, date changes, reminders, and Quicklinks on this iPhone.")
                }
            }
            .navigationTitle("Import Timetable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Replace all Rhythm data?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Replace", role: .destructive) {
                    let success = model.importReplacingAll(preview.export)
                    if success { model.preferences.hasCompletedOnboarding = true }
                    dismiss()
                    onFinish(success)
                }
            }
        }
    }
}

/// How to have iOS start the Live Activity every school day with no taps, using a Shortcuts
/// automation that runs Rhythm's "Start Rhythm Live Activity" action.
private struct LiveActivityAutomationView: View {
    var body: some View {
        List {
            Section {
                Text("Rhythm schedules a Live Activity before each school day, and starts one whenever you open the app during school hours. For a start that never depends on opening Rhythm, add a Shortcuts automation once:")
            }
            Section("One-time setup") {
                Label("Open the Shortcuts app and tap Automation, then +.", systemImage: "1.circle")
                Label("Choose Time of Day, pick a time a few minutes before first bell (for example 8:20 AM), and select Weekly on school days.", systemImage: "2.circle")
                Label("Choose Run Immediately, then tap Next.", systemImage: "3.circle")
                Label("Search for Rhythm and choose Start Rhythm Live Activity. Tap Done.", systemImage: "4.circle")
            }
            Section {
                Text("You can add more times (for example right after lunch) to refresh it during the day. Rhythm runs the action in the background; it doesn't open the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Start Automatically")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Rhythm's privacy statement.
private struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("Rhythm keeps your schedule, reminders, and Quicklinks only on this iPhone. There’s no account, no server, no analytics, no ads, and no AI.")
                Text("Widgets and the Live Activity receive only period titles, categories, and times so they can display your day.")
                Text("Notifications are scheduled locally by iOS. Quicklinks are opened by iOS; Rhythm doesn’t see what happens in the app or website you open.")
            }
        }
        .navigationTitle("Privacy")
    }
}
