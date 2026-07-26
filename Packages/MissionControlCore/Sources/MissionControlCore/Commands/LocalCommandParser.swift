import Foundation

public struct LocalCommandParser: CommandInterpreting {
    public init() {}

    public func interpret(
        rawTranscript: String,
        confirmedTranscript: String,
        context: CommandContext
    ) -> StructuredCommand {
        let source = normalizeApostrophes(confirmedTranscript)
        let lowercased = source.lowercased()
        var intents: [DetectedIntent] = []
        var entities: [ExtractedEntity] = []
        var mutations: [ProposedMutation] = []
        var warnings: [CommandWarning] = []
        var confirmationReasons: [String] = []
        var affectedStarts: [Date] = []
        var affectedEnds: [Date] = []
        var parsedShifts: [WorkShiftPayload] = []

        if lowercased.contains("woke up late") && lowercased.contains("replan") {
            intents.append(DetectedIntent(kind: .replanDay, confidence: 0.99))
            mutations.append(.requestDayReplan(availableFrom: context.referenceDate))
            warnings.append(
                CommandWarning(
                    severity: .consequence,
                    message: "Replanning can move several remaining blocks. Completed history stays frozen."
                )
            )
            confirmationReasons.append("This can change a large part of today’s remaining schedule.")
            affectedStarts.append(context.referenceDate)
            affectedEnds.append(endOfDay(for: context.referenceDate, context: context))
        }

        if let match = firstMatch(
            #"already started (?:the )?(.+?) (\d+) minutes? ago"#,
            in: source
        ), match.count == 3, let minutes = Int(match[2]) {
            let missionName = cleaned(match[1])
            intents.append(DetectedIntent(kind: .markMissionStarted, confidence: 0.98))
            entities.append(
                ExtractedEntity(kind: .mission, value: missionName)
            )
            entities.append(
                ExtractedEntity(
                    kind: .durationMinutes,
                    value: match[2],
                    integerValue: minutes
                )
            )

            if let mission = resolvedMission(named: missionName, context: context, warnings: &warnings) {
                mutations.append(
                    .markMissionStarted(
                        missionID: mission.id,
                        missionName: mission.title,
                        minutesAgo: minutes
                    )
                )
                if let start = mission.scheduledStart { affectedStarts.append(start) }
                if let end = mission.scheduledEnd { affectedEnds.append(end) }
            }
        }

        if let match = firstMatch(
            #"add (.+?) to (?:my )?today(?: list)?(?:[.!]|$)"#,
            in: source
        ), match.count == 2 {
            let title = cleaned(match[1])
            intents.append(DetectedIntent(kind: .addTodayItem, confidence: 0.99))
            entities.append(ExtractedEntity(kind: .checklistItem, value: title))
            mutations.append(.addChecklistItem(kind: .today, title: title))
        }

        if let match = firstMatch(
            #"add (.+?) to (?:my )?shopping list(?:[.!]|$)"#,
            in: source
        ), match.count == 2 {
            let title = cleaned(match[1])
            intents.append(DetectedIntent(kind: .addShoppingItem, confidence: 0.99))
            entities.append(ExtractedEntity(kind: .checklistItem, value: title))
            mutations.append(.addChecklistItem(kind: .shopping, title: title))
        }

        if let match = firstMatch(
            #"finished (?:the )?last (.+?)(?:[.!]|$)"#,
            in: source
        ), match.count == 2 {
            let itemName = cleaned(match[1])
            intents.append(DetectedIntent(kind: .emptyInventoryItem, confidence: 0.97))
            entities.append(ExtractedEntity(kind: .inventoryItem, value: itemName))
            mutations.append(.markInventoryEmpty(name: itemName))
        }

        if let match = firstMatch(
            #"(?:we have|i have|there are) (\d+) meals? (?:of )?(.+?) (?:left|remaining)(?:[.!]|$)"#,
            in: source
        ), match.count == 3, let meals = Int(match[1]) {
            let itemName = cleaned(match[2])
            intents.append(
                DetectedIntent(kind: .updateInventory, confidence: 0.98)
            )
            entities.append(
                ExtractedEntity(
                    kind: .inventoryItem,
                    value: itemName
                )
            )
            entities.append(
                ExtractedEntity(
                    kind: .inventoryQuantity,
                    value: match[1],
                    normalizedValue: "\(meals)",
                    integerValue: meals
                )
            )
            mutations.append(
                .updateInventory(
                    InventoryUpdatePayload(
                        name: itemName,
                        state: meals == 0 ? .empty : meals <= 1 ? .low : .available,
                        mealsRemaining: meals
                    )
                )
            )
        }

        if let match = firstMatch(
            #"(.+?) is (low|out|empty)(?:[.!]|$)"#,
            in: source
        ), match.count == 3 {
            let itemName = cleaned(match[1])
            let state: InventoryState =
                match[2].lowercased() == "low" ? .low : .empty
            intents.append(
                DetectedIntent(kind: .updateInventory, confidence: 0.97)
            )
            entities.append(
                ExtractedEntity(kind: .inventoryItem, value: itemName)
            )
            mutations.append(
                .updateInventory(
                    InventoryUpdatePayload(name: itemName, state: state)
                )
            )
        }

        if let match = firstMatch(
            #"set (.+?) to (\d+(?:\.\d+)?) ([a-zA-Z]+)(?:[.!]|$)"#,
            in: source
        ), match.count == 4, let quantity = Double(match[2]) {
            let itemName = cleaned(match[1])
            intents.append(
                DetectedIntent(kind: .updateInventory, confidence: 0.96)
            )
            entities.append(
                ExtractedEntity(kind: .inventoryItem, value: itemName)
            )
            mutations.append(
                .updateInventory(
                    InventoryUpdatePayload(
                        name: itemName,
                        state: quantity == 0 ? .empty : .available,
                        exactQuantity: quantity,
                        quantityUnit: cleaned(match[3])
                    )
                )
            )
        }

        if let match = firstMatch(
            #"(?:i(?:'m| am) )?(?:skipping|skip|not going to) (?:the )?(.+?)(?: today)?(?:[.!]|$)"#,
            in: source
        ), match.count == 2 {
            let missionName = cleaned(match[1])
            intents.append(DetectedIntent(kind: .skipMission, confidence: 0.97))
            entities.append(ExtractedEntity(kind: .mission, value: missionName))

            if let mission = resolvedMission(named: missionName, context: context, warnings: &warnings) {
                mutations.append(.skipMission(missionID: mission.id, missionName: mission.title))
                if mission.rigidity == .protected || mission.rigidity == .fixed {
                    warnings.append(
                        CommandWarning(
                            severity: .consequence,
                            message: "Skipping \(mission.title) breaks a protected commitment and may create backlog."
                        )
                    )
                    confirmationReasons.append("A protected or fixed mission is being skipped.")
                }
                if let start = mission.scheduledStart { affectedStarts.append(start) }
                if let end = mission.scheduledEnd { affectedEnds.append(end) }
            }
        }

        if let bodyArea = detectedBodyArea(in: lowercased) {
            intents.append(DetectedIntent(kind: .reportPain, confidence: 0.96))
            entities.append(ExtractedEntity(kind: .bodyArea, value: bodyArea))
            mutations.append(.addPainFlag(bodyArea: bodyArea))
            warnings.append(
                CommandWarning(
                    severity: .consequence,
                    message: "Work that materially loads the \(bodyArea) should remain paused until reassessed."
                )
            )
            confirmationReasons.append("This recovery flag can restrict physical work and request replanning.")
            affectedStarts.append(context.referenceDate)
            affectedEnds.append(endOfDay(for: context.referenceDate, context: context))
        }

        let shiftMatches = allMatches(
            #"(?:work shift|i work)(?: on)? (\d{4}-\d{2}-\d{2}|\d{1,2} [a-z]+(?: \d{4})?) (?:from )?(\d{1,2}[:.]\d{2}) (?:to|-)(\d{1,2}[:.]\d{2})"#,
            in: source
        )
        for match in shiftMatches where match.count == 4 {
            if match[1].range(of: #"\b\d{4}\b"#, options: .regularExpression) == nil {
                warnings.append(
                    CommandWarning(
                        severity: .caution,
                        message: "No year was spoken for \(match[1]); the current year was inferred."
                    )
                )
                confirmationReasons.append("The work-shift year was inferred.")
            }
            guard let shift = parseShift(
                dateText: match[1],
                startTimeText: match[2],
                endTimeText: match[3],
                context: context
            ) else {
                warnings.append(
                    CommandWarning(
                        severity: .caution,
                        message: "The work-shift date or time could not be resolved safely."
                    )
                )
                confirmationReasons.append("The shift date or time is ambiguous.")
                continue
            }
            guard shift.end > context.referenceDate else {
                warnings.append(
                    CommandWarning(
                        severity: .caution,
                        message: "The proposed work shift is entirely in the past and was not added."
                    )
                )
                continue
            }
            if shift.start < context.referenceDate {
                warnings.append(
                    CommandWarning(
                        severity: .caution,
                        message: "The proposed work shift has already started. Confirm its exact times before applying."
                    )
                )
                confirmationReasons.append("The proposed work shift has already started.")
            }

            intents.append(DetectedIntent(kind: .addWorkShift, confidence: 0.96))
            entities.append(
                ExtractedEntity(
                    kind: .date,
                    value: match[1],
                    dateValue: shift.start
                )
            )
            entities.append(
                ExtractedEntity(
                    kind: .timeRange,
                    value: "\(match[2])–\(match[3])",
                    dateValue: shift.end
                )
            )
            mutations.append(.addWorkShift(shift))
            parsedShifts.append(shift)
            affectedStarts.append(shift.start)
            affectedEnds.append(shift.end)
            confirmationReasons.append("Work shifts are fixed commitments and must be confirmed.")

            if context.fixedCommitments.contains(where: {
                intervalsOverlap(shift.start, shift.end, $0.start, $0.end)
            }) {
                warnings.append(
                    CommandWarning(
                        severity: .consequence,
                        message: "This shift overlaps an existing fixed commitment."
                    )
                )
                confirmationReasons.append("The proposed shift conflicts with an existing fixed commitment.")
            }
        }

        if shiftMatches.count > 1 {
            warnings.append(
                CommandWarning(
                    severity: .consequence,
                    message: "Multiple shifts were detected. Review every date and time before applying."
                )
            )
            confirmationReasons.append("Multiple work shifts were detected in one command.")
        }
        if shiftsContainConflict(parsedShifts) {
            warnings.append(
                CommandWarning(
                    severity: .consequence,
                    message: "Two or more proposed work shifts overlap each other."
                )
            )
            confirmationReasons.append("The proposed work shifts conflict with each other.")
        }

        if !lowercased.contains("woke up late"),
           let match = firstMatch(
               #"(?:move|replan) (?:the )?(.+?)(?: mission)?(?:[.!]|$)"#,
            in: source
           ),
           match.count == 2 {
            let missionName = cleaned(match[1])
            if missionName != "my day" && missionName != "day" {
                intents.append(DetectedIntent(kind: .moveMission, confidence: 0.93))
                entities.append(ExtractedEntity(kind: .mission, value: missionName))
                if let mission = resolvedMission(named: missionName, context: context, warnings: &warnings) {
                    mutations.append(
                        .requestMissionMove(missionID: mission.id, missionName: mission.title)
                    )
                    warnings.append(
                        CommandWarning(
                            severity: .consequence,
                            message: "Moving \(mission.title) can affect later blocks and transition time."
                        )
                    )
                    confirmationReasons.append("Moving a mission can change the remaining schedule.")
                    if let start = mission.scheduledStart { affectedStarts.append(start) }
                    if let end = mission.scheduledEnd { affectedEnds.append(end) }
                }
            }
        }

        if intents.isEmpty {
            intents = [DetectedIntent(kind: .unknown, confidence: 0)]
            warnings.append(
                CommandWarning(
                    severity: .caution,
                    message: "No supported local command was found. Edit the transcript and try again."
                )
            )
        }

        if mutations.count > 1 && shiftMatches.count <= 1 {
            confirmationReasons.append("This transcript proposes multiple changes.")
        }

        return StructuredCommand(
            rawTranscript: rawTranscript,
            confirmedTranscript: confirmedTranscript,
            detectedIntents: intents,
            extractedEntities: entities,
            proposedMutations: mutations,
            affectedScheduleRange: AffectedScheduleRange(
                start: affectedStarts.min(),
                end: affectedEnds.max()
            ),
            warnings: warnings,
            confirmationRequirement: confirmationReasons.isEmpty
                ? .none
                : .explicit(reasons: unique(confirmationReasons)),
            createdAt: context.referenceDate,
            contextRevisionToken: context.revisionToken
        )
    }

    private func resolvedMission(
        named name: String,
        context: CommandContext,
        warnings: inout [CommandWarning]
    ) -> CommandMissionReference? {
        let query = normalizedName(name)
        let exactMatches = context.missions.filter {
            normalizedName($0.title) == query || $0.category.rawValue == query
        }
        if exactMatches.count == 1 {
            return exactMatches[0]
        }

        let partialMatches = context.missions.filter {
            normalizedName($0.title).contains(query) || query.contains(normalizedName($0.title))
        }
        if partialMatches.count == 1 {
            return partialMatches[0]
        }

        warnings.append(
            CommandWarning(
                severity: .caution,
                message: exactMatches.count + partialMatches.count == 0
                    ? "No mission matched “\(name)”."
                    : "More than one mission matched “\(name)”. Be more specific."
            )
        )
        return nil
    }

    private func detectedBodyArea(in text: String) -> String? {
        let bodyAreas = [
            "hamstring", "knee", "ankle", "calf", "quad", "hip", "groin",
            "back", "shoulder", "elbow", "wrist", "neck", "foot"
        ]
        return bodyAreas.first(where: {
            text.contains("my \($0) hurts")
                || text.contains("pain in my \($0)")
                || text.contains("\($0) pain")
        })
    }

    private func parseShift(
        dateText: String,
        startTimeText: String,
        endTimeText: String,
        context: CommandContext
    ) -> WorkShiftPayload? {
        guard
            let day = parseDate(dateText, context: context),
            let startTime = parseTime(startTimeText),
            let endTime = parseTime(endTimeText)
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: context.timeZoneIdentifier) ?? .current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        guard
            let start = calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: dayComponents.year,
                    month: dayComponents.month,
                    day: dayComponents.day,
                    hour: startTime.hour,
                    minute: startTime.minute
                )
            ),
            var end = calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: dayComponents.year,
                    month: dayComponents.month,
                    day: dayComponents.day,
                    hour: endTime.hour,
                    minute: endTime.minute
                )
            )
        else {
            return nil
        }

        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return WorkShiftPayload(start: start, end: end)
    }

    private func parseDate(_ text: String, context: CommandContext) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: context.timeZoneIdentifier) ?? .current

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false

        if text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: text)
        }

        let containsYear = text.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil
        let resolvedText: String
        if containsYear {
            resolvedText = text
        } else {
            let year = calendar.component(.year, from: context.referenceDate)
            resolvedText = "\(text) \(year)"
        }

        for format in ["d MMMM yyyy", "d MMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: resolvedText) {
                return date
            }
        }
        return nil
    }

    private func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.replacingOccurrences(of: ".", with: ":").split(separator: ":")
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            return nil
        }
        return (hour, minute)
    }

    private func endOfDay(for date: Date, context: CommandContext) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: context.timeZoneIdentifier) ?? .current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    private func intervalsOverlap(
        _ firstStart: Date,
        _ firstEnd: Date,
        _ secondStart: Date,
        _ secondEnd: Date
    ) -> Bool {
        firstStart < secondEnd && secondStart < firstEnd
    }

    private func shiftsContainConflict(_ shifts: [WorkShiftPayload]) -> Bool {
        guard shifts.count > 1 else { return false }
        for firstIndex in shifts.indices {
            for secondIndex in shifts.indices where secondIndex > firstIndex {
                if intervalsOverlap(
                    shifts[firstIndex].start,
                    shifts[firstIndex].end,
                    shifts[secondIndex].start,
                    shifts[secondIndex].end
                ) {
                    return true
                }
            }
        }
        return false
    }

    private func normalizedName(_ text: String) -> String {
        cleaned(text)
            .lowercased()
            .replacingOccurrences(of: "the ", with: "")
            .replacingOccurrences(of: " session", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeApostrophes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
    }

    private func cleaned(_ text: String) -> String {
        text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: ".,;:!?\"“”")
            )
        )
    }

    private func firstMatch(_ pattern: String, in text: String) -> [String]? {
        allMatches(pattern, in: text).first
    }

    private func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let matchRange = match.range(at: index)
                guard
                    matchRange.location != NSNotFound,
                    let range = Range(matchRange, in: text)
                else {
                    return ""
                }
                return String(text[range])
            }
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
