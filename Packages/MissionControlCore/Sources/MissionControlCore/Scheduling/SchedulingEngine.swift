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
        var workout: ScheduledWorkoutMetadata? = nil
        var workoutSequence: Int? = nil
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
        let horizonStart = calendar.startOfDay(for: input.currentTime)
        let horizonEnd = calendar.date(
            byAdding: .day,
            value: input.profile.planningPolicy.planningHorizonDays,
            to: horizonStart
        ) ?? horizonStart.addingTimeInterval(7 * 86_400)
        let dayStarts = (0..<input.profile.planningPolicy.planningHorizonDays)
            .compactMap {
                calendar.date(byAdding: .day, value: $0, to: horizonStart)
            }

        self.calendar = calendar
        self.horizonStart = horizonStart
        self.horizonEnd = horizonEnd
        self.dayStarts = dayStarts
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
        let fullyUnscheduled = Set(unscheduledMissionIDs).filter { missionID in
            !blocks.contains(where: {
                $0.missionID == missionID && $0.kind == .mission
            })
        }
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
            unscheduledMissionIDs: Array(fullyUnscheduled).sorted()
        )
    }

    // MARK: Hard constraints

    private func loadLockedBlocks() {
        for block in input.lockedBlocks
        where intersectsHorizon(block.start, block.end) {
            guard !blocks.contains(where: { $0.id == block.id }) else {
                continue
            }
            var preserved = block
            if block.end > input.currentTime,
               var metadata = block.workout,
               let session = input.workoutPrograms
                .first(where: { $0.id == metadata.programID })?
                .sessionTemplates.first(where: {
                    $0.id == metadata.sessionTemplateID
                }) {
                let newlyBlocked = WorkoutPlanning.blockedExerciseIDs(
                    in: session,
                    painFlags: input.painFlags
                )
                if !metadata.isShortened {
                    metadata.exerciseIDs = session.exercises.map(\.id)
                }
                metadata.blockedExerciseIDs = newlyBlocked
                metadata.exerciseIDs.removeAll(where: {
                    newlyBlocked.contains($0)
                })
                preserved.workout = metadata
                if !newlyBlocked.isEmpty {
                    addDecision(
                        kind: .recoveryAdjusted,
                        rule: .painRestriction,
                        missionID: block.missionID,
                        blockID: block.id,
                        title: block.title,
                        explanation: "Active pain safeguards were applied to this frozen occurrence without changing its approved session template.",
                        previousStart: block.start,
                        newStart: block.start
                    )
                }
            }
            if preserved.workout?.exerciseIDs.isEmpty == true {
                addDecision(
                    kind: .omitted,
                    rule: .painRestriction,
                    missionID: block.missionID,
                    blockID: block.id,
                    title: block.title,
                    explanation: "The frozen gym occurrence has no unaffected approved exercises and remains blocked pending explicit reassessment."
                )
                continue
            }
            blocks.append(preserved)
            addDecision(
                kind: .preserved,
                rule: .stability,
                missionID: preserved.missionID,
                blockID: preserved.id,
                title: preserved.title,
                explanation: preserved.kind == .freeTime
                    ? "Past free time was frozen with the rest of history."
                    : "This block was frozen or outside the affected replan range.",
                previousStart: preserved.start,
                newStart: preserved.start
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
        let lockedIDs = Set(input.lockedBlocks.map(\.id))
        let fixed = blocks.filter {
            $0.kind == .fixedCommitment || lockedIDs.contains($0.id)
        }
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
                    title: "User-controlled blocks overlap",
                    explanation: "\(left.title) and \(right.title) both retain their exact times. Adjust one of them to resolve the conflict.",
                    missionID: left.missionID ?? right.missionID,
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
            if spec.travelAfterMinutes > 0,
               !canBundleShopping(after: commitment) {
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
            placeSavedMeals(
                input.plannedMeals.filter {
                    calendar.isDate($0.localDay, inSameDayAs: day)
                },
                need: need,
                day: day,
                mealTimes: mealTimes
            )
            for block in blocks
            where block.kind == .meal
                && calendar.isDate(block.start, inSameDayAs: day) {
                guard let missionID = block.missionID,
                      !generatedMissions.contains(where: {
                          $0.id == missionID
                      }) else {
                    continue
                }
                generatedMissions.append(
                    nutritionMission(
                        id: missionID,
                        title: block.title,
                        durationMinutes: block.durationMinutes,
                        nutritionPlanningNeedID: need.id
                    )
                )
            }
            let suggestionMissionID = identifiers.identifier(
                namespace:
                    "nutrition.suggestion.\(need.id.rawValue.uuidString)"
            )

            let nonPlannedCoverage = blocks.filter {
                guard $0.kind == .meal,
                      calendar.isDate($0.start, inSameDayAs: day) else {
                    return false
                }
                guard let missionID = $0.missionID,
                      let mission = generatedMissions.first(where: {
                          $0.id == missionID
                      }) else {
                    return true
                }
                return mission.plannedMealID == nil
                    && mission.id != suggestionMissionID
            }.count
            let mealsToPlace = max(
                need.missingMealCount - nonPlannedCoverage,
                0
            )
            for index in 0..<mealsToPlace {
                let mealIndex =
                    need.substantialMealsCovered + nonPlannedCoverage + index
                let preferredMinute = mealTimes.isEmpty
                    ? 13 * 60
                    : mealTimes[min(mealIndex, mealTimes.count - 1)]
                let namespace =
                    "nutrition.coverage.\(need.id.rawValue.uuidString).\(index)"
                guard let start = findSimpleSlot(
                    day: day,
                    durationMinutes: need.suggestedMealDurationMinutes,
                    preferredMinute: preferredMinute,
                    earliestOverride: nil
                ) else {
                    addConflict(
                        kind: .noValidWindow,
                        severity: .warning,
                        title: "No eating window available",
                        explanation: "The requested substantial-meal coverage does not fit without moving a harder constraint.",
                        start: day,
                        end: awakeEnd(for: day)
                    )
                    continue
                }
                let mission = nutritionMission(
                    id: identifiers.identifier(namespace: namespace),
                    title: "Substantial meal",
                    durationMinutes: need.suggestedMealDurationMinutes,
                    nutritionPlanningNeedID: need.id
                )
                let block = ScheduleBlock(
                    id: identifiers.identifier(namespace: "\(namespace).block"),
                    missionID: mission.id,
                    title: mission.title,
                    category: .nutrition,
                    kind: .meal,
                    rigidity: .protected,
                    start: start,
                    end: start.addingTimeInterval(
                        TimeInterval(need.suggestedMealDurationMinutes * 60)
                    )
                )
                generatedMissions.append(mission)
                blocks.append(block)
                addDecision(
                    kind: .placed,
                    rule: .nutritionCoverage,
                    missionID: mission.id,
                    blockID: block.id,
                    title: block.title,
                    explanation: "Reserved practical time toward the editable substantial-meal target.",
                    newStart: start
                )
            }

            placeDeficitSuggestion(
                need: need,
                day: day,
                mealTimes: mealTimes
            )
        }
    }

    private func placeSavedMeals(
        _ meals: [PlannedMeal],
        need: NutritionPlanningNeed,
        day: Date,
        mealTimes: [Int]
    ) {
        let sortedMeals = meals.sorted {
            ($0.preferredStartMinute ?? Int.max)
                < ($1.preferredStartMinute ?? Int.max)
        }
        for (index, plannedMeal) in sortedMeals.enumerated() {
            let missionID = identifiers.identifier(
                namespace:
                    "nutrition.planned.\(plannedMeal.id.rawValue.uuidString)"
            )
            let mission = nutritionMission(
                id: missionID,
                title: plannedMeal.title,
                durationMinutes: plannedMeal.estimatedDurationMinutes,
                plannedMealID: plannedMeal.id,
                mealTemplateID: plannedMeal.mealTemplateID,
                nutritionPlanningNeedID: need.id
            )
            guard !input.completionHistory.contains(where: {
                $0.missionID == missionID
                    && ($0.status == .completed || $0.status == .partial)
            }) else {
                continue
            }
            if blocks.contains(where: { $0.missionID == missionID }) {
                generatedMissions.append(mission)
                continue
            }
            let fallbackMinute = mealTimes.isEmpty
                ? 13 * 60
                : mealTimes[min(index, mealTimes.count - 1)]
            guard let start = findSimpleSlot(
                day: day,
                durationMinutes: plannedMeal.estimatedDurationMinutes,
                preferredMinute:
                    plannedMeal.preferredStartMinute ?? fallbackMinute,
                earliestOverride: nil
            ) else {
                addConflict(
                    kind: .noValidWindow,
                    severity: .warning,
                    title: "No window for \(plannedMeal.title)",
                    explanation: "The planned meal could not fit without overlapping a harder commitment or protected sleep.",
                    start: day,
                    end: awakeEnd(for: day)
                )
                continue
            }
            let block = ScheduleBlock(
                id: identifiers.identifier(
                    namespace:
                        "nutrition.planned.block.\(plannedMeal.id.rawValue.uuidString)"
                ),
                missionID: mission.id,
                title: mission.title,
                category: .nutrition,
                kind: .meal,
                rigidity: .protected,
                start: start,
                end: start.addingTimeInterval(
                    TimeInterval(
                        plannedMeal.estimatedDurationMinutes * 60
                    )
                )
            )
            generatedMissions.append(mission)
            blocks.append(block)
            addDecision(
                kind: .placed,
                rule: .nutritionCoverage,
                missionID: mission.id,
                blockID: block.id,
                title: block.title,
                explanation: "Placed the saved approximate meal plan before flexible project and household work.",
                newStart: start
            )
        }
    }

    private func placeDeficitSuggestion(
        need: NutritionPlanningNeed,
        day: Date,
        mealTimes: [Int]
    ) {
        guard need.clearDeficit,
              need.suggestionDisposition != .declined else {
            return
        }
        let namespace =
            "nutrition.suggestion.\(need.id.rawValue.uuidString)"
        let missionID = identifiers.identifier(namespace: namespace)
        let title = "Eat — food deficit: \(need.suggestedTitle)"
        let mission = nutritionMission(
            id: missionID,
            title: title,
            durationMinutes: need.suggestedMealDurationMinutes,
            mealTemplateID: need.suggestedMealTemplateID,
            nutritionPlanningNeedID: need.id
        )
        guard !input.completionHistory.contains(where: {
            $0.missionID == missionID
                && ($0.status == .completed || $0.status == .partial)
        }) else {
            return
        }
        if blocks.contains(where: { $0.missionID == missionID }) {
            if let index = generatedMissions.firstIndex(where: {
                $0.id == missionID
            }) {
                generatedMissions[index] = mission
            } else {
                generatedMissions.append(mission)
            }
            return
        }
        let preferredMinute = need.suggestedStartMinute
            ?? mealTimes.last
            ?? 20 * 60
        let earliestOverride =
            calendar.isDate(day, inSameDayAs: input.currentTime)
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
                severity: .blocking,
                title: "Food coverage still looks short",
                explanation: "The approximate deficit was detected, but no non-overlapping eating block fits before protected sleep. The suggestion remains editable or can be declined.",
                start: day,
                end: awakeEnd(for: day)
            )
            return
        }
        let block = ScheduleBlock(
            id: identifiers.identifier(namespace: "\(namespace).block"),
            missionID: mission.id,
            title: title,
            category: .nutrition,
            kind: .meal,
            rigidity: .protected,
            start: start,
            end: start.addingTimeInterval(
                TimeInterval(need.suggestedMealDurationMinutes * 60)
            )
        )
        generatedMissions.append(mission)
        blocks.append(block)
        addDecision(
            kind: .placed,
            rule: .nutritionCoverage,
            missionID: mission.id,
            blockID: block.id,
            title: block.title,
            explanation: "Inserted a practical saved meal, snack, or generic eating block because the approximate daily plan is clearly below an editable coverage threshold.",
            newStart: start
        )
    }

    private func nutritionMission(
        id: EntityID,
        title: String,
        durationMinutes: Int,
        plannedMealID: EntityID? = nil,
        mealTemplateID: EntityID? = nil,
        nutritionPlanningNeedID: EntityID? = nil
    ) -> Mission {
        Mission(
            id: id,
            category: .nutrition,
            title: title,
            rigidity: .protected,
            importance: .high,
            urgency: .normal,
            estimatedDurationMinutes: durationMinutes,
            minimumUsefulBlockMinutes: min(durationMinutes, 10),
            consistencyCost: .high,
            energyDemand: .low,
            plannedMealID: plannedMealID,
            mealTemplateID: mealTemplateID,
            nutritionPlanningNeedID: nutritionPlanningNeedID
        )
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
            let alreadyLocked = blocks.contains(where: {
                $0.missionID == mission.id && $0.kind == .mission
            })
            if mission.category == .project,
               let project = mission.projectID.flatMap({ projectID in
                   input.projects.first(where: { $0.id == projectID })
               }),
               project.status == .backlog {
                unscheduledMissionIDs.append(mission.id)
                addDecision(
                    kind: .omitted,
                    rule: .projectPriority,
                    missionID: mission.id,
                    title: mission.title,
                    explanation: "The project is in Backlog, so it has no automatic schedule exposure."
                )
                continue
            }
            if alreadyLocked && mission.category != .project {
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
            if mission.category == .project {
                candidates.append(
                    contentsOf: projectCandidates(for: mission)
                )
            } else {
                candidates.append(candidate(for: mission))
            }
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
            let recoveryWindows = input.recoveryDueWindows[mission.id]
                ?? input.dueWindowOverrides[mission.id].map { [$0] }
                ?? []
            let scheduledRecoveryCount = recoveryWindows.count
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
            let program = workout.programID.flatMap { programID in
                input.workoutPrograms.first(where: {
                    $0.id == programID && $0.isApproved && $0.isActive
                })
            }
            if workout.programID != nil, program == nil {
                unscheduledMissionIDs.append(mission.id)
                addDecision(
                    kind: .omitted,
                    rule: .protectedCommitment,
                    missionID: mission.id,
                    title: mission.title,
                    explanation: "The linked workout program is not both user-approved and active, so no replacement session was generated."
                )
                continue
            }
            if let program, program.sessionTemplates.isEmpty {
                unscheduledMissionIDs.append(mission.id)
                addDecision(
                    kind: .omitted,
                    rule: .protectedCommitment,
                    missionID: mission.id,
                    title: mission.title,
                    explanation: "The approved program has no session templates, so no gym mission was invented."
                )
                continue
            }
            let selectedSessions = program.map {
                WorkoutPlanning.nextSessions(
                    in: $0,
                    after: input.workoutLogs,
                    count: selectedDays.count + recoveryWindows.count
                )
            } ?? []
            var sessionOffset = 0
            for day in selectedDays {
                let existingForDay = existing.first(where: {
                    calendar.isDate($0.start, inSameDayAs: day)
                })
                if let existingForDay,
                   blocks.contains(where: {
                       $0.id == existingForDay.id
                   }) {
                    if program != nil {
                        sessionOffset += 1
                    }
                    continue
                }
                var scheduledMission = mission
                var workoutMetadata: ScheduledWorkoutMetadata?
                if let program,
                   selectedSessions.indices.contains(sessionOffset) {
                    var session = selectedSessions[sessionOffset]
                    if let existingMetadata = existingForDay?.workout,
                       existingMetadata.programID == program.id,
                       let preservedSession = program.sessionTemplates
                        .first(where: {
                            $0.id == existingMetadata.sessionTemplateID
                        }) {
                        session = preservedSession
                    }
                    let blockedIDs = WorkoutPlanning.blockedExerciseIDs(
                        in: session,
                        painFlags: input.painFlags
                    )
                    var exerciseIDs = session.exercises
                        .map(\.id)
                        .filter { !blockedIDs.contains($0) }
                    var shortened = false
                    if let preserved = existingForDay?.workout,
                       preserved.programID == program.id,
                       preserved.sessionTemplateID == session.id,
                       preserved.isShortened {
                        exerciseIDs = preserved.exerciseIDs.filter {
                            exerciseIDs.contains($0)
                        }
                        shortened = true
                    }
                    scheduledMission = workoutMission(
                        base: mission,
                        session: session,
                        exerciseIDs: exerciseIDs,
                        shortenedDuration: shortened
                            ? existingForDay?.durationMinutes
                            : nil
                    )
                    workoutMetadata = ScheduledWorkoutMetadata(
                        programID: program.id,
                        sessionTemplateID: session.id,
                        exerciseIDs: exerciseIDs,
                        blockedExerciseIDs: blockedIDs,
                        isShortened: shortened
                    )
                    sessionOffset += 1
                }
                candidates.append(
                    Candidate(
                        mission: scheduledMission,
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
                        repeatedMissCause: latestMissCause(for: mission),
                        workout: workoutMetadata,
                        workoutSequence: workoutMetadata == nil
                            ? nil
                            : sessionOffset - 1
                    )
                )
            }
            for (recoveryIndex, recoveryWindow) in
                recoveryWindows.enumerated()
            {
                let recoveryStart = recoveryWindow.earliest ?? horizonStart
                let recoveryEnd = recoveryWindow.latest ?? horizonEnd
                let eligibleDays = dayStarts.filter { day in
                    awakeEnd(for: day) > recoveryStart
                        && awakeStart(for: day) < recoveryEnd
                }
                var scheduledMission = mission
                var workoutMetadata: ScheduledWorkoutMetadata?
                if let program,
                   selectedSessions.indices.contains(sessionOffset) {
                    let session = selectedSessions[sessionOffset]
                    let blockedIDs = WorkoutPlanning.blockedExerciseIDs(
                        in: session,
                        painFlags: input.painFlags
                    )
                    let exerciseIDs = session.exercises
                        .map(\.id)
                        .filter { !blockedIDs.contains($0) }
                    scheduledMission = workoutMission(
                        base: mission,
                        session: session,
                        exerciseIDs: exerciseIDs
                    )
                    workoutMetadata = ScheduledWorkoutMetadata(
                        programID: program.id,
                        sessionTemplateID: session.id,
                        exerciseIDs: exerciseIDs,
                        blockedExerciseIDs: blockedIDs
                    )
                }
                candidates.append(
                    Candidate(
                        mission: scheduledMission,
                        routineID: nil,
                        occurrenceKey:
                            "workout.\(workout.id.rawValue.uuidString).recovery.\(timestampKey(recoveryStart)).\(recoveryIndex)",
                        stage: 3,
                        preferredDayStarts: eligibleDays,
                        preferredStartMinute: workout.preferredStartMinute
                            ?? preferredMinute(for: mission),
                        earliest: recoveryStart,
                        latest: recoveryEnd,
                        existingBlock: nil,
                        repeatedMissCause: latestMissCause(for: mission),
                        workout: workoutMetadata,
                        workoutSequence: workoutMetadata == nil
                            ? nil
                            : sessionOffset
                    )
                )
                if workoutMetadata != nil {
                    sessionOffset += 1
                }
            }
        }
        return candidates
    }

    private func workoutMission(
        base: Mission,
        session: WorkoutSessionTemplate,
        exerciseIDs: [EntityID],
        shortenedDuration: Int? = nil
    ) -> Mission {
        var mission = base
        let exercises = session.exercises.filter {
            exerciseIDs.contains($0.id)
        }
        mission.title = session.title
        mission.miniGoals = exercises.map { exercise in
            MissionStep(
                id: exercise.id,
                title: "\(exercise.title) · \(exercise.sets.count) sets"
            )
        }
        mission.estimatedDurationMinutes = max(
            shortenedDuration ?? session.estimatedDurationMinutes,
            10
        )
        mission.minimumUsefulBlockMinutes = min(
            mission.minimumUsefulBlockMinutes,
            mission.estimatedDurationMinutes
        )
        mission.bodyAreaTags = Array(
            Set(exercises.flatMap(\.bodyAreaTags))
        ).sorted()
        if exercises.contains(where: { $0.physicalLoad == .heavy }) {
            mission.physicalLoad = .heavy
        } else if exercises.contains(where: {
            $0.physicalLoad == .moderate
        }) {
            mission.physicalLoad = .moderate
        } else if exercises.contains(where: {
            $0.physicalLoad == .light
        }) {
            mission.physicalLoad = .light
        } else {
            mission.physicalLoad = .none
        }
        return mission
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
                let supermarketShift = compatibleSupermarketShift(
                    for: routine,
                    window: defaultWindow
                )
                if supermarketShift != nil {
                    mission.travelBeforeMinutes = 0
                    mission.travelAfterMinutes =
                        input.profile.transitions.workTravelEachWayMinutes
                }
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
                        stage: supermarketShift != nil
                            ? min(stage(for: routine), 2)
                            : isShoppingRoutine(routine)
                                && !input.shoppingItems.isEmpty
                                ? min(stage(for: routine), 6)
                                : stage(for: routine),
                        preferredDayStarts: eligibleDays.isEmpty
                            ? [calendar.startOfDay(for: nominal)]
                            : supermarketShift.map {
                                [calendar.startOfDay(for: $0.end)]
                            } ?? eligibleDays,
                        preferredStartMinute: isTriggered
                            ? nil
                            : supermarketShift.map(minuteOfDay)
                                ?? routinePreferredMinute(routine),
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
                ),
                !violatesPostMatchRestriction(
                    mission: candidate.mission,
                    start: missionStart,
                    end: end
                ),
                !violatesFootballTrainingLoad(
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
            let anchor = routine.anchorDate.map {
                calendar.startOfDay(for: $0)
            } ?? calendar.date(
                from: DateComponents(year: 2001, month: 1, day: 1)
            ) ?? horizonStart
            let interval = routine.flexibleCadence?.maximumDays
                ?? routine.recurrence.interval
            return dayStarts.filter { day in
                let offset = calendar.dateComponents(
                    [.day],
                    from: anchor,
                    to: day
                ).day ?? 0
                return offset >= 0 && offset.isMultiple(of: interval)
            }
        case .weekly:
            return dayStarts.filter {
                routine.recurrence.weekdays.contains(weekday(for: $0))
            }
        case .monthly:
            if let anchorDate = routine.anchorDate {
                let anchor = calendar.startOfDay(for: anchorDate)
                return dayStarts.filter { day in
                    let months = calendar.dateComponents(
                        [.month],
                        from: anchor,
                        to: day
                    ).month ?? 0
                    return months >= 0
                        && months.isMultiple(
                            of: routine.recurrence.interval
                        )
                        && calendar.component(.day, from: day)
                            == calendar.component(.day, from: anchor)
                }
            }
            addConflict(
                kind: .recurrenceAnchorMissing,
                severity: .warning,
                title: "\(routine.title) needs a monthly anchor",
                explanation: "Set an anchor date so the monthly cadence has a deterministic calendar day. Until then, the planner uses the first day of this horizon and reports the assumption.",
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
        let flexibleLeadDays = routine.flexibleCadence.map {
            max($0.maximumDays - $0.minimumDays, 0)
        } ?? 0
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
        let flexibleStartDay = calendar.date(
            byAdding: .day,
            value: -flexibleLeadDays,
            to: day
        ) ?? day
        let start = max(awakeStart(for: flexibleStartDay), horizonStart)
        let nominalStart = awakeStart(for: day)
        return DateInterval(
            start: start,
            end: min(
                min(
                    nominalStart.addingTimeInterval(
                        TimeInterval(
                            (
                                routine.dueWindowMinutes
                                    + routine.estimatedDurationMinutes
                            ) * 60
                        )
                    ),
                    awakeEnd(for: day)
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
            miniGoals: isShoppingRoutine(routine)
                ? input.shoppingItems.map {
                    MissionStep(
                        id: $0.id,
                        title: [$0.quantity, $0.title]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                        isCompleted: $0.isCompleted
                    )
                }
                : [],
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
        if let workout = candidate.workout,
           workout.exerciseIDs.isEmpty {
            let explanation = workout.blockedExerciseIDs.isEmpty
                ? "The approved session has no executable exercises, so the planner did not invent a replacement."
                : "Every exercise in this approved session materially loads an area with an active pain flag. The session stays blocked until explicit reassessment or clearance."
            omit(
                candidate,
                conflictKind: .recoveryRestricted,
                rule: .painRestriction,
                explanation: explanation
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
        if let workout = candidate.workout,
           !workout.blockedExerciseIDs.isEmpty {
            addDecision(
                kind: .recoveryAdjusted,
                rule: .painRestriction,
                missionID: candidate.mission.id,
                blockID: missionBlock?.id,
                title: candidate.mission.title,
                explanation: "\(workout.blockedExerciseIDs.count) materially affected exercise\(workout.blockedExerciseIDs.count == 1 ? " was" : "s were") kept out of this occurrence. The approved template was not changed.",
                newStart: missionStart
            )
        }
    }

    private func findMissionStart(for candidate: Candidate) -> Date? {
        if let bundled = compatibleBundledStart(for: candidate) {
            return bundled
        }
        let spec = transitionSpec(for: candidate.mission)
        let candidateDays = candidate.preferredDayStarts.isEmpty
            ? dayStarts
            : candidate.preferredDayStarts
        for day in candidateDays {
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
        if candidate.workout != nil,
           blocks.contains(where: {
               $0.category == .gym
                   && $0.kind == .mission
                   && calendar.isDate(
                       $0.start,
                       inSameDayAs: missionStart
                   )
           }) {
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
        if violatesPostMatchRestriction(
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
        if violatesFootballTrainingLoad(
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
                isImmutable: candidate.mission.isExternallyManaged,
                workout: candidate.workout
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
            mission.category == .gym,
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

    private func violatesPostMatchRestriction(
        mission: Mission,
        start: Date,
        end: Date
    ) -> Bool {
        guard mission.category == .gym,
              isHeavyLowerBody(mission) else { return false }
        return input.fixedCommitments
            .filter { $0.category == .football && $0.isFootballMatch }
            .contains(where: { match in
                let restrictedEnd = match.end.addingTimeInterval(
                    24 * 60 * 60
                )
                return overlaps(start, end, match.end, restrictedEnd)
            })
    }

    private func violatesFootballTrainingLoad(
        mission: Mission,
        start: Date,
        end: Date
    ) -> Bool {
        guard mission.category == .gym,
              isHeavyLowerBody(mission) else { return false }
        let fixedTrainingOnDay = input.fixedCommitments.contains {
            $0.category == .football
                && !$0.isFootballMatch
                && (
                    calendar.isDate($0.start, inSameDayAs: start)
                        || overlaps(start, end, $0.start, $0.end)
                )
        }
        if fixedTrainingOnDay { return true }
        let workoutWeekday = weekday(for: start)
        return input.routines.contains { routine in
            guard
                routine.isEnabled,
                routine.category == .football,
                routine.recurrence.frequency == .weekly
            else {
                return false
            }
            let weekdays = routine.recurrence.weekdays.isEmpty
                ? input.profile.footballPattern.trainingWeekdays
                : routine.recurrence.weekdays
            return weekdays.contains(workoutWeekday)
        }
    }

    private func isHeavyLowerBody(_ mission: Mission) -> Bool {
        mission.physicalLoad == .heavy
            && mission.bodyAreaTags.map(normalizedBodyArea).contains(where: {
                lowerBodyAreas.contains($0)
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
        if let leftSequence = left.workoutSequence,
           let rightSequence = right.workoutSequence,
           leftSequence != rightSequence {
            return leftSequence < rightSequence
        }
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

    private func projectCandidates(for mission: Mission) -> [Candidate] {
        let base = candidate(for: mission)
        guard
            let projectID = mission.projectID,
            let project = input.projects.first(where: {
                $0.id == projectID
            })
        else {
            return blocks.contains(where: {
                $0.missionID == mission.id && $0.kind == .mission
            }) ? [] : [base]
        }
        let projectMissions = input.missions
            .filter {
                $0.projectID == projectID
                    && $0.sourceRoutineID == nil
                    && $0.status == .planned
            }
            .sorted(by: { $0.id < $1.id })
        let baseBlockMinutes = max(
            base.mission.estimatedDurationMinutes,
            input.profile.planningPolicy.minimumFocusedBlockMinutes
        )
        let siblingBaseline = projectMissions
            .filter { $0.id != mission.id }
            .map {
                max(
                    $0.estimatedDurationMinutes,
                    input.profile.planningPolicy
                        .minimumFocusedBlockMinutes
                )
            }
            .reduce(0, +)
        let target = projectMissions.first?.id == mission.id
            ? max(
                project.weeklyPlannedMinutes - siblingBaseline,
                baseBlockMinutes
            )
            : baseBlockMinutes
        guard project.weeklyPlannedMinutes > 0 else {
            return blocks.contains(where: {
                $0.missionID == mission.id && $0.kind == .mission
            }) ? [] : [base]
        }
        let completedMinutes = input.completionHistory
            .filter {
                $0.missionID == mission.id
                    && ($0.status == .completed || $0.status == .partial)
                    && $0.completedAt >= horizonStart
                    && $0.completedAt < horizonEnd
            }
            .map(\.actualDurationMinutes)
            .reduce(0, +)
        let lockedMinutes = blocks
            .filter {
                $0.missionID == mission.id && $0.kind == .mission
            }
            .map(\.durationMinutes)
            .reduce(0, +)
        let remaining = max(target - completedMinutes - lockedMinutes, 0)
        guard remaining > 0 else { return [] }
        let blockMinutes = baseBlockMinutes
        let count = min(
            Int(ceil(Double(remaining) / Double(blockMinutes))),
            max(dayStarts.count * 2, 1)
        )
        let existing = input.existingPlan
            .filter { existingBlock in
                existingBlock.missionID == mission.id
                    && existingBlock.kind == .mission
                    && existingBlock.end > input.currentTime
                    && !blocks.contains(where: {
                        $0.id == existingBlock.id
                    })
            }
            .sorted(by: blockOrder)
        let availableDays = dayStarts.filter {
            awakeEnd(for: $0) > input.currentTime
        }
        return (0..<count).map { index in
            var result = base
            result.occurrenceKey =
                "project.\(mission.id.rawValue.uuidString).\(index)"
            if !availableDays.isEmpty {
                let preferredIndex = index % availableDays.count
                result.preferredDayStarts =
                    Array(availableDays[preferredIndex...])
                    + Array(availableDays[..<preferredIndex])
            }
            result.existingBlock = index < existing.count
                ? existing[index]
                : nil
            if index == count - 1, remaining % blockMinutes != 0 {
                result.mission.estimatedDurationMinutes = max(
                    remaining % blockMinutes,
                    result.mission.minimumUsefulBlockMinutes
                )
            }
            return result
        }
    }

    private func isShoppingRoutine(_ routine: Routine) -> Bool {
        let title = routine.title.lowercased()
        return title.contains("grocer") || title.contains("shopping")
    }

    private func isSupermarketCommitment(
        _ commitment: FixedCommitment
    ) -> Bool {
        let context = (
            [commitment.title, commitment.location ?? ""]
                + commitment.contextTags
        )
        .joined(separator: " ")
        .lowercased()
        return context.contains("supermarket")
            || context.contains("grocery")
            || context.contains("aldi")
            || context.contains("lidl")
    }

    private func compatibleSupermarketShift(
        for routine: Routine,
        window: DateInterval
    ) -> FixedCommitment? {
        guard isShoppingRoutine(routine) else { return nil }
        return input.fixedCommitments
            .filter {
                $0.category == .work
                    && isSupermarketCommitment($0)
                    && $0.end >= window.start
                    && $0.end <= window.end
                    && $0.end.addingTimeInterval(
                        TimeInterval(
                            (
                                routine.estimatedDurationMinutes
                                    + input.profile.transitions
                                        .workTravelEachWayMinutes
                            ) * 60
                        )
                    ) <= awakeEnd(
                        for: calendar.startOfDay(for: $0.end)
                    )
            }
            .sorted(by: fixedOrder)
            .first
    }

    private func canBundleShopping(after commitment: FixedCommitment) -> Bool {
        guard
            commitment.category == .work,
            isSupermarketCommitment(commitment)
        else {
            return false
        }
        return input.routines.filter(\.isEnabled).contains { routine in
            guard isShoppingRoutine(routine) else { return false }
            return nominalDates(for: routine).contains { nominal in
                let window = routineWindow(routine, nominalDate: nominal)
                return commitment.end >= window.start
                    && commitment.end <= window.end
                    && commitment.end.addingTimeInterval(
                        TimeInterval(
                            (
                                routine.estimatedDurationMinutes
                                    + input.profile.transitions
                                        .workTravelEachWayMinutes
                            ) * 60
                        )
                    ) <= awakeEnd(
                        for: calendar.startOfDay(for: commitment.end)
                    )
            }
        }
    }

    private func compatibleBundledStart(
        for candidate: Candidate
    ) -> Date? {
        guard
            let routineID = candidate.routineID,
            let routine = input.routines.first(where: { $0.id == routineID })
        else {
            return nil
        }
        if let shift = candidate.preferredDayStarts.first.flatMap({ day in
            input.fixedCommitments.first(where: {
                calendar.isDate($0.end, inSameDayAs: day)
                    && isSupermarketCommitment($0)
                    && isShoppingRoutine(routine)
            })
        }), canPlace(candidate, missionStart: shift.end) {
            return shift.end
        }
        let compatibleIDs = Set(routine.compatibleRoutineIDs)
        guard !compatibleIDs.isEmpty else { return nil }
        let compatibleBlocks = blocks
            .filter { block in
                guard
                    block.kind == .mission,
                    let missionID = block.missionID,
                    let otherMission = generatedMissions.first(where: {
                        $0.id == missionID
                    }),
                    let otherRoutineID = otherMission.sourceRoutineID
                else {
                    return false
                }
                return compatibleIDs.contains(otherRoutineID)
            }
            .sorted(by: blockOrder)
        for block in compatibleBlocks {
            if canPlace(candidate, missionStart: block.end) {
                return block.end
            }
            let before = block.start.addingTimeInterval(
                -TimeInterval(
                    candidate.mission.estimatedDurationMinutes * 60
                )
            )
            if canPlace(candidate, missionStart: before) {
                return before
            }
        }
        return nil
    }

    private func minuteOfDay(_ commitment: FixedCommitment) -> Int {
        calendar.component(.hour, from: commitment.end) * 60
            + calendar.component(.minute, from: commitment.end)
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
        if let routineID = candidate.routineID {
            let title = candidate.mission.title.lowercased()
            if title.contains("grocer")
                || title.contains("meal preparation")
                || input.routines.first(where: {
                    $0.id == routineID
                })?.compatibleRoutineIDs.isEmpty == false {
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
            if title.contains("grocer") || title.contains("shopping") {
                let itemText = input.shoppingItems.isEmpty
                    ? ""
                    : " for \(input.shoppingItems.count) pending item\(input.shoppingItems.count == 1 ? "" : "s")"
                if input.fixedCommitments.contains(where: {
                    isSupermarketCommitment($0)
                        && calendar.isDate(
                            $0.end,
                            inSameDayAs: candidate.preferredDayStarts.first
                                ?? horizonStart
                        )
                }) {
                    return "Combined shopping\(itemText) with a supermarket work shift inside the routine's due window to avoid a separate trip."
                }
                return "Placed shopping\(itemText) inside its flexible due window and kept compatible household work close by."
            }
            if title.contains("grocer")
                || title.contains("meal preparation") {
                return "Placed inside its due window beside compatible food and household work to reduce fragmentation."
            }
            if let routine = candidate.routineID.flatMap({ routineID in
                input.routines.first(where: { $0.id == routineID })
            }), !routine.compatibleRoutineIDs.isEmpty {
                let note = routine.bundlingNote.isEmpty
                    ? ""
                    : " \(routine.bundlingNote)"
                return "Placed inside its due window near compatible recurring work to reduce fragmentation." + note
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
