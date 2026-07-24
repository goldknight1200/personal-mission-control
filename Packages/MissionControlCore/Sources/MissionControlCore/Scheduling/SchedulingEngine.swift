import Foundation

public struct SchedulingEngine: SchedulePlanning {
    private let identifiers: any IdentifierGenerating

    public init(
        identifiers: any IdentifierGenerating = StableIdentifierGenerator()
    ) {
        self.identifiers = identifiers
    }

    public func makePlan(input: PlanningInput) -> SchedulingResult {
        Planner(input: input, identifiers: identifiers).run()
    }
}

private final class Planner {
    private struct Candidate {
        var mission: Mission
        var routineID: EntityID?
        var occurrenceKey: String
        var stage: Int
        var preferredDayStarts: [Date]
        var preferredStartMinute: Int?
        var earliest: Date?
        var latest: Date?
        var existingBlock: ScheduleBlock?
        var repeatedMissCause: MissionMissCause?
    }

    private struct TransitionSpec {
        var preparationMinutes: Int
        var travelBeforeMinutes: Int
        var travelAfterMinutes: Int
        var recoveryAfterMinutes: Int

        var beforeMinutes: Int {
            preparationMinutes + travelBeforeMinutes
        }

        var afterMinutes: Int {
            travelAfterMinutes + recoveryAfterMinutes
        }
    }

    private let input: PlanningInput
    private let identifiers: any IdentifierGenerating
    private var calendar: Calendar
    private let horizonStart: Date
    private let horizonEnd: Date
    private let dayStarts: [Date]

    private var blocks: [ScheduleBlock] = []
    private var generatedMissions: [Mission] = []
    private var decisions: [SchedulingDecision] = []
    private var conflicts: [SchedulingConflict] = []
    private var unscheduledMissionIDs: [EntityID] = []
    private var essentialMealReservations: [DateInterval] = []

    init(input: PlanningInput, identifiers: any IdentifierGenerating) {
        self.input = input
        self.identifiers = identifiers
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: input.profile.timeZoneIdentifier
        ) ?? .current
        self.calendar = calendar
        horizonStart = calendar.startOfDay(for: input.currentTime)
        horizonEnd = calendar.date(
            byAdding: .day,
            value: input.profile.planningPolicy.planningHorizonDays,
            to: horizonStart
        ) ?? horizonStart.addingTimeInterval(7 * 86_400)
        dayStarts = (0..<input.profile.planningPolicy.planningHorizonDays)
            .compactMap {
                calendar.date(byAdding: .day, value: $0, to: horizonStart)
            }
    }

    func run() -> SchedulingResult {
        loadLockedBlocks()
        loadFixedCommitments()
        detectFixedConflicts()
        insertFixedTransitions()
        protectSleep()
        let primaryCandidates = buildPrimaryCandidates()
        essentialMealReservations = mealReservations(
            for: primaryCandidates
        )
        placeNutritionCoverage()
        essentialMealReservations = []
        placeCandidates(primaryCandidates)
        placeCandidates(buildTriggeredRoutineCandidates())
        preserveFreeTime()

        blocks.sort(by: blockOrder)
        return SchedulingResult(
            metadata: SchedulingPlanMetadata(
                generatedAt: input.currentTime,
                horizonStart: horizonStart,
                horizonEnd: horizonEnd,
                gridMinutes: input.profile.planningPolicy.generatedGridMinutes
            ),
            blocks: blocks,
            generatedMissions: generatedMissions,
            decisions: decisions,
            conflicts: conflicts,
            unscheduledMissionIDs: Array(Set(unscheduledMissionIDs)).sorted()
        )
    }

    // MARK: Hard constraints

    private func loadLockedBlocks() {
        for block in input.lockedBlocks
        where intersectsHorizon(block.start, block.end) {
            guard !blocks.contains(where: { $0.id == block.id }) else {
                continue
            }
            blocks.append(block)
            addDecision(
                kind: .preserved,
                rule: .stability,
                missionID: block.missionID,
                blockID: block.id,
                title: block.title,
                explanation: block.kind == .freeTime
                    ? "Past free time was frozen with the rest of history."
                    : "This block was frozen or outside the affected replan range.",
                previousStart: block.start,
                newStart: block.start
            )
        }
    }

    private func loadFixedCommitments() {
        for commitment in input.fixedCommitments
            .filter({ intersectsHorizon($0.start, $0.end) })
            .sorted(by: fixedOrder) {
            if blocks.contains(where: {
                $0.fixedCommitmentID == commitment.id
            }) {
                continue
            }
            let block = ScheduleBlock(
                id: identifiers.identifier(
                    namespace: "fixed.\(commitment.id.rawValue.uuidString)"
                ),
                fixedCommitmentID: commitment.id,
                title: commitment.title,
                category: commitment.category,
                kind: .fixedCommitment,
                rigidity: .fixed,
                start: commitment.start,
                end: commitment.end,
                isImmutable: commitment.isExternallyManaged
            )
            blocks.append(block)
            addDecision(
                kind: commitment.isExternallyManaged ? .protected : .placed,
                rule: commitment.isExternallyManaged
                    ? .immutableExternalEvent
                    : .fixedCommitment,
                blockID: block.id,
                title: block.title,
                explanation: commitment.isExternallyManaged
                    ? "The imported event retained its exact time and cannot be moved by the planner."
                    : "The fixed commitment retained its exact entered time.",
                newStart: block.start
            )
        }
    }

    private func detectFixedConflicts() {
        let fixed = blocks.filter { $0.kind == .fixedCommitment }
            .sorted(by: blockOrder)
        guard fixed.count > 1 else { return }
        for leftIndex in 0..<(fixed.count - 1) {
            for rightIndex in (leftIndex + 1)..<fixed.count {
                let left = fixed[leftIndex]
                let right = fixed[rightIndex]
                guard overlaps(left.start, left.end, right.start, right.end) else {
                    if right.start >= left.end { break }
                    continue
                }
                addConflict(
                    kind: .fixedOverlap,
                    severity: .blocking,
                    title: "Fixed commitments overlap",
                    explanation: "\(left.title) and \(right.title) both retain their exact times. The planner cannot resolve this without user authority.",
                    commitmentIDs: [
                        left.fixedCommitmentID,
                        right.fixedCommitmentID
                    ].compactMap { $0 },
                    start: max(left.start, right.start),
                    end: min(left.end, right.end)
                )
            }
        }
    }

    private func insertFixedTransitions() {
        let commitments = input.fixedCommitments
            .filter { intersectsHorizon($0.start, $0.end) }
            .sorted(by: fixedOrder)
        for commitment in commitments {
            let spec = transitionSpec(for: commitment.category)
            guard spec.beforeMinutes > 0 || spec.afterMinutes > 0 else {
                continue
            }
            var proposed: [ScheduleBlock] = []
            var cursor = commitment.start.addingTimeInterval(
                -TimeInterval(spec.beforeMinutes * 60)
            )
            if spec.preparationMinutes > 0 {
                let end = cursor.addingTimeInterval(
                    TimeInterval(spec.preparationMinutes * 60)
                )
                proposed.append(
                    transitionBlock(
                        namespace: "fixed.\(commitment.id.rawValue.uuidString).prep",
                        title: "Prepare for \(commitment.title)",
                        category: commitment.category,
                        kind: .preparation,
                        start: cursor,
                        end: end,
                        immutable: commitment.isExternallyManaged
                    )
                )
                cursor = end
            }
            if spec.travelBeforeMinutes > 0 {
                let end = cursor.addingTimeInterval(
                    TimeInterval(spec.travelBeforeMinutes * 60)
                )
                proposed.append(
                    transitionBlock(
                        namespace: "fixed.\(commitment.id.rawValue.uuidString).travel.before",
                        title: "Travel to \(commitment.title)",
                        category: commitment.category,
                        kind: .travel,
                        start: cursor,
                        end: end,
                        immutable: commitment.isExternallyManaged
                    )
                )
            }
            cursor = commitment.end
            if spec.travelAfterMinutes > 0 {
                let end = cursor.addingTimeInterval(
                    TimeInterval(spec.travelAfterMinutes * 60)
                )
                proposed.append(
                    transitionBlock(
                        namespace: "fixed.\(commitment.id.rawValue.uuidString).travel.after",
                        title: "Travel after \(commitment.title)",
                        category: commitment.category,
                        kind: .travel,
                        start: cursor,
                        end: end,
                        immutable: commitment.isExternallyManaged
                    )
                )
                cursor = end
            }
            if spec.recoveryAfterMinutes > 0 {
                let end = cursor.addingTimeInterval(
                    TimeInterval(spec.recoveryAfterMinutes * 60)
                )
                proposed.append(
                    transitionBlock(
                        namespace: "fixed.\(commitment.id.rawValue.uuidString).recovery",
                        title: "Shower and change",
                        category: .recovery,
                        kind: .preparation,
                        start: cursor,
                        end: end,
                        immutable: commitment.isExternallyManaged
                    )
                )
            }
            addTransitionGroup(
                proposed,
                ownerTitle: commitment.title,
                rule: .preparationAndTravel
            )
        }
    }

    private func protectSleep() {
        let policy = input.profile.planningPolicy
        for day in dayStarts {
            guard
                let wake = date(on: day, minute: policy.preferredWakeMinute)
            else {
                continue
            }
            let targetStart = wake.addingTimeInterval(
                -TimeInterval(policy.sleepTargetMinutes * 60)
            )
            guard intersectsHorizon(targetStart, wake) else { continue }
            if blocks.contains(where: {
                $0.kind == .sleep
                    && calendar.isDate($0.end, inSameDayAs: wake)
            }) {
                continue
            }
            if overlappingBlocks(start: targetStart, end: wake).isEmpty {
                let block = ScheduleBlock(
                    id: identifiers.identifier(
                        namespace: "sleep.\(dayKey(day))"
                    ),
                    title: "Sleep",
                    category: .recovery,
                    kind: .sleep,
                    rigidity: .protected,
                    start: targetStart,
                    end: wake,
                    isImmutable: false
                )
                blocks.append(block)
                addDecision(
                    kind: .protected,
                    rule: .sleepProtection,
                    blockID: block.id,
                    title: block.title,
                    explanation: "Reserved the editable \(policy.sleepTargetMinutes)-minute sleep target before the preferred wake time.",
                    newStart: targetStart
                )
            } else {
                let practicalStart = wake.addingTimeInterval(
                    -TimeInterval(
                        policy.practicalSleepMinimumMinutes * 60
                    )
                )
                if overlappingBlocks(
                    start: practicalStart,
                    end: wake
                ).isEmpty {
                    let block = ScheduleBlock(
                        id: identifiers.identifier(
                            namespace: "sleep.\(dayKey(day))"
                        ),
                        title: "Sleep",
                        category: .recovery,
                        kind: .sleep,
                        rigidity: .protected,
                        start: practicalStart,
                        end: wake
                    )
                    blocks.append(block)
                    addDecision(
                        kind: .recoveryAdjusted,
                        rule: .sleepProtection,
                        blockID: block.id,
                        title: block.title,
                        explanation: "An exact commitment prevents the full sleep target, so the planner retained the editable practical minimum and reported the shortfall.",
                        newStart: practicalStart
                    )
                    addConflict(
                        kind: .sleepConflict,
                        severity: .warning,
                        title: "Sleep target shortened",
                        explanation: "The full \(policy.sleepTargetMinutes)-minute target conflicts with exact time. The \(policy.practicalSleepMinimumMinutes)-minute practical minimum still fits.",
                        start: targetStart,
                        end: practicalStart
                    )
                    continue
                }
                addConflict(
                    kind: .sleepConflict,
                    severity: .blocking,
                    title: "Sleep target conflicts with fixed time",
                    explanation: "The preferred sleep window overlaps a frozen or fixed block. The planner recorded the conflict instead of moving exact commitments or silently shortening sleep.",
                    start: targetStart,
                    end: wake
                )
            }
        }
    }

    // MARK: Essential coverage

    private func placeNutritionCoverage() {
        let needs = normalizedNutritionNeeds()
        let mealTimes = input.profile.nutritionTargets.preferredMealStartMinutes
        for need in needs.sorted(by: { $0.localDay < $1.localDay }) {
            let day = calendar.startOfDay(for: need.localDay)
            let lockedCoverage = blocks.filter {
                $0.kind == .meal
                    && calendar.isDate($0.start, inSameDayAs: day)
            }.count
            let requiredBySignal = need.clearDeficit
                ? max(need.missingMealCount, 1)
                : need.missingMealCount
            let mealsToPlace = max(
                requiredBySignal - lockedCoverage,
                0
            )
            guard mealsToPlace > 0 else { continue }
            for index in 0..<mealsToPlace {
                let mealIndex = lockedCoverage + index
                let preferredMinute = mealTimes.isEmpty
                    ? 13 * 60
                    : mealTimes[min(mealIndex, mealTimes.count - 1)]
                let namespace = "meal.\(dayKey(day)).\(mealIndex)"
                let earliestOverride = need.clearDeficit
                    && calendar.isDate(day, inSameDayAs: input.currentTime)
                    ? input.currentTime
                    : nil
                guard let start = findSimpleSlot(
                    day: day,
                    durationMinutes: need.suggestedMealDurationMinutes,
                    preferredMinute: preferredMinute,
                    earliestOverride: earliestOverride
                ) else {
                    addConflict(
                        kind: .noValidWindow,
                        severity: need.clearDeficit ? .blocking : .warning,
                        title: "No eating window available",
                        explanation: need.clearDeficit
                            ? "A clear food deficit was reported, but no non-overlapping eating block fits before protected sleep."
                            : "The requested substantial-meal coverage does not fit without moving a harder constraint.",
                        start: day,
                        end: awakeEnd(for: day)
                    )
                    continue
                }
                let block = ScheduleBlock(
                    id: identifiers.identifier(namespace: namespace),
                    title: need.clearDeficit && mealIndex == 0
                        ? "Eat — food deficit"
                        : "Substantial meal",
                    category: .nutrition,
                    kind: .meal,
                    rigidity: .protected,
                    start: start,
                    end: start.addingTimeInterval(
                        TimeInterval(need.suggestedMealDurationMinutes * 60)
                    )
                )
                blocks.append(block)
                addDecision(
                    kind: .placed,
                    rule: .nutritionCoverage,
                    blockID: block.id,
                    title: block.title,
                    explanation: need.clearDeficit && mealIndex == 0
                        ? "Inserted the earliest practical eating block because a clear food deficit was reported."
                        : "Reserved practical time toward the editable substantial-meal target.",
                    newStart: start
                )
            }
        }
    }

    private func normalizedNutritionNeeds() -> [NutritionPlanningNeed] {
        let explicit = input.nutritionNeeds.filter {
            let day = calendar.startOfDay(for: $0.localDay)
            return day >= horizonStart && day < horizonEnd
        }
        return dayStarts.map { day in
            if let configured = explicit
                .filter({ need in
                    calendar.isDate(
                        need.localDay,
                        inSameDayAs: day
                    )
                })
                .sorted(by: { $0.id < $1.id })
                .first {
                return configured
            }
            return NutritionPlanningNeed(
                id: identifiers.identifier(
                    namespace: "nutrition.need.\(dayKey(day))"
                ),
                localDay: day,
                substantialMealsRequired:
                    input.profile.nutritionTargets.substantialMeals
            )
        }
    }

    // MARK: Candidate generation

    private func buildPrimaryCandidates() -> [Candidate] {
        var candidates: [Candidate] = []
        let approvedMissionIDs = Set(
            input.approvedWorkouts.filter(\.isEnabled).map(\.missionID)
        )
        for mission in input.missions
        where mission.sourceRoutineID == nil
            && mission.status == .planned
            && !approvedMissionIDs.contains(mission.id)
            && !input.deferredMissionIDs.contains(mission.id) {
            if blocks.contains(where: {
                $0.missionID == mission.id && $0.kind == .mission
            }) {
                continue
            }
            if mission.rigidity == .droppable,
               mission.urgency < .high,
               mission.deadline == nil {
                unscheduledMissionIDs.append(mission.id)
                addDecision(
                    kind: .omitted,
                    rule: .freeTime,
                    missionID: mission.id,
                    title: mission.title,
                    explanation: "Optional droppable work had no urgent or dated reason to consume open time."
                )
                continue
            }
            candidates.append(candidate(for: mission))
        }
        candidates.append(contentsOf: approvedWorkoutCandidates())
        candidates.append(contentsOf: routineCandidates(includeTriggered: false))
        return candidates.sorted(by: candidateOrder)
    }

    private func candidate(for mission: Mission) -> Candidate {
        var scheduledMission = mission
        let dueWindowOverride = input.dueWindowOverrides[mission.id]
        if let dueWindowOverride {
            scheduledMission.dueWindow = dueWindowOverride
        }
        if scheduledMission.category == .project {
            let minimum = max(
                input.profile.planningPolicy.minimumFocusedBlockMinutes,
                scheduledMission.minimumUsefulBlockMinutes
            )
            scheduledMission.estimatedDurationMinutes = max(
                scheduledMission.estimatedDurationMinutes,
                minimum
            )
            scheduledMission.minimumUsefulBlockMinutes = minimum
        }
        let existing = input.existingPlan
            .filter {
                $0.missionID == mission.id && $0.kind == .mission
            }
            .sorted(by: blockOrder)
            .first
        return Candidate(
            mission: scheduledMission,
            routineID: mission.sourceRoutineID,
            occurrenceKey: "mission.\(mission.id.rawValue.uuidString)",
            stage: stage(for: mission),
            preferredDayStarts: [],
            preferredStartMinute: preferredMinute(for: mission),
            earliest: dueWindowOverride?.earliest
                ?? mission.dueWindow?.earliest,
            latest: dueWindowOverride?.latest
                ?? mission.dueWindow?.latest
                ?? mission.deadline,
            existingBlock: existing,
            repeatedMissCause: latestMissCause(for: mission)
        )
    }

    private func approvedWorkoutCandidates() -> [Candidate] {
        var candidates: [Candidate] = []
        for workout in input.approvedWorkouts
            .filter(\.isEnabled)
            .sorted(by: { $0.id < $1.id }) {
            guard
                workout.weeklySessionTarget > 0,
                let mission = input.missions.first(where: {
                    $0.id == workout.missionID
                }),
                mission.status != .skipped,
                !input.deferredMissionIDs.contains(mission.id)
            else {
                continue
            }
            let completedThisHorizon = input.completionHistory.filter {
                $0.missionID == mission.id
                    && ($0.status == .completed || $0.status == .partial)
                    && $0.completedAt >= horizonStart
                    && $0.completedAt < horizonEnd
            }.count
            let recoveryWindow = input.dueWindowOverrides[mission.id]
            let scheduledRecoveryCount = recoveryWindow == nil ? 0 : 1
            let deferredOccurrenceCount =
                input.deferredOccurrenceCounts[mission.id] ?? 0
            let remainingTarget = max(
                workout.weeklySessionTarget
                    - completedThisHorizon
                    - scheduledRecoveryCount
                    - deferredOccurrenceCount,
                0
            )
            let resolvedDays = input.completionHistory
                .filter {
                    $0.missionID == mission.id
                        && $0.completedAt >= horizonStart
                        && $0.completedAt < horizonEnd
                }
                .map { record in
                    let scheduledStart = record.scheduleBlockID.flatMap {
                        blockID in
                        input.existingPlan.first(where: {
                            $0.id == blockID
                        })?.start
                    }
                    return calendar.startOfDay(
                        for: scheduledStart ?? record.completedAt
                    )
                }
            let preferred = dayStarts.filter { day in
                !resolvedDays.contains(where: { resolvedDay in
                    calendar.isDate(
                        resolvedDay,
                        inSameDayAs: day
                    )
                })
                    && (
                        workout.preferredWeekdays.isEmpty
                            || workout.preferredWeekdays.contains(
                                weekday(for: day)
                            )
                    )
            }
            let fallback = dayStarts.filter { day in
                !resolvedDays.contains(where: {
                    calendar.isDate($0, inSameDayAs: day)
                })
                    && !preferred.contains(where: {
                        calendar.isDate($0, inSameDayAs: day)
                    })
            }
            let selectedDays = Array(
                (preferred + fallback)
                    .filter {
                        awakeEnd(for: $0) > input.currentTime
                    }
                    .prefix(remainingTarget)
            )
            let completedBlockIDs = Set(
                input.completionHistory.compactMap(\.scheduleBlockID)
            )
            let existing = input.existingPlan
                .filter {
                    $0.missionID == mission.id && $0.kind == .mission
                        && !completedBlockIDs.contains($0.id)
                        && $0.end > input.currentTime
                }
                .sorted(by: blockOrder)
            for day in selectedDays {
                let existingForDay = existing.first(where: {
                    calendar.isDate($0.start, inSameDayAs: day)
                })
                if let existingForDay,
                   blocks.contains(where: {
                       $0.id == existingForDay.id
                   }) {
                    continue
                }
                candidates.append(
                    Candidate(
                        mission: mission,
                        routineID: nil,
                        occurrenceKey: "workout.\(workout.id.rawValue.uuidString).\(dayKey(day))",
                        stage: 3,
                        preferredDayStarts: [day] + dayStarts.filter {
                            !calendar.isDate($0, inSameDayAs: day)
                        },
                        preferredStartMinute: workout.preferredStartMinute
                            ?? preferredMinute(for: mission),
                        earliest: horizonStart,
                        latest: horizonEnd,
                        existingBlock: existingForDay,
                        repeatedMissCause: latestMissCause(for: mission)
                    )
                )
            }
            if let recoveryWindow {
                let eligibleDays = dayStarts.filter { day in
                    awakeEnd(for: day) > recoveryWindow.earliest
                        && awakeStart(for: day) < recoveryWindow.latest
                }
                candidates.append(
                    Candidate(
                        mission: mission,
                        routineID: nil,
                        occurrenceKey: "workout.\(workout.id.rawValue.uuidString).recovery.\(timestampKey(recoveryWindow.earliest))",
                        stage: 3,
                        preferredDayStarts: eligibleDays,
                        preferredStartMinute: workout.preferredStartMinute
                            ?? preferredMinute(for: mission),
                        earliest: recoveryWindow.earliest,
                        latest: recoveryWindow.latest,
                        existingBlock: nil,
                        repeatedMissCause: latestMissCause(for: mission)
                    )
                )
            }
        }
        return candidates
    }

    private func routineCandidates(includeTriggered: Bool) -> [Candidate] {
        var candidates: [Candidate] = []
        for routine in input.routines
            .filter(\.isEnabled)
            .sorted(by: { $0.id < $1.id }) {
            let isTriggered = routine.recurrence.frequency == .afterEvent
            guard isTriggered == includeTriggered else { continue }
            for nominal in nominalDates(for: routine) {
                var mission = generatedMission(
                    for: routine,
                    nominalDate: nominal
                )
                guard !input.deferredMissionIDs.contains(mission.id) else {
                    continue
                }
                guard input.dueWindowOverrides[mission.id] != nil
                    || !input.completionHistory.contains(where: {
                        $0.missionID == mission.id
                    }) else {
                    continue
                }
                let defaultWindow = routineWindow(
                    routine,
                    nominalDate: nominal
                )
                if let override = input.dueWindowOverrides[mission.id] {
                    mission.dueWindow = override
                }
                if !generatedMissions.contains(where: { $0.id == mission.id }) {
                    generatedMissions.append(mission)
                }
                let window = DateInterval(
                    start: input.dueWindowOverrides[mission.id]?.earliest
                        ?? defaultWindow.start,
                    end: input.dueWindowOverrides[mission.id]?.latest
                        ?? defaultWindow.end
                )
                let eligibleDays = dayStarts.filter { day in
                    awakeEnd(for: day) > window.start
                        && awakeStart(for: day) < window.end
                }
                let existing = input.existingPlan.first(where: {
                    $0.missionID == mission.id && $0.kind == .mission
                })
                if blocks.contains(where: {
                    $0.missionID == mission.id && $0.kind == .mission
                }) {
                    continue
                }
                candidates.append(
                    Candidate(
                        mission: mission,
                        routineID: routine.id,
                        occurrenceKey: "routine.\(routine.id.rawValue.uuidString).\(timestampKey(nominal))",
                        stage: stage(for: routine),
                        preferredDayStarts: eligibleDays.isEmpty
                            ? [calendar.startOfDay(for: nominal)]
                            : eligibleDays,
                        preferredStartMinute: isTriggered
                            ? nil
                            : routinePreferredMinute(routine),
                        earliest: window.start,
                        latest: window.end,
                        existingBlock: existing,
                        repeatedMissCause: latestMissCause(for: mission)
                    )
                )
            }
        }
        return candidates.sorted(by: candidateOrder)
    }

    private func buildTriggeredRoutineCandidates() -> [Candidate] {
        routineCandidates(includeTriggered: true)
    }

    private func mealReservations(
        for candidates: [Candidate]
    ) -> [DateInterval] {
        // Meals remain essential, but their preferred times are flexible. A
        // provisional reservation keeps them from taking the only viable
        // interval for a protected activity; meals then choose the nearest
        // practical open time before final candidate placement.
        candidates.compactMap { candidate in
            let day = candidate.preferredDayStarts.first
                ?? (dayStarts.first ?? horizonStart)
            guard
                candidate.stage <= 4,
                let preferredMinute = candidate.preferredStartMinute,
                let missionStart = date(
                    on: day,
                    minute: preferredMinute
                )
            else {
                return nil
            }
            let spec = transitionSpec(for: candidate.mission)
            let start = missionStart.addingTimeInterval(
                -TimeInterval(spec.beforeMinutes * 60)
            )
            let end = missionStart.addingTimeInterval(
                TimeInterval(
                    (
                        candidate.mission.estimatedDurationMinutes
                            + spec.afterMinutes
                    ) * 60
                )
            )
            guard
                start >= horizonStart,
                start >= awakeStart(for: day),
                end <= horizonEnd,
                missionStart >= (candidate.earliest ?? .distantPast),
                missionStart.addingTimeInterval(
                    TimeInterval(
                        candidate.mission.estimatedDurationMinutes * 60
                    )
                ) <= (candidate.latest ?? .distantFuture),
                end <= awakeEnd(for: day),
                overlappingBlocks(start: start, end: end).isEmpty,
                blockingPainFlag(for: candidate.mission) == nil,
                !(isDemandingPhysical(candidate.mission)
                    && recoveryRestrictsToday()
                    && calendar.isDate(
                        missionStart,
                        inSameDayAs: input.currentTime
                    )),
                !violatesPreMatchRestriction(
                    mission: candidate.mission,
                    start: missionStart,
                    end: end
                )
            else {
                return nil
            }
            return DateInterval(start: start, end: end)
        }
    }

    private func nominalDates(for routine: Routine) -> [Date] {
        switch routine.recurrence.frequency {
        case .daily:
            let anchor = calendar.date(
                from: DateComponents(year: 2001, month: 1, day: 1)
            ) ?? horizonStart
            return dayStarts.filter { day in
                let offset = calendar.dateComponents(
                    [.day],
                    from: anchor,
                    to: day
                ).day ?? 0
                return offset.isMultiple(
                    of: routine.recurrence.interval
                )
            }
        case .weekly:
            return dayStarts.filter {
                routine.recurrence.weekdays.contains(weekday(for: $0))
            }
        case .monthly:
            // The durable routine model currently has no recurrence anchor.
            // One occurrence at the horizon start is explicit and deterministic.
            addConflict(
                kind: .recurrenceAnchorMissing,
                severity: .warning,
                title: "\(routine.title) needs a monthly anchor",
                explanation: "The routine model does not yet store a last-completed or calendar-day anchor, so the planner uses the first day of this horizon and reports the assumption.",
                start: horizonStart,
                end: horizonEnd
            )
            return dayStarts.first.map { [$0] } ?? []
        case .afterEvent:
            guard let category = routine.recurrence.triggerCategory else {
                return []
            }
            return blocks.filter {
                $0.category == category
                    && ($0.kind == .fixedCommitment || $0.kind == .mission)
                    && $0.end < horizonEnd
            }
            .map(\.end)
            .sorted()
        }
    }

    private func routineWindow(
        _ routine: Routine,
        nominalDate: Date
    ) -> DateInterval {
        if routine.recurrence.frequency == .afterEvent {
            return DateInterval(
                start: nominalDate,
                end: min(
                    nominalDate.addingTimeInterval(
                        TimeInterval(routine.dueWindowMinutes * 60)
                    ),
                    horizonEnd
                )
            )
        }
        let day = calendar.startOfDay(for: nominalDate)
        if let preferred = routine.recurrence.preferredStartMinute,
           let preferredDate = date(on: day, minute: preferred) {
            let halfWindow = routine.dueWindowMinutes / 2
            return DateInterval(
                start: max(
                    awakeStart(for: day),
                    preferredDate.addingTimeInterval(
                        -TimeInterval(halfWindow * 60)
                    )
                ),
                end: min(
                    awakeEnd(for: day),
                    preferredDate.addingTimeInterval(
                        TimeInterval(
                            (
                                halfWindow
                                    + routine.estimatedDurationMinutes
                            ) * 60
                        )
                    )
                )
            )
        }
        let start = awakeStart(for: day)
        return DateInterval(
            start: start,
            end: min(
                start.addingTimeInterval(
                    TimeInterval(
                        (
                            routine.dueWindowMinutes
                                + routine.estimatedDurationMinutes
                        ) * 60
                    )
                ),
                horizonEnd
            )
        )
    }

    private func generatedMission(
        for routine: Routine,
        nominalDate: Date
    ) -> Mission {
        Mission(
            id: identifiers.identifier(
                namespace: "routine.mission.\(routine.id.rawValue.uuidString).\(timestampKey(nominalDate))"
            ),
            category: routine.category,
            title: routine.title,
            rigidity: routine.rigidity,
            importance: routine.rigidity == .protected ? .high : .normal,
            urgency: .normal,
            dueWindow: DueWindow(
                earliest: routineWindow(
                    routine,
                    nominalDate: nominalDate
                ).start,
                latest: routineWindow(
                    routine,
                    nominalDate: nominalDate
                ).end
            ),
            estimatedDurationMinutes: routine.estimatedDurationMinutes,
            minimumUsefulBlockMinutes: min(
                max(routine.estimatedDurationMinutes, 1),
                10
            ),
            sourceRoutineID: routine.id,
            consistencyCost: routine.rigidity == .protected ? .high : .normal,
            backlogCost: routine.rigidity == .deferrable ? .low : .normal,
            energyDemand: routine.category == .football ? .high : .low,
            physicalLoad: routine.category == .football ? .heavy : .light,
            bodyAreaTags: routine.category == .football
                ? ["lower body"]
                : [],
            preparationMinutes: routine.category == .football
                ? input.profile.transitions.footballPreparationMinutes.maximum
                : 0,
            travelBeforeMinutes: routineTravelMinutes(for: routine),
            travelAfterMinutes: routineTravelMinutes(for: routine),
            location: routine.category == .football
                ? "Training ground"
                : nil
        )
    }

    // MARK: Candidate placement

    private func placeCandidates(_ initial: [Candidate]) {
        var pending = initial
        var madeProgress = true
        while !pending.isEmpty && madeProgress {
            madeProgress = false
            var deferred: [Candidate] = []
            for candidate in pending {
                let unresolvedDependencies = candidate.mission.dependencyIDs
                    .filter { !dependencyIsAvailable($0) }
                if !unresolvedDependencies.isEmpty {
                    deferred.append(candidate)
                    continue
                }
                place(candidate)
                madeProgress = true
            }
            pending = deferred
        }
        for candidate in pending {
            omit(
                candidate,
                conflictKind: .dependencyUnavailable,
                rule: .dependency,
                explanation: "A prerequisite is neither completed nor present earlier in the valid plan."
            )
        }
    }

    private func place(_ originalCandidate: Candidate) {
        var candidate = originalCandidate
        if let pain = blockingPainFlag(for: candidate.mission) {
            omit(
                candidate,
                conflictKind: .recoveryRestricted,
                rule: .painRestriction,
                explanation: "Active \(pain.bodyArea) pain blocks work that materially loads the affected area until explicit reassessment."
            )
            return
        }

        if let existing = candidate.existingBlock,
           canPlace(candidate, missionStart: existing.start) {
            let placement = createBundle(
                for: candidate,
                missionStart: existing.start,
                preservedMissionBlockID: existing.id
            )
            blocks.append(contentsOf: placement)
            addDecision(
                kind: .preserved,
                rule: .stability,
                missionID: candidate.mission.id,
                routineID: candidate.routineID,
                blockID: existing.id,
                title: candidate.mission.title,
                explanation: "The existing placement remained valid, so the planner preserved it to avoid unnecessary churn.",
                previousStart: existing.start,
                newStart: existing.start
            )
            return
        }

        var missionStart = findMissionStart(for: candidate)
        if missionStart == nil,
           candidate.mission.category == .project,
           candidate.mission.allowsSplitting {
            let minimum = max(
                input.profile.planningPolicy.minimumFocusedBlockMinutes,
                candidate.mission.minimumUsefulBlockMinutes
            )
            if candidate.mission.estimatedDurationMinutes > minimum {
                candidate.mission.estimatedDurationMinutes = minimum
                missionStart = findMissionStart(for: candidate)
            }
        }
        guard let missionStart else {
            let rule: SchedulingRule = candidate.mission.category == .project
                ? .minimumUsefulBlock
                : candidate.routineID == nil
                    ? .overload
                    : .routineDueWindow
            omit(
                candidate,
                conflictKind: candidate.routineID == nil
                    ? .noValidWindow
                    : .dueWindowMissed,
                rule: rule,
                explanation: omissionExplanation(for: candidate)
            )
            return
        }

        let placement = createBundle(
            for: candidate,
            missionStart: missionStart,
            preservedMissionBlockID: nil
        )
        blocks.append(contentsOf: placement)
        let missionBlock = placement.first(where: { $0.kind == .mission })
        let wasMoved = candidate.existingBlock != nil
            && candidate.existingBlock?.start != missionStart
        let causeText = candidate.repeatedMissCause.map {
            " The latest repeated-miss classification was \($0.displayName.lowercased()), so its recommendation was considered."
        } ?? ""
        addDecision(
            kind: wasMoved ? .moved : .placed,
            rule: wasMoved
                ? .stability
                : decisionRule(for: candidate),
            missionID: candidate.mission.id,
            routineID: candidate.routineID,
            blockID: missionBlock?.id,
            title: candidate.mission.title,
            explanation: placementExplanation(for: candidate) + causeText,
            previousStart: candidate.existingBlock?.start,
            newStart: missionStart
        )
        for transition in placement where transition.kind.isTransition {
            addDecision(
                kind: .transitionInserted,
                rule: .preparationAndTravel,
                missionID: candidate.mission.id,
                routineID: candidate.routineID,
                blockID: transition.id,
                title: transition.title,
                explanation: "Preparation, travel, and recovery consume real time and were reserved with the mission.",
                newStart: transition.start
            )
        }
        if isRecoveryAdjusted(candidate, start: missionStart) {
            addDecision(
                kind: .recoveryAdjusted,
                rule: .recoveryContext,
                missionID: candidate.mission.id,
                blockID: missionBlock?.id,
                title: candidate.mission.title,
                explanation: "Demanding physical work was kept out of today because sleep or fatigue context crossed the editable recovery threshold.",
                newStart: missionStart
            )
        }
    }

    private func findMissionStart(for candidate: Candidate) -> Date? {
        let spec = transitionSpec(for: candidate.mission)
        let candidateDays = candidate.preferredDayStarts.isEmpty
            ? dayStarts
            : candidate.preferredDayStarts
        for day in candidateDays.sorted() {
            var earliest = awakeStart(for: day).addingTimeInterval(
                TimeInterval(spec.beforeMinutes * 60)
            )
            if calendar.isDate(day, inSameDayAs: input.currentTime) {
                earliest = max(
                    earliest,
                    snapUp(input.currentTime).addingTimeInterval(
                        TimeInterval(spec.beforeMinutes * 60)
                    )
                )
            }
            if let dueEarliest = candidate.earliest {
                earliest = max(earliest, dueEarliest)
            }
            var latest = awakeEnd(for: day).addingTimeInterval(
                -TimeInterval(
                    (
                        candidate.mission.estimatedDurationMinutes
                            + spec.afterMinutes
                    ) * 60
                )
            )
            if let dueLatest = candidate.latest {
                latest = min(
                    latest,
                    dueLatest.addingTimeInterval(
                        -TimeInterval(
                            candidate.mission.estimatedDurationMinutes * 60
                        )
                    )
                )
            }
            guard earliest <= latest else { continue }

            let step = TimeInterval(
                input.profile.planningPolicy.generatedGridMinutes * 60
            )
            if let preferredMinute = adjustedPreferredMinute(for: candidate),
               let preferred = date(on: day, minute: preferredMinute) {
                let snappedPreferred = snapUp(preferred)
                var cursor = max(snapUp(earliest), snappedPreferred)
                while cursor <= latest {
                    if canPlace(candidate, missionStart: cursor) {
                        return cursor
                    }
                    cursor.addTimeInterval(step)
                }

                cursor = snapUp(earliest)
                let earlierLimit = min(latest, snappedPreferred)
                while cursor < earlierLimit {
                    if canPlace(candidate, missionStart: cursor) {
                        return cursor
                    }
                    cursor.addTimeInterval(step)
                }
            } else {
                var cursor = snapUp(earliest)
                while cursor <= latest {
                    if canPlace(candidate, missionStart: cursor) {
                        return cursor
                    }
                    cursor.addTimeInterval(step)
                }
            }
        }

        return nil
    }

    private func canPlace(
        _ candidate: Candidate,
        missionStart: Date
    ) -> Bool {
        let spec = transitionSpec(for: candidate.mission)
        let groupStart = missionStart.addingTimeInterval(
            -TimeInterval(spec.beforeMinutes * 60)
        )
        let groupEnd = missionStart.addingTimeInterval(
            TimeInterval(
                (
                    candidate.mission.estimatedDurationMinutes
                        + spec.afterMinutes
                ) * 60
            )
        )
        let day = calendar.startOfDay(for: missionStart)
        guard
            groupStart >= awakeStart(for: day),
            groupEnd <= awakeEnd(for: day),
            overlappingBlocks(start: groupStart, end: groupEnd).isEmpty,
            !calendar.isDate(
                missionStart,
                inSameDayAs: input.currentTime
            ) || groupStart >= snapUp(input.currentTime),
            missionStart >= (candidate.earliest ?? .distantPast),
            groupEnd <= horizonEnd
        else {
            return false
        }
        if let latest = candidate.latest,
           missionStart.addingTimeInterval(
               TimeInterval(candidate.mission.estimatedDurationMinutes * 60)
           ) > latest {
            return false
        }
        if isDemandingPhysical(candidate.mission)
            && recoveryRestrictsToday()
            && calendar.isDate(
                missionStart,
                inSameDayAs: input.currentTime
            ) {
            return false
        }
        if violatesPreMatchRestriction(
            mission: candidate.mission,
            start: missionStart,
            end: missionStart.addingTimeInterval(
                TimeInterval(
                    candidate.mission.estimatedDurationMinutes * 60
                )
            )
        ) {
            return false
        }
        return true
    }

    private func createBundle(
        for candidate: Candidate,
        missionStart: Date,
        preservedMissionBlockID: EntityID?
    ) -> [ScheduleBlock] {
        let spec = transitionSpec(for: candidate.mission)
        var result: [ScheduleBlock] = []
        var cursor = missionStart.addingTimeInterval(
            -TimeInterval(spec.beforeMinutes * 60)
        )
        if spec.preparationMinutes > 0 {
            let end = cursor.addingTimeInterval(
                TimeInterval(spec.preparationMinutes * 60)
            )
            result.append(
                transitionBlock(
                    namespace: "\(candidate.occurrenceKey).prep",
                    title: "Prepare for \(candidate.mission.title)",
                    category: candidate.mission.category,
                    kind: .preparation,
                    start: cursor,
                    end: end
                )
            )
            cursor = end
        }
        if spec.travelBeforeMinutes > 0 {
            let end = cursor.addingTimeInterval(
                TimeInterval(spec.travelBeforeMinutes * 60)
            )
            result.append(
                transitionBlock(
                    namespace: "\(candidate.occurrenceKey).travel.before",
                    title: "Travel to \(candidate.mission.title)",
                    category: candidate.mission.category,
                    kind: .travel,
                    start: cursor,
                    end: end
                )
            )
        }
        let missionEnd = missionStart.addingTimeInterval(
            TimeInterval(candidate.mission.estimatedDurationMinutes * 60)
        )
        result.append(
            ScheduleBlock(
                id: preservedMissionBlockID ?? identifiers.identifier(
                    namespace: "\(candidate.occurrenceKey).mission"
                ),
                missionID: candidate.mission.id,
                title: candidate.mission.title,
                category: candidate.mission.category,
                kind: .mission,
                rigidity: candidate.mission.rigidity,
                start: missionStart,
                end: missionEnd,
                isImmutable: candidate.mission.isExternallyManaged
            )
        )
        cursor = missionEnd
        if spec.travelAfterMinutes > 0 {
            let end = cursor.addingTimeInterval(
                TimeInterval(spec.travelAfterMinutes * 60)
            )
            result.append(
                transitionBlock(
                    namespace: "\(candidate.occurrenceKey).travel.after",
                    title: "Travel after \(candidate.mission.title)",
                    category: candidate.mission.category,
                    kind: .travel,
                    start: cursor,
                    end: end
                )
            )
            cursor = end
        }
        if spec.recoveryAfterMinutes > 0 {
            let end = cursor.addingTimeInterval(
                TimeInterval(spec.recoveryAfterMinutes * 60)
            )
            result.append(
                transitionBlock(
                    namespace: "\(candidate.occurrenceKey).recovery",
                    title: "Shower and change",
                    category: .recovery,
                    kind: .preparation,
                    start: cursor,
                    end: end
                )
            )
        }
        return result
    }

    // MARK: Free time

    private func preserveFreeTime() {
        blocks.removeAll(where: {
            $0.kind == .freeTime && $0.end > input.currentTime
        })
        for day in dayStarts {
            let start = max(
                awakeStart(for: day),
                calendar.isDate(day, inSameDayAs: input.currentTime)
                    ? snapUp(input.currentTime)
                    : awakeStart(for: day)
            )
            let end = awakeEnd(for: day)
            guard end > start else { continue }
            let occupied = blocks.filter {
                overlaps($0.start, $0.end, start, end)
            }
            .sorted(by: blockOrder)
            var cursor = start
            var freeIndex = 0
            for block in occupied {
                if block.start > cursor {
                    addFreeTime(
                        start: cursor,
                        end: min(block.start, end),
                        day: day,
                        index: freeIndex
                    )
                    freeIndex += 1
                }
                cursor = max(cursor, block.end)
                if cursor >= end { break }
            }
            if cursor < end {
                addFreeTime(
                    start: cursor,
                    end: end,
                    day: day,
                    index: freeIndex
                )
            }
        }
    }

    private func addFreeTime(
        start: Date,
        end: Date,
        day: Date,
        index: Int
    ) {
        guard end.timeIntervalSince(start) >= 30 * 60 else { return }
        let block = ScheduleBlock(
            id: identifiers.identifier(
                namespace: "free.\(dayKey(day)).\(index).\(timestampKey(start))"
            ),
            title: "Free time",
            category: .freeTime,
            kind: .freeTime,
            rigidity: .droppable,
            start: start,
            end: end
        )
        blocks.append(block)
        addDecision(
            kind: .freeTimePreserved,
            rule: .freeTime,
            blockID: block.id,
            title: block.title,
            explanation: "No stronger documented need justified consuming this open interval.",
            newStart: start
        )
    }

    // MARK: Restrictions and ranking

    private func dependencyIsAvailable(_ missionID: EntityID) -> Bool {
        input.completionHistory.contains(where: {
            $0.missionID == missionID && $0.status == .completed
        }) || blocks.contains(where: {
            $0.missionID == missionID && $0.kind == .mission
        })
    }

    private func blockingPainFlag(for mission: Mission) -> PainFlag? {
        let missionTags = Set(mission.bodyAreaTags.map(normalizedBodyArea))
        guard !missionTags.isEmpty else { return nil }
        return input.painFlags
            .filter(\.isActive)
            .sorted(by: { $0.reportedAt > $1.reportedAt })
            .first(where: { flag in
                let pain = normalizedBodyArea(flag.bodyArea)
                return missionTags.contains(where: {
                    $0.contains(pain)
                        || pain.contains($0)
                        || lowerBodyAreas.contains($0)
                            && lowerBodyAreas.contains(pain)
                })
            })
    }

    private var lowerBodyAreas: Set<String> {
        [
            "lower body",
            "hamstring",
            "quadriceps",
            "quad",
            "knee",
            "calf",
            "ankle",
            "glute",
            "hip"
        ]
    }

    private func violatesPreMatchRestriction(
        mission: Mission,
        start: Date,
        end: Date
    ) -> Bool {
        guard
            mission.physicalLoad == .heavy,
            mission.bodyAreaTags.map(normalizedBodyArea).contains(where: {
                lowerBodyAreas.contains($0)
            })
        else {
            return false
        }
        return input.fixedCommitments
            .filter { $0.category == .football && $0.isFootballMatch }
            .contains(where: { match in
                let restrictedStart = match.start.addingTimeInterval(-24 * 60 * 60)
                return overlaps(start, end, restrictedStart, match.start)
            })
    }

    private func recoveryRestrictsToday() -> Bool {
        guard let recovery = input.recoveryContext else { return false }
        guard calendar.isDate(
            recovery.recordedAt,
            inSameDayAs: input.currentTime
        ) else {
            return false
        }
        if recovery.fatigue == .high { return true }
        if let sleep = recovery.sleepDurationMinutes {
            return sleep
                < input.profile.planningPolicy
                    .reconsiderDemandingWorkBelowMinutes
        }
        return false
    }

    private func isDemandingPhysical(_ mission: Mission) -> Bool {
        mission.physicalLoad == .heavy
            || mission.physicalLoad == .moderate
                && mission.energyDemand == .high
    }

    private func isRecoveryAdjusted(
        _ candidate: Candidate,
        start: Date
    ) -> Bool {
        isDemandingPhysical(candidate.mission)
            && recoveryRestrictsToday()
            && !calendar.isDate(start, inSameDayAs: input.currentTime)
    }

    private func stage(for mission: Mission) -> Int {
        if mission.category == .football || mission.category == .gym {
            return mission.rigidity == .protected ? 3 : 6
        }
        if mission.rigidity == .protected {
            return 4
        }
        if mission.category == .project {
            let project = mission.projectID.flatMap { projectID in
                input.projects.first(where: { $0.id == projectID })
            }
            if project?.status == .activePriority
                || mission.userPriorityOverride != nil
                || mission.deadline.map({ $0 < horizonEnd }) == true {
                return 5
            }
            if project?.status == .maintained {
                return 6
            }
            return 8
        }
        switch mission.rigidity {
        case .fixed: return 2
        case .protected: return 4
        case .flexible: return 7
        case .deferrable: return 8
        case .droppable: return 9
        }
    }

    private func stage(for routine: Routine) -> Int {
        if routine.category == .football || routine.category == .gym {
            return 3
        }
        switch routine.rigidity {
        case .fixed: return 2
        case .protected: return 4
        case .flexible: return 7
        case .deferrable: return 8
        case .droppable: return 9
        }
    }

    private func candidateOrder(_ left: Candidate, _ right: Candidate) -> Bool {
        if left.stage != right.stage { return left.stage < right.stage }
        let leftOverride = left.mission.userPriorityOverride?.rawValue ?? 0
        let rightOverride = right.mission.userPriorityOverride?.rawValue ?? 0
        if leftOverride != rightOverride {
            return leftOverride > rightOverride
        }
        if left.mission.urgency != right.mission.urgency {
            return left.mission.urgency > right.mission.urgency
        }
        if left.mission.importance != right.mission.importance {
            return left.mission.importance > right.mission.importance
        }
        let leftDeadline = left.mission.deadline ?? .distantFuture
        let rightDeadline = right.mission.deadline ?? .distantFuture
        if leftDeadline != rightDeadline {
            return leftDeadline < rightDeadline
        }
        if left.mission.backlogCost != right.mission.backlogCost {
            return left.mission.backlogCost > right.mission.backlogCost
        }
        if left.mission.consistencyCost != right.mission.consistencyCost {
            return left.mission.consistencyCost
                > right.mission.consistencyCost
        }
        if left.mission.title != right.mission.title {
            return left.mission.title < right.mission.title
        }
        return left.occurrenceKey < right.occurrenceKey
    }

    private func preferredMinute(for mission: Mission) -> Int {
        switch mission.category {
        case .project, .work: 9 * 60
        case .gym: 16 * 60
        case .football:
            input.profile.footballPattern.historicalTrainingStartMinute
        case .nutrition: 13 * 60
        case .household: 18 * 60
        case .recovery: 20 * 60
        default: 10 * 60
        }
    }

    private func adjustedPreferredMinute(
        for candidate: Candidate
    ) -> Int? {
        switch candidate.repeatedMissCause {
        case .badTiming:
            return max(candidate.preferredStartMinute ?? 10 * 60, 14 * 60)
        case .fatigue:
            return max(candidate.preferredStartMinute ?? 10 * 60, 12 * 60)
        default:
            return candidate.preferredStartMinute
        }
    }

    private func latestMissCause(for mission: Mission) -> MissionMissCause? {
        input.missDiagnostics
            .filter { $0.category == mission.category }
            .max(by: { $0.recordedAt < $1.recordedAt })?
            .cause
    }

    // MARK: Transition defaults

    private func transitionSpec(for mission: Mission) -> TransitionSpec {
        TransitionSpec(
            preparationMinutes: mission.preparationMinutes,
            travelBeforeMinutes: mission.travelBeforeMinutes,
            travelAfterMinutes: mission.travelAfterMinutes,
            recoveryAfterMinutes: recoveryMinutes(for: mission.category)
        )
    }

    private func transitionSpec(
        for category: MissionCategory
    ) -> TransitionSpec {
        switch category {
        case .work:
            TransitionSpec(
                preparationMinutes:
                    input.profile.transitions.workPreparationMinutes.maximum,
                travelBeforeMinutes:
                    input.profile.transitions.workTravelEachWayMinutes,
                travelAfterMinutes:
                    input.profile.transitions.workTravelEachWayMinutes,
                recoveryAfterMinutes: 0
            )
        case .football:
            TransitionSpec(
                preparationMinutes:
                    input.profile.transitions.footballPreparationMinutes.maximum,
                travelBeforeMinutes:
                    input.profile.transitions.footballTravelEachWayMinutes,
                travelAfterMinutes:
                    input.profile.transitions.footballTravelEachWayMinutes,
                recoveryAfterMinutes:
                    input.profile.transitions
                        .footballShowerChangeMinutes.maximum
            )
        case .gym:
            TransitionSpec(
                preparationMinutes:
                    input.profile.transitions.gymPreparationMinutes.maximum,
                travelBeforeMinutes:
                    input.profile.transitions.gymTravelEachWayMinutes,
                travelAfterMinutes:
                    input.profile.transitions.gymTravelEachWayMinutes,
                recoveryAfterMinutes:
                    input.profile.transitions.gymShowerChangeMinutes.maximum
            )
        default:
            TransitionSpec(
                preparationMinutes: 0,
                travelBeforeMinutes: 0,
                travelAfterMinutes: 0,
                recoveryAfterMinutes: 0
            )
        }
    }

    private func routineTravelMinutes(for routine: Routine) -> Int {
        if routine.category == .football {
            return input.profile.transitions.footballTravelEachWayMinutes
        }
        let title = routine.title.lowercased()
        if title.contains("grocer") || title.contains("shopping") {
            return input.profile.transitions.shoppingTravelMinutes
        }
        return 0
    }

    private func routinePreferredMinute(_ routine: Routine) -> Int? {
        if let preferred = routine.recurrence.preferredStartMinute {
            return preferred
        }
        let title = routine.title.lowercased()
        if title.contains("grocer") {
            return 17 * 60
        }
        if title.contains("meal preparation") {
            return 17 * 60 + 40
        }
        if routine.category == .household {
            return 18 * 60 + 30
        }
        switch routine.category {
        case .nutrition: return 13 * 60
        case .recovery: return 20 * 60
        default: return 10 * 60
        }
    }

    private func recoveryMinutes(for category: MissionCategory) -> Int {
        switch category {
        case .football:
            input.profile.transitions.footballShowerChangeMinutes.maximum
        case .gym:
            input.profile.transitions.gymShowerChangeMinutes.maximum
        default:
            0
        }
    }

    // MARK: Explanations and conflicts

    private func decisionRule(for candidate: Candidate) -> SchedulingRule {
        if candidate.routineID != nil {
            let title = candidate.mission.title.lowercased()
            if title.contains("grocer")
                || title.contains("meal preparation") {
                return .compatibleBundling
            }
            return .routineDueWindow
        }
        if candidate.mission.rigidity == .protected {
            return .protectedCommitment
        }
        if candidate.mission.category == .project {
            return .projectPriority
        }
        return .fiveMinuteGrid
    }

    private func placementExplanation(for candidate: Candidate) -> String {
        if candidate.routineID != nil {
            let title = candidate.mission.title.lowercased()
            if title.contains("grocer")
                || title.contains("meal preparation") {
                return "Placed inside its due window beside compatible food and household work to reduce fragmentation."
            }
            return "Placed within the routine's flexible due window after harder constraints."
        }
        if candidate.mission.category == .project {
            return "Placed after hard constraints using active priority, urgency, deadline, and backlog tie-breakers; the block meets the minimum useful focus duration."
        }
        if candidate.mission.rigidity == .protected {
            return "Protected work was placed before flexible and deferrable candidates."
        }
        return "Placed on the editable five-minute grid after higher-order constraints."
    }

    private func omissionExplanation(for candidate: Candidate) -> String {
        if candidate.mission.category == .project {
            let minimum = max(
                input.profile.planningPolicy.minimumFocusedBlockMinutes,
                candidate.mission.minimumUsefulBlockMinutes
            )
            return "No valid \(minimum)-minute project block fits without violating a harder constraint or consuming protected recovery."
        }
        if candidate.routineID != nil {
            return "No non-overlapping interval fits inside the routine's due window."
        }
        return "No valid interval remains after fixed, sleep, meal, recovery, transition, and higher-priority constraints."
    }

    private func omit(
        _ candidate: Candidate,
        conflictKind: SchedulingConflictKind,
        rule: SchedulingRule,
        explanation: String
    ) {
        unscheduledMissionIDs.append(candidate.mission.id)
        addDecision(
            kind: .omitted,
            rule: rule,
            missionID: candidate.mission.id,
            routineID: candidate.routineID,
            title: candidate.mission.title,
            explanation: explanation
        )
        addConflict(
            kind: conflictKind,
            severity: candidate.mission.rigidity == .protected
                ? .blocking
                : .warning,
            title: "\(candidate.mission.title) was not placed",
            explanation: explanation,
            missionID: candidate.mission.id,
            start: candidate.earliest,
            end: candidate.latest
        )
    }

    private func addDecision(
        kind: SchedulingDecisionKind,
        rule: SchedulingRule,
        missionID: EntityID? = nil,
        routineID: EntityID? = nil,
        blockID: EntityID? = nil,
        title: String,
        explanation: String,
        previousStart: Date? = nil,
        newStart: Date? = nil,
        requiresConfirmation: Bool = false
    ) {
        let namespace = [
            "decision",
            kind.rawValue,
            rule.rawValue,
            missionID?.rawValue.uuidString ?? "none",
            routineID?.rawValue.uuidString ?? "none",
            blockID?.rawValue.uuidString ?? "none",
            title
        ].joined(separator: ".")
        decisions.append(
            SchedulingDecision(
                id: identifiers.identifier(namespace: namespace),
                kind: kind,
                rule: rule,
                missionID: missionID,
                routineID: routineID,
                scheduleBlockID: blockID,
                title: title,
                explanation: explanation,
                previousStart: previousStart,
                newStart: newStart,
                requiresConfirmation: requiresConfirmation
            )
        )
    }

    private func addConflict(
        kind: SchedulingConflictKind,
        severity: SchedulingConflictSeverity,
        title: String,
        explanation: String,
        missionID: EntityID? = nil,
        commitmentIDs: [EntityID] = [],
        start: Date? = nil,
        end: Date? = nil
    ) {
        let namespace = [
            "conflict",
            kind.rawValue,
            title,
            missionID?.rawValue.uuidString ?? "none",
            commitmentIDs.map(\.rawValue.uuidString).joined(separator: ","),
            timestampKey(start),
            timestampKey(end)
        ].joined(separator: ".")
        conflicts.append(
            SchedulingConflict(
                id: identifiers.identifier(namespace: namespace),
                kind: kind,
                severity: severity,
                title: title,
                explanation: explanation,
                affectedMissionID: missionID,
                affectedCommitmentIDs: commitmentIDs,
                rangeStart: start,
                rangeEnd: end
            )
        )
    }

    // MARK: Calendar and interval helpers

    private func awakeStart(for day: Date) -> Date {
        date(
            on: day,
            minute: input.profile.planningPolicy.preferredWakeMinute
        ) ?? day
    }

    private func awakeEnd(for day: Date) -> Date {
        guard
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
            let nextWake = date(
                on: nextDay,
                minute: input.profile.planningPolicy.preferredWakeMinute
            )
        else {
            return day.addingTimeInterval(24 * 60 * 60)
        }
        return nextWake.addingTimeInterval(
            -TimeInterval(
                input.profile.planningPolicy.sleepTargetMinutes * 60
            )
        )
    }

    private func date(on day: Date, minute: Int) -> Date? {
        calendar.date(
            byAdding: .minute,
            value: minute,
            to: calendar.startOfDay(for: day)
        )
    }

    private func weekday(for day: Date) -> Weekday {
        Weekday(
            rawValue: calendar.component(.weekday, from: day)
        ) ?? .monday
    }

    private func findSimpleSlot(
        day: Date,
        durationMinutes: Int,
        preferredMinute: Int,
        earliestOverride: Date?
    ) -> Date? {
        let earliest = snapUp(
            max(
                awakeStart(for: day),
                max(
                    earliestOverride ?? .distantPast,
                    calendar.isDate(day, inSameDayAs: input.currentTime)
                        ? input.currentTime
                        : .distantPast
                )
            )
        )
        let latest = awakeEnd(for: day).addingTimeInterval(
            -TimeInterval(durationMinutes * 60)
        )
        let duration = TimeInterval(durationMinutes * 60)
        let step = TimeInterval(
            input.profile.planningPolicy.generatedGridMinutes * 60
        )
        if let preferred = date(on: day, minute: preferredMinute) {
            let proposed = max(snapUp(preferred), earliest)
            var cursor = proposed
            while cursor <= latest {
                if simpleSlotIsOpen(
                    start: cursor,
                    end: cursor.addingTimeInterval(duration)
                ) {
                    return cursor
                }
                cursor.addTimeInterval(step)
            }

            cursor = earliest
            while cursor < min(proposed, latest.addingTimeInterval(step)) {
                if simpleSlotIsOpen(
                    start: cursor,
                    end: cursor.addingTimeInterval(duration)
                ) {
                    return cursor
                }
                cursor.addTimeInterval(step)
            }
            return nil
        }
        var cursor = earliest
        while cursor <= latest {
            let end = cursor.addingTimeInterval(duration)
            if simpleSlotIsOpen(start: cursor, end: end) {
                return cursor
            }
            cursor.addTimeInterval(step)
        }
        return nil
    }

    private func simpleSlotIsOpen(start: Date, end: Date) -> Bool {
        overlappingBlocks(start: start, end: end).isEmpty
            && !essentialMealReservations.contains(where: {
                overlaps(start, end, $0.start, $0.end)
            })
    }

    private func addTransitionGroup(
        _ proposed: [ScheduleBlock],
        ownerTitle: String,
        rule: SchedulingRule
    ) {
        for block in proposed {
            if blocks.contains(where: { $0.id == block.id }) {
                continue
            }
            if overlappingBlocks(start: block.start, end: block.end).isEmpty {
                blocks.append(block)
                addDecision(
                    kind: .transitionInserted,
                    rule: rule,
                    blockID: block.id,
                    title: block.title,
                    explanation: "Reserved the configured transition around \(ownerTitle).",
                    newStart: block.start
                )
            } else {
                addConflict(
                    kind: .transitionUnavailable,
                    severity: .blocking,
                    title: "Transition time does not fit",
                    explanation: "\(block.title) overlaps another fixed or frozen block. Exact commitments were preserved and the missing transition was reported.",
                    start: block.start,
                    end: block.end
                )
            }
        }
    }

    private func transitionBlock(
        namespace: String,
        title: String,
        category: MissionCategory,
        kind: ScheduleBlockKind,
        start: Date,
        end: Date,
        immutable: Bool = false
    ) -> ScheduleBlock {
        ScheduleBlock(
            id: identifiers.identifier(namespace: namespace),
            title: title,
            category: category,
            kind: kind,
            rigidity: .fixed,
            start: start,
            end: end,
            isImmutable: immutable
        )
    }

    private func overlappingBlocks(
        start: Date,
        end: Date
    ) -> [ScheduleBlock] {
        blocks.filter { overlaps($0.start, $0.end, start, end) }
    }

    private func overlaps(
        _ leftStart: Date,
        _ leftEnd: Date,
        _ rightStart: Date,
        _ rightEnd: Date
    ) -> Bool {
        leftStart < rightEnd && rightStart < leftEnd
    }

    private func intersectsHorizon(_ start: Date, _ end: Date) -> Bool {
        overlaps(start, end, horizonStart, horizonEnd)
    }

    private func snapUp(_ date: Date) -> Date {
        let grid = Double(
            input.profile.planningPolicy.generatedGridMinutes * 60
        )
        let value = date.timeIntervalSinceReferenceDate
        return Date(
            timeIntervalSinceReferenceDate: ceil(value / grid) * grid
        )
    }

    private func normalizedBodyArea(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func blockOrder(
        _ left: ScheduleBlock,
        _ right: ScheduleBlock
    ) -> Bool {
        if left.start != right.start { return left.start < right.start }
        if left.end != right.end { return left.end < right.end }
        return left.id < right.id
    }

    private func fixedOrder(
        _ left: FixedCommitment,
        _ right: FixedCommitment
    ) -> Bool {
        if left.start != right.start { return left.start < right.start }
        if left.end != right.end { return left.end < right.end }
        return left.id < right.id
    }

    private func dayKey(_ date: Date) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func timestampKey(_ date: Date?) -> String {
        guard let date else { return "none" }
        return String(Int(date.timeIntervalSince1970.rounded()))
    }
}
