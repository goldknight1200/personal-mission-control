import Foundation

public struct EveningExecutionSummary: Equatable, Sendable {
    public var completedCount: Int
    public var partialCount: Int
    public var skippedCount: Int
    public var unresolvedBlocks: [ScheduleBlock]

    public init(
        completedCount: Int,
        partialCount: Int,
        skippedCount: Int,
        unresolvedBlocks: [ScheduleBlock]
    ) {
        self.completedCount = completedCount
        self.partialCount = partialCount
        self.skippedCount = skippedCount
        self.unresolvedBlocks = unresolvedBlocks
    }
}

public enum DailyReflection {
    public static func shouldShowMorning(
        snapshot: MissionControlSnapshot,
        at date: Date
    ) -> Bool {
        let calendar = calendar(for: snapshot.profile.timeZoneIdentifier)
        let hour = calendar.component(.hour, from: date)
        guard (5..<12).contains(hour) else { return false }
        return !snapshot.dailyCheckIns.contains(where: {
            $0.kind == .morning && calendar.isDate($0.recordedAt, inSameDayAs: date)
        })
    }

    public static func shouldShowEvening(
        snapshot: MissionControlSnapshot,
        at date: Date
    ) -> Bool {
        let calendar = calendar(for: snapshot.profile.timeZoneIdentifier)
        return calendar.component(.hour, from: date) >= 18
    }

    public static func eveningSummary(
        snapshot: MissionControlSnapshot,
        at date: Date
    ) -> EveningExecutionSummary {
        let calendar = calendar(for: snapshot.profile.timeZoneIdentifier)
        let records = snapshot.completions.filter {
            calendar.isDate($0.completedAt, inSameDayAs: date)
        }
        let unresolved = snapshot.scheduleBlocks.filter { block in
            guard
                let missionID = block.missionID,
                block.end <= date,
                calendar.isDate(block.start, inSameDayAs: date),
                let mission = snapshot.mission(withID: missionID),
                mission.status == .planned || mission.status == .inProgress
            else {
                return false
            }
            return !snapshot.completions.contains(where: {
                $0.scheduleBlockID == block.id
            }) && !snapshot.unresolvedDispositions.contains(where: {
                $0.scheduleBlockID == block.id
            })
        }
        .sorted(by: { $0.start < $1.start })

        return EveningExecutionSummary(
            completedCount: records.filter { $0.status == .completed }.count,
            partialCount: records.filter { $0.status == .partial }.count,
            skippedCount: records.filter { $0.status == .skipped }.count,
            unresolvedBlocks: unresolved
        )
    }

    private static func calendar(for timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }
}

public enum RepeatedMissAnalyzer {
    public static func diagnostic(
        snapshot: MissionControlSnapshot,
        missionID: EntityID,
        at date: Date,
        threshold: Int = 3,
        lookbackDays: Int = 28
    ) -> RepeatedMissDiagnostic? {
        guard
            threshold > 0,
            let mission = snapshot.mission(withID: missionID)
        else {
            return nil
        }
        let cutoff = date.addingTimeInterval(-TimeInterval(lookbackDays * 24 * 60 * 60))
        let missionIDs = Set(
            snapshot.missions
                .filter { $0.category == mission.category }
                .map(\.id)
        )
        let missCount = snapshot.completions.filter {
            $0.status == .skipped
                && missionIDs.contains($0.missionID)
                && $0.completedAt >= cutoff
                && $0.completedAt <= date
        }.count
        guard missCount >= threshold else { return nil }

        let hasRecentDiagnosis = snapshot.missDiagnostics.contains {
            $0.category == mission.category
                && $0.recordedAt >= cutoff
                && $0.recordedAt <= date
        }
        guard !hasRecentDiagnosis else { return nil }

        return RepeatedMissDiagnostic(
            missionID: missionID,
            missionTitle: mission.title,
            category: mission.category,
            recentMissCount: missCount
        )
    }
}

public enum WeeklyConsistencyAggregator {
    public static func summarize(
        snapshot: MissionControlSnapshot,
        containing date: Date
    ) -> WeeklyConsistencySummary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: snapshot.profile.timeZoneIdentifier
        ) ?? .current
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 24 * 60 * 60)

        let blocks = snapshot.scheduleBlocks.filter {
            $0.start >= interval.start && $0.start < interval.end
        }
        let footballFixed = snapshot.fixedCommitments.filter {
            $0.category == .football
                && $0.start >= interval.start
                && $0.start < interval.end
        }.count
        let records = snapshot.completions.filter {
            $0.completedAt >= interval.start && $0.completedAt < interval.end
        }
        let missionByID = Dictionary(
            uniqueKeysWithValues: snapshot.missions.map { ($0.id, $0) }
        )
        let completedRecords = records.filter {
            $0.status == .completed || $0.status == .partial
        }

        let footballPlanned = blocks.filter {
            $0.missionID != nil && $0.category == .football
        }.count + footballFixed
        let footballCompleted = completedRecords.filter {
            missionByID[$0.missionID]?.category == .football
        }.count
        let gymCompleted = completedRecords.filter {
            missionByID[$0.missionID]?.category == .gym
        }.count
        let projectPlanned = blocks.filter {
            $0.missionID != nil && $0.category == .project
        }.reduce(0) { $0 + $1.durationMinutes }
        let projectActual = completedRecords.filter {
            missionByID[$0.missionID]?.category == .project
        }.reduce(0) { $0 + $1.actualDurationMinutes }

        var nutritionDays = Set<Date>()
        for checkIn in snapshot.dailyCheckIns where checkIn.nutritionTargetMet == true {
            guard checkIn.recordedAt >= interval.start && checkIn.recordedAt < interval.end else {
                continue
            }
            nutritionDays.insert(calendar.startOfDay(for: checkIn.recordedAt))
        }
        let nutritionRecords = completedRecords.filter {
            missionByID[$0.missionID]?.category == .nutrition
        }
        let nutritionByDay = Dictionary(grouping: nutritionRecords) {
            calendar.startOfDay(for: $0.completedAt)
        }
        for (day, dayRecords) in nutritionByDay
        where dayRecords.count >= snapshot.profile.nutritionTargets.substantialMeals {
            nutritionDays.insert(day)
        }

        let sleepTargetNights = snapshot.dailyCheckIns.filter {
            guard
                let minutes = $0.sleepDurationMinutes,
                minutes >= snapshot.profile.planningPolicy.sleepTargetMinutes
            else {
                return false
            }
            return $0.recordedAt >= interval.start && $0.recordedAt < interval.end
        }.count

        return WeeklyConsistencySummary(
            weekStart: interval.start,
            weekEnd: interval.end,
            footballCompleted: footballCompleted,
            footballPlanned: footballPlanned,
            gymCompleted: gymCompleted,
            gymTargetMinimum: snapshot.profile.gymWeeklyTarget.minimum,
            gymTargetPreferred: snapshot.profile.gymWeeklyTarget.preferred,
            projectActualMinutes: projectActual,
            projectPlannedMinutes: projectPlanned,
            nutritionTargetDays: nutritionDays.count,
            sleepTargetNights: sleepTargetNights
        )
    }
}
