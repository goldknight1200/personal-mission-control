import Foundation
import MissionControlCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CalendarIntegrationView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: AppModel
    @State private var isAddingSubscription = false

    var body: some View {
        Form {
            Section {
                Picker(
                    "Calendar access",
                    selection: Binding(
                        get: {
                            model.snapshot.calendarIntegrationSettings.mode
                        },
                        set: { mode in
                            Task { await model.setCalendarMode(mode) }
                        }
                    )
                ) {
                    ForEach(CalendarIntegrationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                LabeledContent("Permission", value: statusText)

                if model.snapshot.calendarIntegrationSettings.mode
                    != .disabled {
                    if model.calendarAuthorizationState == .notDetermined
                        || model.calendarAuthorizationState == .limited {
                        Button("Review Calendar access") {
                            Task {
                                await model.setCalendarMode(
                                    model.snapshot
                                        .calendarIntegrationSettings.mode
                                )
                            }
                        }
                    } else if model.calendarAuthorizationState == .denied {
                        Button("Open system settings") {
                            openSystemSettings()
                        }
                    }

                    Button {
                        Task { await model.syncCalendar() }
                    } label: {
                        if model.isCalendarSyncing {
                            Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Sync now", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(
                        model.isCalendarSyncing
                            || model.calendarAuthorizationState
                                != .authorized
                    )
                }

                if let lastSync =
                    model.snapshot.calendarIntegrationSettings.lastSyncAt {
                    LabeledContent("Last sync") {
                        Text(lastSync, style: .relative)
                    }
                }
                if let error =
                    model.snapshot.calendarIntegrationSettings.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Apple Calendar")
            } footer: {
                Text(
                    "Permission is requested only when you choose an enabled mode. Imported events are exact, externally managed commitments and cannot be moved by the scheduler. Calendar access is optional."
                )
            }

            if model.snapshot.calendarIntegrationSettings.mode
                == .importAndSync,
               model.calendarAuthorizationState == .authorized {
                Section {
                    if model.availableCalendars.isEmpty {
                        ContentUnavailableView(
                            "No calendars available",
                            systemImage: "calendar.badge.exclamationmark"
                        )
                    } else {
                        ForEach(model.availableCalendars) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: {
                                        model.snapshot
                                            .calendarIntegrationSettings
                                            .importsCalendarIDs
                                            .contains(calendar.id)
                                    },
                                    set: {
                                        model.setCalendarImported(
                                            calendar.id,
                                            isImported: $0
                                        )
                                    }
                                )
                            ) {
                                VStack(alignment: .leading) {
                                    Text(calendar.title)
                                    Text(calendar.sourceTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Calendars to import")
                } footer: {
                    Text(
                        "Deselecting a calendar removes its imported planning items on the next successful sync. Nothing is deleted from Apple Calendar."
                    )
                }
            }

            if model.snapshot.calendarIntegrationSettings.mode
                != .disabled,
               model.calendarAuthorizationState == .authorized {
                Section {
                    Toggle(
                        model.snapshot.calendarIntegrationSettings.mode
                            == .createOnly
                            ? "Add new app commitments"
                            : "Create and update app commitments",
                        isOn: Binding(
                            get: {
                                model.snapshot.calendarIntegrationSettings
                                    .exportsLocalCommitments
                            },
                            set: {
                                model.updateCalendarExports(
                                    enabled: $0,
                                    destinationCalendarID:
                                        model.snapshot
                                        .calendarIntegrationSettings
                                        .destinationCalendarID
                                )
                            }
                        )
                    )

                    if model.snapshot.calendarIntegrationSettings
                        .exportsLocalCommitments,
                       model.snapshot.calendarIntegrationSettings.mode
                        == .importAndSync {
                        Picker(
                            "Destination",
                            selection: Binding<String?>(
                                get: {
                                    model.snapshot
                                        .calendarIntegrationSettings
                                        .destinationCalendarID
                                },
                                set: {
                                    model.updateCalendarExports(
                                        enabled: true,
                                        destinationCalendarID: $0
                                    )
                                }
                            )
                        ) {
                            Text("System default").tag(String?.none)
                            ForEach(
                                model.availableCalendars.filter(
                                    \.allowsContentModifications
                                )
                            ) {
                                Text($0.title).tag(String?.some($0.id))
                            }
                        }
                    }
                } header: {
                    Text("App-owned events")
                } footer: {
                    if model.snapshot.calendarIntegrationSettings.mode
                        == .createOnly {
                        Text(
                            "Write-only access can add events but cannot read, update, or delete even events this app created. Each local commitment is added once and keeps its local export marker to prevent duplicates. Choose Import and sync if you want later updates."
                        )
                    } else {
                        Text(
                            "Only events marked as created by Mission Control are updated or removed by the app. Known events that cannot be resolved are never recreated silently."
                        )
                    }
                }
            }

            Section {
                if model.snapshot.iCalSubscriptions.isEmpty {
                    ContentUnavailableView(
                        "No fixture subscriptions",
                        systemImage: "sportscourt"
                    )
                } else {
                    ForEach(model.snapshot.iCalSubscriptions) { subscription in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(
                                    subscription.title,
                                    systemImage: subscription
                                        .isFootballFixtures
                                        ? "soccerball"
                                        : "calendar"
                                )
                                Spacer()
                                if subscription.isEnabled {
                                    Button("Sync") {
                                        Task {
                                            await model.syncICalSubscription(
                                                subscription.id
                                            )
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Button(
                                    subscription.isEnabled ? "Pause" : "Resume"
                                ) {
                                    Task {
                                        await model
                                            .setICalSubscriptionEnabled(
                                                subscription.id,
                                                enabled:
                                                    !subscription.isEnabled
                                            )
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                            Text(subscription.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let error = subscription.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else if let lastSync = subscription.lastSyncAt {
                                HStack(spacing: 4) {
                                    Text("Updated")
                                    Text(lastSync, style: .relative)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                model.deleteICalSubscription(subscription.id)
                            }
                        }
                    }
                }
                Button {
                    isAddingSubscription = true
                } label: {
                    Label("Add iCal subscription", systemImage: "plus")
                }
            } header: {
                Text("External fixtures")
            } footer: {
                Text(
                    "HTTPS and webcal feeds are read only. Updates reuse each feed UID; cancellations and confirmed deletions remove only the matching local imported commitment."
                )
            }
        }
        .task {
            await model.preparePlatformIntegrations()
        }
        .sheet(isPresented: $isAddingSubscription) {
            ICalSubscriptionEditor { subscription in
                Task {
                    await model.saveICalSubscription(subscription)
                }
            }
        }
    }

    private var statusText: String {
        switch model.calendarAuthorizationState {
        case .disabled: "Off"
        case .notDetermined: "Not requested"
        case .requested: "Requested"
        case .authorized: "Allowed"
        case .limited: "Write only"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .unavailable: "Unavailable"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(
            string: UIApplication.openSettingsURLString
        ) else {
            return
        }
        openURL(url)
    }
}

private struct ICalSubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ICalSubscription) -> Void

    @State private var title = ""
    @State private var urlString = ""
    @State private var isFootballFixtures = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscription") {
                    TextField("Name", text: $title)
                    TextField(
                        "https://example.com/fixtures.ics",
                        text: $urlString
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    Toggle("Football fixtures", isOn: $isFootballFixtures)
                }
                Section {
                    Text(
                        "Adding this feed allows the app to download its events. It does not grant access to any account and does not make the local planner dependent on the feed."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("iCal subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(
                            ICalSubscription(
                                title: title.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ),
                                urlString: urlString.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ),
                                isFootballFixtures: isFootballFixtures
                            )
                        )
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || urlString.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }
            }
        }
    }
}

struct HealthIntegrationView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Use sleep duration",
                    isOn: Binding(
                        get: {
                            model.snapshot.healthIntegrationSettings
                                .sleepReadEnabled
                        },
                        set: { enabled in
                            Task {
                                await model.setHealthSleepEnabled(enabled)
                            }
                        }
                    )
                )
                LabeledContent("Permission", value: statusText)

                if model.snapshot.healthIntegrationSettings.sleepReadEnabled {
                    if model.healthAuthorizationState == .notDetermined {
                        Button("Review Health access") {
                            Task {
                                await model.setHealthSleepEnabled(true)
                            }
                        }
                    } else if model.healthAuthorizationState == .denied {
                        Button("Open system settings") {
                            openSystemSettings()
                        }
                    }
                    Button {
                        Task { await model.refreshHealthSleep() }
                    } label: {
                        Label(
                            model.isHealthRefreshing
                                ? "Refreshing"
                                : "Refresh sleep context",
                            systemImage: "bed.double"
                        )
                    }
                    .disabled(model.isHealthRefreshing)
                }

                if let error =
                    model.snapshot.healthIntegrationSettings.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("HealthKit sleep")
            } footer: {
                Text(
                    "The app requests read access only to Sleep Analysis after you enable this switch. HealthKit does not reveal whether read access was denied, so no data is handled as a normal fallback."
                )
            }

            Section("Morning recovery context") {
                if
                    let recovery = model.snapshot.recoveryContext,
                    recovery.sleepSource == .healthKitSleep,
                    let minutes = recovery.sleepDurationMinutes
                {
                    LabeledContent(
                        "Recent sleep",
                        value: "\(minutes / 60)h \(minutes % 60)m"
                    )
                    if let end = recovery.sleepWindowEnd {
                        LabeledContent("Sleep window ended") {
                            Text(end, style: .relative)
                        }
                    }
                } else {
                    Text(
                        "No HealthKit sleep context is available. Planning continues with local information."
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Label(
                    "Sleep duration is used only as planning and recovery context.",
                    systemImage: "shield.lefthalf.filled"
                )
                Text(
                    "It is not a diagnosis, readiness score, or medical recommendation. You can disable the integration at any time without losing core app features."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("Privacy and interpretation")
            }
        }
        .task {
            await model.preparePlatformIntegrations()
        }
    }

    private var statusText: String {
        switch model.healthAuthorizationState {
        case .disabled: "Off"
        case .notDetermined: "Not requested"
        case .requested: "Permission reviewed"
        case .authorized: "Allowed"
        case .limited: "Limited"
        case .denied: "Request failed"
        case .restricted: "Restricted"
        case .unavailable: "Unavailable"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(
            string: UIApplication.openSettingsURLString
        ) else {
            return
        }
        openURL(url)
    }
}

struct AIBehaviorSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: AIIntegrationSettings
    @State private var credential = ""
    @State private var didSaveCredential = false

    init(model: AppModel) {
        self.model = model
        _draft = State(
            initialValue: model.snapshot.aiIntegrationSettings
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use optional AI interpretation", isOn: $draft.isEnabled)
                    .onChange(of: draft.isEnabled) { _, enabled in
                        if enabled && draft.provider == .disabled {
                            draft.provider = .customJSON
                        }
                    }
                Picker("Provider adapter", selection: $draft.provider) {
                    ForEach(AIProviderSelection.allCases, id: \.self) {
                        provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .disabled(!draft.isEnabled)
            } footer: {
                Text(
                    "AI is optional. It proposes strict structured commands only; local validation, confirmation, persistence, conflict checks, and scheduling remain deterministic."
                )
            }

            if draft.isEnabled && draft.provider == .customJSON {
                Section {
                    TextField(
                        "HTTPS endpoint",
                        text: $draft.endpointURLString
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    TextField("Model identifier", text: $draft.modelIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(
                        model.hasAIProviderCredential
                            ? "Replace saved bearer credential"
                            : "Bearer credential",
                        text: $credential
                    )
                    .textContentType(.password)
                    if model.hasAIProviderCredential || didSaveCredential {
                        Label(
                            "Credential stored in this deviceâ€™s Keychain",
                            systemImage: "lock.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        Button(
                            "Remove saved credential",
                            role: .destructive
                        ) {
                            model.removeAIProviderCredential()
                            credential = ""
                            didSaveCredential = false
                        }
                    }
                } header: {
                    Text("Provider configuration")
                } footer: {
                    Text(
                        "The endpoint must accept the mission-control.command.v1 JSON envelope and return only the documented structured response. HTTP URLs, embedded credentials, query strings, and fragments are rejected. Secrets are never stored in the app snapshot or backup."
                    )
                }

                Section("Minimum context") {
                    Toggle(
                        "Share relevant mission titles",
                        isOn: $draft.sharesRelevantMissionTitles
                    )
                    Toggle(
                        "Share work-shift times when asked",
                        isOn:
                            $draft.sharesWorkShiftTimesWhenRelevant
                    )
                    LabeledContent(
                        "Never sent",
                        value: "Raw Health, full calendars, recordings"
                    )
                    Text(
                        "Only the confirmed text, reference date, time zone, up to six relevant mission references, and optionally bounded work-shift times can leave the device."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if let payload = model.lastAIRequestInspection {
                    Section("Last request this session") {
                        DisclosureGroup("Inspect exact minimized payload") {
                            ScrollView(.horizontal) {
                                Text(payload)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                        Text(
                            "This inspection is session-only and can contain the confirmed command text."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Save AI settings") {
                    model.updateAISettings(draft)
                    if !credential.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty {
                        didSaveCredential =
                            model.saveAIProviderCredential(credential)
                        if didSaveCredential {
                            credential = ""
                        }
                    }
                }
                .disabled(
                    draft.isEnabled
                        && (
                            draft.provider == .disabled
                                || !draft.isConfigured
                        )
                )
            } footer: {
                Text(
                    "If the configured provider is offline or invalid, supported commands use the deterministic local parser. Manual planning remains available."
                )
            }
        }
    }
}

struct PrivacyAndDataSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: PrivacySettings
    @State private var backupDocument: MissionControlBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingRestore: MissionControlBackup?
    @State private var isRestoreConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var errorMessage: String?

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.snapshot.privacySettings)
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Retain confirmed command text",
                    isOn: $draft.retainsCommandTranscripts
                )
                Picker(
                    "Time-zone behavior",
                    selection: $draft.timeZoneBehavior
                ) {
                    ForEach(TimeZoneBehavior.allCases, id: \.self) {
                        behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                Button("Save privacy settings") {
                    model.updatePrivacySettings(draft)
                    model.handleSignificantTimeChange()
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text(
                    "Turning transcript retention off immediately replaces existing stored raw and confirmed command text. Structured intents and mutation history remain for consistency and idempotency."
                )
            }

            Section("Backup") {
                Button {
                    do {
                        backupDocument = MissionControlBackupDocument(
                            data: try model.makeBackupData()
                        )
                        isExporting = true
                    } catch {
                        errorMessage =
                            "A valid backup could not be created."
                    }
                } label: {
                    Label("Export local backup", systemImage: "square.and.arrow.up")
                }
                Button {
                    isImporting = true
                } label: {
                    Label("Restore from backup", systemImage: "arrow.clockwise.icloud")
                }
                Text(
                    "A backup contains the full local snapshot, including schedule titles, retained command text, and configured feed URLs. It excludes Keychain credentials, raw Health samples, and audio."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(
                    "History records",
                    value: "\(model.datasetProfile.historyRecordCount)"
                )
                LabeledContent(
                    "Schedule blocks",
                    value: "\(model.datasetProfile.scheduleBlockCount)"
                )
                LabeledContent(
                    "Commands",
                    value: "\(model.datasetProfile.commandCount)"
                )
                LabeledContent(
                    "Workout sets",
                    value: "\(model.datasetProfile.workoutSetCount)"
                )
            } header: {
                Text("Dataset")
            } footer: {
                Text(
                    "These counts expose dataset growth without sending diagnostics. Large-history performance still requires profiling on supported devices."
                )
            }

            Section {
                Button("Delete all local app data", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
            } header: {
                Text("Delete")
            } footer: {
                Text(
                    "Deletion removes the local snapshot and AI credential, then creates an empty local profile. It does not delete events already exported to Apple Calendar or data owned by external providers."
                )
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "Mission-Control-Backup"
        ) { result in
            if case .failure = result {
                errorMessage = "The backup was not exported."
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            guard case let .success(url) = result else {
                errorMessage = "No backup was imported."
                return
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                pendingRestore = try model.reviewBackupData(
                    Data(contentsOf: url)
                )
                isRestoreConfirmationPresented = true
            } catch {
                errorMessage =
                    "This file is not a supported, valid Mission Control backup."
            }
        }
        .alert(
            "Restore this backup?",
            isPresented: $isRestoreConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {
                pendingRestore = nil
            }
            Button("Restore", role: .destructive) {
                if let pendingRestore {
                    _ = model.restoreBackup(pendingRestore)
                }
                pendingRestore = nil
            }
        } message: {
            Text(
                pendingRestore.map {
                    "Exported \($0.exportedAt.formatted()). Restoring replaces the current local snapshot, then reschedules notifications."
                } ?? "The backup is no longer available."
            )
        }
        .alert(
            "Delete all local app data?",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                _ = model.deleteAllLocalData()
                draft = model.snapshot.privacySettings
            }
        } message: {
            Text(
                "This cannot be undone unless you exported a backup. External provider data and previously exported calendar events are not deleted."
            )
        }
        .alert(
            "Data operation",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

struct MissionControlBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
