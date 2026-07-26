import Foundation

public struct WorkShiftBatchEntry: Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var payload: WorkShiftPayload
    public var existingCommitmentID: EntityID?
    public var warnings: [String]

    public init(
        id: EntityID = EntityID(),
        payload: WorkShiftPayload,
        existingCommitmentID: EntityID? = nil,
        warnings: [String] = []
    ) {
        self.id = id
        self.payload = payload
        self.existingCommitmentID = existingCommitmentID
        self.warnings = warnings
    }

    public var isChange: Bool {
        existingCommitmentID != nil
    }
}

public struct WorkShiftBatchParseResult: Equatable, Sendable {
    public var entries: [WorkShiftBatchEntry]
    public var unparsedInput: String?

    public init(
        entries: [WorkShiftBatchEntry],
        unparsedInput: String? = nil
    ) {
        self.entries = entries
        self.unparsedInput = unparsedInput
    }
}

public struct WorkShiftBatchParser: Sendable {
    public init() {}

    public func parse(
        _ text: String,
        title: String = "Work shift",
        location: String? = nil,
        referenceDate: Date,
        timeZoneIdentifier: String,
        existingCommitments: [FixedCommitment] = []
    ) -> WorkShiftBatchParseResult {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return WorkShiftBatchParseResult(entries: [])
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let pattern = #"(?i)(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[./]\d{1,2}(?:[./]\d{2,4})?|\d{1,2}\s+[a-z]+\s*(?:\d{4})?|[a-z]+\s+\d{1,2}(?:,?\s+\d{4})?)\s*(?:from\s*)?(\d{1,2}(?:(?::|\.)\d{2})?\s*(?:am|pm)?)\s*(?:to|[-–—])\s*(\d{1,2}(?:(?::|\.)\d{2})?\s*(?:am|pm)?)"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: []
        ) else {
            return WorkShiftBatchParseResult(
                entries: [],
                unparsedInput: source
            )
        }
        let range = NSRange(source.startIndex..., in: source)
        let matches = expression.matches(in: source, options: [], range: range)
        var entries: [WorkShiftBatchEntry] = []
        for match in matches {
            guard
                let dateRange = Range(match.range(at: 1), in: source),
                let startRange = Range(match.range(at: 2), in: source),
                let endRange = Range(match.range(at: 3), in: source)
            else {
                continue
            }
            let dateText = String(source[dateRange])
            let startText = String(source[startRange])
            let endText = String(source[endRange])
            guard
                let day = parseDay(
                    dateText,
                    referenceDate: referenceDate,
                    calendar: calendar
                ),
                let timeRange = parseTimeRange(
                    startText,
                    endText,
                    day: day,
                    calendar: calendar
                )
            else {
                continue
            }
            var warnings: [String] = []
            let matchingWork = existingCommitments
                .filter {
                    $0.category == .work
                        && calendar.isDate($0.start, inSameDayAs: timeRange.start)
                }
                .sorted(by: { $0.start < $1.start })
            let exactStart = matchingWork.first(where: {
                $0.start == timeRange.start
            })
            let inferredChange = exactStart ?? (
                matchingWork.count == 1
                    && overlaps(
                        timeRange.start,
                        timeRange.end,
                        matchingWork[0].start,
                        matchingWork[0].end
                    )
                ? matchingWork[0]
                : nil
            )
            if let inferredChange,
               inferredChange.start != timeRange.start
                    || inferredChange.end != timeRange.end {
                warnings.append(
                    "Changes the existing \(timeLabel(inferredChange.start, calendar: calendar))–\(timeLabel(inferredChange.end, calendar: calendar)) shift."
                )
            }
            let conflicting = existingCommitments.filter { commitment in
                commitment.id != inferredChange?.id
                    && overlaps(
                        timeRange.start,
                        timeRange.end,
                        commitment.start,
                        commitment.end
                    )
            }
            if !conflicting.isEmpty {
                warnings.append(
                    "Overlaps \(conflicting.count) existing fixed commitment\(conflicting.count == 1 ? "" : "s")."
                )
            }
            if !containsYear(dateText) {
                warnings.append("The year was inferred.")
            }
            entries.append(
                WorkShiftBatchEntry(
                    payload: WorkShiftPayload(
                        title: title.isEmpty ? "Work shift" : title,
                        start: timeRange.start,
                        end: timeRange.end,
                        location: location
                    ),
                    existingCommitmentID: inferredChange?.id,
                    warnings: warnings
                )
            )
        }

        for left in entries.indices {
            for right in entries.indices where right > left {
                if overlaps(
                    entries[left].payload.start,
                    entries[left].payload.end,
                    entries[right].payload.start,
                    entries[right].payload.end
                ) {
                    let warning = "Overlaps another shift in this batch."
                    if !entries[left].warnings.contains(warning) {
                        entries[left].warnings.append(warning)
                    }
                    if !entries[right].warnings.contains(warning) {
                        entries[right].warnings.append(warning)
                    }
                }
            }
        }
        return WorkShiftBatchParseResult(
            entries: entries.sorted(by: {
                $0.payload.start < $1.payload.start
            }),
            unparsedInput: entries.isEmpty ? source : nil
        )
    }

    private func parseDay(
        _ text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        if let components = numericDateComponents(cleaned) {
            var resolved = components
            let referenceYear = calendar.component(.year, from: referenceDate)
            if resolved.year == nil {
                resolved.year = referenceYear
            }
            guard var date = calendar.date(from: resolved) else { return nil }
            if !containsYear(cleaned),
               calendar.startOfDay(for: date)
                < calendar.startOfDay(for: referenceDate) {
                date = calendar.date(byAdding: .year, value: 1, to: date)
                    ?? date
            }
            return calendar.startOfDay(for: date)
        }

        let formats = containsYear(cleaned)
            ? ["d MMMM yyyy", "d MMM yyyy", "MMMM d yyyy", "MMM d yyyy"]
            : ["d MMMM", "d MMM", "MMMM d", "MMM d"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.defaultDate = referenceDate
            guard var date = formatter.date(from: cleaned) else { continue }
            if !containsYear(cleaned) {
                var components = calendar.dateComponents(
                    [.month, .day],
                    from: date
                )
                components.year = calendar.component(.year, from: referenceDate)
                guard let sameYear = calendar.date(from: components) else {
                    continue
                }
                date = sameYear
                if calendar.startOfDay(for: date)
                    < calendar.startOfDay(for: referenceDate) {
                    date = calendar.date(byAdding: .year, value: 1, to: date)
                        ?? date
                }
            }
            return calendar.startOfDay(for: date)
        }
        return nil
    }

    private func numericDateComponents(
        _ text: String
    ) -> DateComponents? {
        let separator: Character?
        if text.contains("-") {
            separator = "-"
        } else if text.contains(".") {
            separator = "."
        } else if text.contains("/") {
            separator = "/"
        } else {
            separator = nil
        }
        guard let separator else { return nil }
        let values = text.split(separator: separator).compactMap {
            Int($0)
        }
        guard values.count == 2 || values.count == 3 else { return nil }
        if values[0] > 31, values.count == 3 {
            return DateComponents(
                year: values[0],
                month: values[1],
                day: values[2]
            )
        }
        let year: Int?
        if values.count == 3 {
            year = values[2] < 100 ? 2_000 + values[2] : values[2]
        } else {
            year = nil
        }
        return DateComponents(year: year, month: values[1], day: values[0])
    }

    private func parseTimeRange(
        _ startText: String,
        _ endText: String,
        day: Date,
        calendar: Calendar
    ) -> DateInterval? {
        guard
            let startParts = timeParts(startText),
            let endParts = timeParts(endText)
        else {
            return nil
        }
        var startHour = normalizedHour(
            startParts.hour,
            meridiem: startParts.meridiem
        )
        var endHour = normalizedHour(
            endParts.hour,
            meridiem: endParts.meridiem
        )
        guard startHour >= 0, startHour <= 23, endHour >= 0, endHour <= 23 else {
            return nil
        }
        var endDayOffset = 0
        let startMinutes = startHour * 60 + startParts.minute
        var endMinutes = endHour * 60 + endParts.minute
        if endMinutes <= startMinutes {
            if startParts.meridiem == nil,
               endParts.meridiem == nil,
               startParts.hour <= 12,
               endParts.hour <= 12,
               endHour + 12 <= 23 {
                endHour += 12
                endMinutes = endHour * 60 + endParts.minute
            }
            if endMinutes <= startMinutes {
                endDayOffset = 1
            }
        }
        guard
            let start = calendar.date(
                byAdding: .minute,
                value: startMinutes,
                to: day
            ),
            let endDay = calendar.date(
                byAdding: .day,
                value: endDayOffset,
                to: day
            ),
            let end = calendar.date(
                byAdding: .minute,
                value: endMinutes,
                to: endDay
            ),
            end > start
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func timeParts(
        _ text: String
    ) -> (hour: Int, minute: Int, meridiem: String?)? {
        let cleaned = text
            .lowercased()
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: " ", with: "")
        let meridiem: String?
        let numeric: String
        if cleaned.hasSuffix("am") || cleaned.hasSuffix("pm") {
            meridiem = String(cleaned.suffix(2))
            numeric = String(cleaned.dropLast(2))
        } else {
            meridiem = nil
            numeric = cleaned
        }
        let pieces = numeric.split(separator: ":")
        guard let hour = pieces.first.flatMap({ Int($0) }) else {
            return nil
        }
        let minute = pieces.count > 1 ? Int(pieces[1]) ?? -1 : 0
        guard minute >= 0, minute < 60 else { return nil }
        if meridiem != nil && !(1...12).contains(hour) {
            return nil
        }
        return (hour, minute, meridiem)
    }

    private func normalizedHour(
        _ hour: Int,
        meridiem: String?
    ) -> Int {
        switch meridiem {
        case "am": hour == 12 ? 0 : hour
        case "pm": hour == 12 ? 12 : hour + 12
        default: hour
        }
    }

    private func containsYear(_ text: String) -> Bool {
        text.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil
    }

    private func overlaps(
        _ leftStart: Date,
        _ leftEnd: Date,
        _ rightStart: Date,
        _ rightEnd: Date
    ) -> Bool {
        leftStart < rightEnd && rightStart < leftEnd
    }

    private func timeLabel(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}

public struct ProjectWeeklyProgress: Equatable, Sendable {
    public var projectID: EntityID
    public var weekStart: Date
    public var weekEnd: Date
    public var targetMinutes: Int
    public var scheduledMinutes: Int
    public var actualMinutes: Int

    public init(
        projectID: EntityID,
        weekStart: Date,
        weekEnd: Date,
        targetMinutes: Int,
        scheduledMinutes: Int,
        actualMinutes: Int
    ) {
        self.projectID = projectID
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.targetMinutes = targetMinutes
        self.scheduledMinutes = scheduledMinutes
        self.actualMinutes = actualMinutes
    }
}

public struct ProjectActivityReassessment: Equatable, Identifiable, Sendable {
    public var projectID: EntityID
    public var projectTitle: String
    public var recentSkipCount: Int

    public var id: EntityID { projectID }

    public init(
        projectID: EntityID,
        projectTitle: String,
        recentSkipCount: Int
    ) {
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.recentSkipCount = recentSkipCount
    }
}

public enum ProjectPlanningAnalytics {
    public static func weeklyProgress(
        projectID: EntityID,
        snapshot: MissionControlSnapshot,
        containing date: Date
    ) -> ProjectWeeklyProgress? {
        guard let project = snapshot.projects.first(where: {
            $0.id == projectID
        }) else {
            return nil
        }
        let calendar = configuredCalendar(snapshot.profile.timeZoneIdentifier)
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(
                start: calendar.startOfDay(for: date),
                duration: 7 * 86_400
            )
        let missionIDs = Set(
            snapshot.missions.filter { $0.projectID == projectID }.map(\.id)
        )
        let scheduled = snapshot.scheduleBlocks
            .filter {
                $0.kind == .mission
                    && $0.start < interval.end
                    && $0.end > interval.start
                    && ($0.missionID.map(missionIDs.contains) ?? false)
            }
            .map(\.durationMinutes)
            .reduce(0, +)
        let actual = snapshot.completions
            .filter {
                $0.completedAt >= interval.start
                    && $0.completedAt < interval.end
                    && missionIDs.contains($0.missionID)
                    && ($0.status == .completed || $0.status == .partial)
            }
            .map(\.actualDurationMinutes)
            .reduce(0, +)
        return ProjectWeeklyProgress(
            projectID: projectID,
            weekStart: interval.start,
            weekEnd: interval.end,
            targetMinutes: project.weeklyPlannedMinutes,
            scheduledMinutes: scheduled,
            actualMinutes: actual
        )
    }

    public static func reassessment(
        projectID: EntityID,
        snapshot: MissionControlSnapshot,
        at date: Date,
        threshold: Int = 3,
        lookbackDays: Int = 28
    ) -> ProjectActivityReassessment? {
        guard
            threshold > 0,
            let project = snapshot.projects.first(where: {
                $0.id == projectID
            }),
            project.status != .backlog
        else {
            return nil
        }
        let calendar = configuredCalendar(snapshot.profile.timeZoneIdentifier)
        let lookback = calendar.date(
            byAdding: .day,
            value: -max(lookbackDays, 1),
            to: date
        ) ?? date.addingTimeInterval(-28 * 86_400)
        let boundary = max(lookback, project.lastActiveReviewAt ?? .distantPast)
        let missionIDs = Set(
            snapshot.missions.filter { $0.projectID == projectID }.map(\.id)
        )
        let skips = snapshot.completions.filter {
            $0.status == .skipped
                && $0.completedAt >= boundary
                && $0.completedAt <= date
                && missionIDs.contains($0.missionID)
        }.count
        guard skips >= threshold else { return nil }
        return ProjectActivityReassessment(
            projectID: projectID,
            projectTitle: project.title,
            recentSkipCount: skips
        )
    }

    private static func configuredCalendar(
        _ timeZoneIdentifier: String
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }
}
