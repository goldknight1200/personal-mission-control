import Foundation
import MissionControlCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PlanView: View {
    enum RangeOption: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    let openMenu: () -> Void

    @State private var selectedRange: RangeOption = .day
    @State private var selectedDay = Date()
    @State private var selectedMonth = Date()
    @State private var selectedMonthDay: Date?
    @State private var showExplanations = false
    @State private var showShiftEntry = false
    @State private var editingBlock: ScheduleBlock?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Plan range", selection: $selectedRange) {
                    ForEach(RangeOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if !model.snapshot.schedulingConflicts.isEmpty {
                    Button {
                        showExplanations = true
                    } label: {
                        Label(
                            "\(model.snapshot.schedulingConflicts.count) planning conflict\(model.snapshot.schedulingConflicts.count == 1 ? "" : "s")",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }

                switch selectedRange {
                case .day:
                    dayPlan
                case .week:
                    weekPlan
                case .month:
                    monthPlan
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showShiftEntry = true
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                    }
                    .accessibilityLabel("Enter work shifts")
                    Button {
                        showExplanations = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Planning explanations")
                    ScreenMenuButton(action: openMenu)
                }
            }
        }
        .sheet(isPresented: $showExplanations) {
            PlanningExplanationsView(model: model)
        }
        .sheet(isPresented: $showShiftEntry) {
            WorkShiftEntryView(model: model)
        }
        .sheet(item: $editingBlock) { block in
            ScheduleAdjustmentView(model: model, block: block)
        }
        .onChange(of: selectedMonth) { _, month in
            if let selectedMonthDay,
               !localCalendar.isDate(
                   selectedMonthDay,
                   equalTo: month,
                   toGranularity: .month
               ) {
                self.selectedMonthDay = nil
            }
        }
    }

    private var dayPlan: some View {
        VStack(spacing: 0) {
            DateNavigator(
                date: $selectedDay,
                calendar: localCalendar,
                component: .day
            )
            let dayBlocks = inspectableBlocks(on: selectedDay)
            if dayBlocks.isEmpty {
                ContentUnavailableView(
                    "Open day",
                    systemImage: "calendar.badge.clock",
                    description: Text("No planned blocks or fixed commitments.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(dayBlocks) { block in
                    planRow(block)
                }
                .listStyle(.plain)
            }
        }
    }

    private var weekPlan: some View {
        VStack(spacing: 0) {
            DateNavigator(
                date: $selectedDay,
                calendar: localCalendar,
                component: .weekOfYear
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(weekDays, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                selectedDay = day
                                selectedRange = .day
                            } label: {
                                HStack {
                                    Text(dayLabel(day))
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)

                            let dayBlocks = inspectableBlocks(on: day)
                            if dayBlocks.isEmpty {
                                Text("Open day")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .missionControlCard()
                            } else {
                                ForEach(dayBlocks) { block in
                                    planRow(block)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .background(
                                            RoundedRectangle(
                                                cornerRadius: 16,
                                                style: .continuous
                                            )
                                            .fill(Color.primary.opacity(0.04))
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
    }

    private var monthPlan: some View {
        ScrollView {
            VStack(spacing: 14) {
                DateNavigator(
                    date: $selectedMonth,
                    calendar: localCalendar,
                    component: .month
                )
                HStack {
                    ForEach(weekdayHeaders, id: \.self) { header in
                        Text(header)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 6),
                        count: 7
                    ),
                    spacing: 6
                ) {
                    ForEach(Array(monthCells.enumerated()), id: \.offset) {
                        cell in
                        let day = cell.element
                        if let day {
                            let blocks = inspectableBlocks(on: day)
                            Button {
                                selectedMonthDay = day
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(
                                        String(
                                            localCalendar.component(
                                                .day,
                                                from: day
                                            )
                                        )
                                    )
                                    .font(.subheadline.weight(
                                        localCalendar.isDateInToday(day)
                                            ? .bold
                                            : .regular
                                    ))
                                    HStack(spacing: 3) {
                                        ForEach(
                                            Array(blocks.prefix(3)),
                                            id: \.id
                                        ) { block in
                                            Circle()
                                                .fill(
                                                    model.snapshot.profile.color(
                                                        for: block.category
                                                    )
                                                )
                                                .frame(width: 5, height: 5)
                                        }
                                    }
                                    Text(
                                        blocks.isEmpty
                                            ? "Open"
                                            : "\(blocks.count) block\(blocks.count == 1 ? "" : "s")"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 58,
                                    alignment: .topLeading
                                )
                                .padding(7)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            selectedMonthDay.map {
                                                localCalendar.isDate(
                                                    $0,
                                                    inSameDayAs: day
                                                )
                                            } == true
                                                ? Color.accentColor.opacity(0.14)
                                                : Color.primary.opacity(0.04)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(height: 72)
                        }
                    }
                }
                .padding(.horizontal, 12)

                if let selectedMonthDay {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayLabel(selectedMonthDay))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let blocks = inspectableBlocks(on: selectedMonthDay)
                        if blocks.isEmpty {
                            Text("No planned blocks or fixed commitments.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .missionControlCard()
                        } else {
                            ForEach(blocks) { block in
                                planRow(block)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.primary.opacity(0.04))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func planRow(_ block: ScheduleBlock) -> some View {
        if canAdjust(block) {
            Button {
                editingBlock = block
            } label: {
                PlanBlockRow(
                    block: block,
                    profile: model.snapshot.profile,
                    isManual: model.snapshot.manualScheduleAdjustments
                        .contains(where: { $0.block.id == block.id })
                )
            }
            .buttonStyle(.plain)
        } else {
            PlanBlockRow(
                block: block,
                profile: model.snapshot.profile,
                isManual: false
            )
        }
    }

    private var weekDays: [Date] {
        let interval = localCalendar.dateInterval(
            of: .weekOfYear,
            for: selectedDay
        )
        let start = interval?.start ?? localCalendar.startOfDay(for: selectedDay)
        return (0..<7).compactMap {
            localCalendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var monthCells: [Date?] {
        guard
            let month = localCalendar.dateInterval(
                of: .month,
                for: selectedMonth
            ),
            let dayRange = localCalendar.range(
                of: .day,
                in: .month,
                for: month.start
            )
        else {
            return []
        }
        let firstWeekday = localCalendar.component(
            .weekday,
            from: month.start
        )
        let leading = (firstWeekday - localCalendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: leading)
        cells.append(
            contentsOf: dayRange.compactMap { day -> Date? in
                localCalendar.date(
                    byAdding: .day,
                    value: day - 1,
                    to: month.start
                )
            }
        )
        while !cells.count.isMultiple(of: 7) {
            cells.append(nil)
        }
        return cells
    }

    private var weekdayHeaders: [String] {
        let symbols = localCalendar.shortStandaloneWeekdaySymbols
        let offset = max(localCalendar.firstWeekday - 1, 0)
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    private func inspectableBlocks(on day: Date) -> [ScheduleBlock] {
        let start = localCalendar.startOfDay(for: day)
        let end = localCalendar.date(
            byAdding: .day,
            value: 1,
            to: start
        ) ?? start.addingTimeInterval(86_400)
        var result = model.snapshot.scheduleBlocks.filter {
            $0.start < end && $0.end > start
        }
        let represented = Set(result.compactMap(\.fixedCommitmentID))
        for commitment in model.snapshot.fixedCommitments
        where commitment.start < end
            && commitment.end > start
            && !represented.contains(commitment.id) {
            result.append(
                ScheduleBlock(
                    id: commitment.id,
                    fixedCommitmentID: commitment.id,
                    title: commitment.title,
                    category: commitment.category,
                    kind: .fixedCommitment,
                    rigidity: .fixed,
                    start: commitment.start,
                    end: commitment.end,
                    isImmutable: commitment.isExternallyManaged
                )
            )
        }
        return result.sorted(by: {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        })
    }

    private func canAdjust(_ block: ScheduleBlock) -> Bool {
        guard !block.isImmutable else { return false }
        if block.missionID != nil { return true }
        if let commitmentID = block.fixedCommitmentID {
            return model.snapshot.fixedCommitments.contains(where: {
                $0.id == commitmentID && !$0.isExternallyManaged
            })
        }
        return false
    }

    private var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: model.snapshot.profile.timeZoneIdentifier
        ) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = localCalendar
        formatter.timeZone = localCalendar.timeZone
        formatter.dateFormat = "EEEE, d MMM"
        return formatter.string(from: date)
    }
}

private struct DateNavigator: View {
    @Binding var date: Date
    let calendar: Calendar
    let component: Calendar.Component

    var body: some View {
        HStack {
            Button {
                date = calendar.date(
                    byAdding: component,
                    value: -1,
                    to: date
                ) ?? date
            } label: {
                Image(systemName: "chevron.left")
            }
            DatePicker(
                "",
                selection: $date,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            Button {
                date = calendar.date(
                    byAdding: component,
                    value: 1,
                    to: date
                ) ?? date
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}

private struct PlanBlockRow: View {
    let block: ScheduleBlock
    let profile: UserProfile
    let isManual: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    isQuiet
                        ? Color.secondary.opacity(0.4)
                        : profile.color(for: block.category)
                )
                .frame(width: 4, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(block.title)
                        .foregroundStyle(
                            isQuiet ? Color.secondary : Color.primary
                        )
                    if isManual {
                        Text("Manual")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                }
                Text(block.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MissionControlFormatters.timeRange(block, profile: profile))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var isQuiet: Bool {
        block.kind.isTransition
            || block.kind == .sleep
            || block.kind == .freeTime
    }
}

private struct ScheduleAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let block: ScheduleBlock

    @State private var start: Date
    @State private var end: Date

    init(model: AppModel, block: ScheduleBlock) {
        self.model = model
        self.block = block
        _start = State(initialValue: block.start)
        _end = State(initialValue: block.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(block.title) {
                    DatePicker("Start", selection: $start)
                    DatePicker("End", selection: $end)
                    if end <= start {
                        Label(
                            "End must be after start.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }
                Section {
                    Text(
                        block.fixedCommitmentID == nil
                            ? "Saving creates a user-controlled occurrence override. The rest of the plan is regenerated around it."
                            : "Saving changes this user-owned fixed commitment and replans the affected day."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if model.snapshot.manualScheduleAdjustments.contains(
                    where: { $0.block.id == block.id }
                ) {
                    Section {
                        Button("Return to automatic planning") {
                            model.returnScheduleBlockToAutomatic(block.id)
                            dismiss()
                        }
                    }
                }
                if let commitmentID = block.fixedCommitmentID,
                   model.snapshot.fixedCommitments.contains(where: {
                       $0.id == commitmentID && !$0.isExternallyManaged
                   }) {
                    Section {
                        Button("Delete commitment", role: .destructive) {
                            model.deleteFixedCommitment(commitmentID)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Adjust block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.moveScheduleBlock(
                            block.id,
                            start: start,
                            end: end
                        )
                        dismiss()
                    }
                    .disabled(end <= start)
                }
            }
        }
    }
}

@MainActor
private struct WorkShiftEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @StateObject private var capture = VoiceCaptureViewModel(
        service: AppleSpeechTranscriptionService()
    )

    @State private var title = "Work shift"
    @State private var location = ""
    @State private var input = ""
    @State private var result: WorkShiftBatchParseResult?
    @State private var selectedIDs = Set<EntityID>()
    @State private var selectedRotaPhoto: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var isImportingImage = false
    @State private var imageAmbiguities: [String] = []
    @State private var imageImportError: String?

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    confirmationSections(result)
                } else {
                    entrySections
                }
            }
            .navigationTitle(result == nil ? "Enter monthly shifts" : "Confirm shifts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Back") {
                        if result == nil {
                            dismiss()
                        } else {
                            self.result = nil
                            selectedIDs.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let result {
                        Button("Save \(selectedIDs.count)") {
                            let entries = result.entries.filter {
                                selectedIDs.contains($0.id)
                            }
                            model.applyWorkShifts(entries)
                            dismiss()
                        }
                        .disabled(selectedIDs.isEmpty)
                    } else {
                        Button("Review", action: parse)
                            .disabled(input.trimmed.isEmpty)
                    }
                }
            }
        }
        .onChange(of: capture.isReviewPresented) { _, isPresented in
            guard isPresented else { return }
            input = capture.confirmedTranscript
            capture.dismissReview()
        }
        .alert(
            "Voice capture",
            isPresented: Binding(
                get: { capture.alertMessage != nil },
                set: { if !$0 { capture.clearAlert() } }
            )
        ) {
            Button("OK", role: .cancel) {
                capture.clearAlert()
            }
        } message: {
            Text(capture.alertMessage ?? "")
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image]
        ) { result in
            switch result {
            case let .success(url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let data = try Data(contentsOf: url)
                    Task { await reviewImage(data) }
                } catch {
                    imageImportError =
                        "The selected file could not be read. Text and voice entry are still available."
                }
            case .failure:
                imageImportError =
                    "The file was not imported. Text and voice entry are still available."
            }
        }
        .onChange(of: selectedRotaPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(
                    type: Data.self
                ) else {
                    imageImportError =
                        "The selected photo could not be read. Text and voice entry are still available."
                    return
                }
                await reviewImage(data)
            }
        }
    }

    @ViewBuilder
    private var entrySections: some View {
        Section("Shift details") {
            TextField("Title", text: $title)
            TextField("Location (optional)", text: $location)
            Text("Use “Supermarket shift” or a supermarket location when shopping can be combined after work.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Section("Dates and times") {
            TextEditor(text: $input)
                .frame(minHeight: 140)
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("3 Aug 09:00–17:00\n5 Aug 10–18; 8 Aug 12pm–8pm")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            Label(
                "Enter several ranges in one message. Missing years use the next matching date.",
                systemImage: "text.alignleft"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Section("Voice") {
            Label(
                capture.statusMessage ?? "Press and hold to dictate all shifts",
                systemImage: capture.isRecording ? "waveform" : "mic.fill"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(capture.isRecording ? Color.red : Color.accentColor)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        capture.pressBegan(
                            localeIdentifier: Locale.autoupdatingCurrent.identifier
                        )
                    }
                    .onEnded { _ in
                        capture.pressEnded()
                    }
            )
            Text("The transcript returns here for editing. Nothing is saved until the confirmation list is approved.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Section("Rota image (optional)") {
            PhotosPicker(
                selection: $selectedRotaPhoto,
                matching: .images
            ) {
                Label(
                    "Choose photo",
                    systemImage: "photo.badge.plus"
                )
            }
            Button {
                isFileImporterPresented = true
            } label: {
                Label("Choose image file", systemImage: "doc.badge.plus")
            }
            if isImportingImage {
                ProgressView("Reading text on deviceâ€¦")
            }
            if let imageImportError {
                Label(
                    imageImportError,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            Text(
                "The selected image is processed on device. Detected ranges are never saved until you select and confirm them; unclear text is shown instead of guessed."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func confirmationSections(
        _ result: WorkShiftBatchParseResult
    ) -> some View {
        if !imageAmbiguities.isEmpty {
            Section("Needs review") {
                ForEach(imageAmbiguities, id: \.self) { ambiguity in
                    Label(
                        ambiguity,
                        systemImage: "questionmark.diamond"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }
        }
        if result.entries.isEmpty {
            Section {
                ContentUnavailableView(
                    "No shifts found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(
                        "Use a date followed by a range, such as 3 Aug 09:00–17:00."
                    )
                )
            }
        } else {
            Section {
                Text("Review every range. Conflicts are disclosed but remain yours to confirm; the scheduler preserves fixed commitments and reports unresolved overlap.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Confirmation list") {
                ForEach(result.entries) { entry in
                    Button {
                        if selectedIDs.contains(entry.id) {
                            selectedIDs.remove(entry.id)
                        } else {
                            selectedIDs.insert(entry.id)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(
                                systemName: selectedIDs.contains(entry.id)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                selectedIDs.contains(entry.id)
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.payload.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(
                                    entry.payload.start.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                    + " – "
                                    + entry.payload.end.formatted(
                                        date: .omitted,
                                        time: .shortened
                                    )
                                )
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                if entry.isChange {
                                    Label(
                                        "Updates an existing shift",
                                        systemImage: "arrow.triangle.2.circlepath"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.indigo)
                                }
                                ForEach(entry.warnings, id: \.self) { warning in
                                    Label(
                                        warning,
                                        systemImage: "exclamationmark.triangle"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func parse() {
        let parsed = WorkShiftBatchParser().parse(
            input,
            title: title.trimmed.isEmpty ? "Work shift" : title.trimmed,
            location: location.trimmed.isEmpty ? nil : location.trimmed,
            referenceDate: Date(),
            timeZoneIdentifier: model.snapshot.profile.timeZoneIdentifier,
            existingCommitments: model.snapshot.fixedCommitments
        )
        result = parsed
        selectedIDs = Set(parsed.entries.map(\.id))
        imageAmbiguities = []
        imageImportError = nil
    }

    @MainActor
    private func reviewImage(_ data: Data) async {
        isImportingImage = true
        imageImportError = nil
        defer { isImportingImage = false }
        do {
            let review = try await model.reviewWorkShiftImage(
                data,
                title: title.trimmed.isEmpty ? "Work shift" : title.trimmed,
                location: location.trimmed.isEmpty ? nil : location.trimmed
            )
            input = review.recognizedText
            result = review.parseResult
            imageAmbiguities = review.ambiguities
            selectedIDs.removeAll()
        } catch {
            imageImportError =
                "No reliable shifts were extracted. Use the existing text or voice flow instead."
        }
    }
}

private struct PlanningExplanationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let metadata = model.snapshot.schedulingPlanMetadata {
                    Section("Plan") {
                        LabeledContent("Generated") {
                            Text(metadata.generatedAt, style: .time)
                        }
                        LabeledContent(
                            "Horizon",
                            value: "\(model.snapshot.profile.planningPolicy.planningHorizonDays) days"
                        )
                        LabeledContent(
                            "Flexible grid",
                            value: "\(metadata.gridMinutes) minutes"
                        )
                        LabeledContent(
                            "Manual overrides",
                            value: "\(model.snapshot.manualScheduleAdjustments.count)"
                        )
                    }
                }

                if !model.snapshot.schedulingConflicts.isEmpty {
                    Section("Conflicts requiring attention") {
                        ForEach(model.snapshot.schedulingConflicts) { conflict in
                            VStack(alignment: .leading, spacing: 5) {
                                Label(
                                    conflict.title,
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.headline)
                                .foregroundStyle(.orange)
                                Text(conflict.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Decisions") {
                    ForEach(model.snapshot.schedulingDecisions) { decision in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(decision.title)
                                .font(.headline)
                            Text(decision.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(decision.rule.rawValue)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Why this plan?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Regenerate") {
                        model.regeneratePlan()
                    }
                }
            }
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
