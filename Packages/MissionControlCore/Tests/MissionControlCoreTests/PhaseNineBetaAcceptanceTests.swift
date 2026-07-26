import Foundation
import XCTest
@testable import MissionControlCore

final class PhaseNineBetaAcceptanceTests: XCTestCase {
    func testSyntheticWeekAndSuccessiveReplansRemainCoherent()
        throws {
        let monday = localDate(2026, 7, 27, 7, 0)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: monday)
        let projectDeadline = localDate(2026, 8, 2, 18, 0)
        snapshot.projects[0].targetDate = projectDeadline
        if let projectMissionIndex = snapshot.missions.firstIndex(where: {
            $0.projectID == snapshot.projects[0].id
        }) {
            snapshot.missions[projectMissionIndex].deadline =
                projectDeadline
        }
        let workShifts = [
            commitment(
                "Monday supermarket shift",
                .work,
                2026, 7, 27, 9, 0, 14, 0,
                tags: ["supermarket"]
            ),
            commitment(
                "Wednesday work shift",
                .work,
                2026, 7, 29, 9, 0, 14, 0
            ),
            commitment(
                "Friday work shift",
                .work,
                2026, 7, 31, 9, 0, 14, 0
            )
        ]
        let match = FixedCommitment(
            title: "Weekend football match",
            category: .football,
            start: localDate(2026, 8, 1, 15, 0),
            end: localDate(2026, 8, 1, 17, 0),
            location: "Away ground",
            isExternallyManaged: true,
            isFootballMatch: true
        )
        snapshot.fixedCommitments = workShifts + [match]

        _ = NutritionPlanningCoordinator.reconcile(
            snapshot: &snapshot,
            referenceDate: monday
        )
        snapshot.applySchedulingResult(
            SchedulingEngine().makePlan(
                input: PlanningInput(
                    snapshot: snapshot,
                    currentTime: monday
                )
            )
        )

        try assertCoherent(snapshot)
        XCTAssertEqual(
            Set(
                snapshot.scheduleBlocks.compactMap {
                    $0.workout?.sessionTemplateID
                }
            ).count,
            4
        )
        XCTAssertTrue(
            snapshot.scheduleBlocks.contains(where: {
                $0.category == .project && $0.kind == .mission
            })
        )
        XCTAssertGreaterThanOrEqual(
            snapshot.scheduleBlocks.filter {
                $0.category == .football
                    && ($0.kind == .mission || $0.kind == .fixedCommitment)
            }.count,
            3
        )
        XCTAssertTrue(
            snapshot.routines.contains(where: {
                $0.title.localizedCaseInsensitiveContains("laundry")
            })
        )
        XCTAssertTrue(
            snapshot.routines.contains(where: {
                $0.title.localizedCaseInsensitiveContains("trash")
            })
        )
        let plannedTitles = snapshot.scheduleBlocks.map {
            $0.title.lowercased()
        }
        for requiredTitle in [
            "laundry",
            "trash",
            "meal preparation",
            "tidying"
        ] {
            XCTAssertTrue(
                plannedTitles.contains(where: {
                    $0.contains(requiredTitle)
                }),
                "Missing planned household responsibility: \(requiredTitle)"
            )
        }
        XCTAssertTrue(
            plannedTitles.contains(where: { $0.contains("grocer") })
                || snapshot.checklist(ofKind: .shopping)?.items.isEmpty
                    == false
        )
        for need in snapshot.nutritionPlanningNeeds
        where need.clearDeficit
            && need.suggestionDisposition != .declined {
            XCTAssertTrue(
                snapshot.missions.contains(where: {
                    $0.nutritionPlanningNeedID == need.id
                })
            )
        }

        let lateWake = ReplanRequest(
            reason: .lateStart,
            requestedAt: localDate(2026, 7, 28, 11, 0),
            affectedStart: localDate(2026, 7, 28, 11, 0),
            affectedEnd: localDate(2026, 7, 29, 0, 0)
        )
        snapshot.replanRequests.append(lateWake)
        snapshot = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [lateWake]
        )
        let remainingTuesdayMissions = snapshot.scheduleBlocks.filter {
                $0.kind == .mission
                    && calendar.isDate(
                        $0.start,
                        inSameDayAs: localDate(2026, 7, 28, 12, 0)
                    )
                    && $0.end > lateWake.requestedAt
            }
        XCTAssertFalse(remainingTuesdayMissions.isEmpty)
        XCTAssertTrue(
            remainingTuesdayMissions.allSatisfy {
                $0.start >= localDate(2026, 7, 28, 11, 0)
            }
        )

        let missedBlock = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: {
                $0.category == .project
                    && $0.start > localDate(2026, 7, 28, 11, 0)
            })
        )
        let missedStart = missedBlock.start.addingTimeInterval(20 * 60)
        let missedRequest = ReplanRequest(
            reason: .lateStart,
            missionID: missedBlock.missionID,
            requestedAt: missedStart,
            affectedStart: missedStart,
            affectedEnd: calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: missedStart)
            )
        )
        snapshot.replanRequests.append(missedRequest)
        snapshot = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [missedRequest]
        )

        let painReportedAt = localDate(2026, 7, 30, 8, 0)
        snapshot.painFlags.append(
            PainFlag(
                bodyArea: "shoulder",
                reportedAt: painReportedAt,
                note: "Synthetic beta pain report"
            )
        )
        let painRequest = ReplanRequest(
            reason: .painReported,
            requestedAt: painReportedAt,
            affectedStart: painReportedAt,
            affectedEnd: localDate(2026, 8, 3, 0, 0),
            confirmationProvided: true
        )
        snapshot.replanRequests.append(painRequest)
        snapshot = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [painRequest]
        )
        XCTAssertTrue(
            snapshot.schedulingDecisions.contains(where: {
                $0.rule == .painRestriction
            })
        )

        let changedIndex = try XCTUnwrap(
            snapshot.fixedCommitments.firstIndex(where: {
                $0.id == workShifts[1].id
            })
        )
        snapshot.fixedCommitments[changedIndex].end =
            localDate(2026, 7, 29, 16, 0)
        let shiftChange = ReplanRequest(
            reason: .fixedCommitmentChanged,
            requestedAt: localDate(2026, 7, 28, 18, 0),
            affectedStart: localDate(2026, 7, 29, 0, 0),
            affectedEnd: localDate(2026, 7, 30, 0, 0),
            confirmationProvided: true
        )
        snapshot.replanRequests.append(shiftChange)
        snapshot = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [shiftChange]
        )

        try assertCoherent(snapshot)
        let changedBlock = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: {
                $0.fixedCommitmentID == workShifts[1].id
            })
        )
        XCTAssertEqual(changedBlock.end, localDate(2026, 7, 29, 16, 0))
        XCTAssertTrue(
            snapshot.schedulingDecisions.allSatisfy {
                !$0.explanation.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
        )
        XCTAssertTrue(
            snapshot.replanRequests.filter {
                [
                    lateWake.id,
                    missedRequest.id,
                    painRequest.id,
                    shiftChange.id
                ].contains($0.id)
            }.allSatisfy { $0.status == .applied }
        )
    }

    private func assertCoherent(
        _ snapshot: MissionControlSnapshot
    ) throws {
        let issues = SnapshotIntegrityValidator.issues(in: snapshot)
        XCTAssertTrue(
            issues.isEmpty,
            issues.map(\.message).joined(separator: "\n")
        )
        for commitment in snapshot.fixedCommitments {
            let block = try XCTUnwrap(
                snapshot.scheduleBlocks.first(where: {
                    $0.fixedCommitmentID == commitment.id
                }),
                "Missing schedule block for fixed commitment \(commitment.title)"
            )
            XCTAssertEqual(block.start, commitment.start)
            XCTAssertEqual(block.end, commitment.end)
            if commitment.isExternallyManaged {
                XCTAssertTrue(block.isImmutable)
            }
        }
        let ordered = snapshot.scheduleBlocks.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThanOrEqual(
                pair.0.end,
                pair.1.start,
                "\(pair.0.title) overlaps \(pair.1.title)"
            )
        }
        XCTAssertFalse(snapshot.schedulingDecisions.isEmpty)
    }

    private func commitment(
        _ title: String,
        _ category: MissionCategory,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ startHour: Int,
        _ startMinute: Int,
        _ endHour: Int,
        _ endMinute: Int,
        tags: [String] = []
    ) -> FixedCommitment {
        FixedCommitment(
            title: title,
            category: category,
            start: localDate(
                year,
                month,
                day,
                startHour,
                startMinute
            ),
            end: localDate(
                year,
                month,
                day,
                endHour,
                endMinute
            ),
            contextTags: tags
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone =
            TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
