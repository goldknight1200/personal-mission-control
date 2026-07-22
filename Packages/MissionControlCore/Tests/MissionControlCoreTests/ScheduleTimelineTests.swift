import Foundation
import XCTest
@testable import MissionControlCore

final class ScheduleTimelineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    func testCurrentBlockSelectionUsesHalfOpenIntervals() {
        let first = block(title: "First", startOffset: 0, endOffset: 60)
        let second = block(title: "Second", startOffset: 60, endOffset: 120)
        let blocks = [second, first]

        XCTAssertNil(ScheduleTimeline.currentBlock(in: blocks, at: start.addingTimeInterval(-1)))
        XCTAssertEqual(ScheduleTimeline.currentBlock(in: blocks, at: start)?.title, "First")
        XCTAssertEqual(
            ScheduleTimeline.currentBlock(in: blocks, at: start.addingTimeInterval(60))?.title,
            "Second"
        )
        XCTAssertNil(ScheduleTimeline.currentBlock(in: blocks, at: start.addingTimeInterval(120)))
    }

    func testProgressClampsBeforeAndAfterBlock() {
        let subject = block(title: "Subject", startOffset: 0, endOffset: 100)

        XCTAssertEqual(ScheduleTimeline.progress(of: subject, at: start.addingTimeInterval(-10)), 0)
        XCTAssertEqual(ScheduleTimeline.progress(of: subject, at: start), 0)
        XCTAssertEqual(ScheduleTimeline.progress(of: subject, at: start.addingTimeInterval(50)), 0.5)
        XCTAssertEqual(ScheduleTimeline.progress(of: subject, at: start.addingTimeInterval(100)), 1)
        XCTAssertEqual(ScheduleTimeline.progress(of: subject, at: start.addingTimeInterval(200)), 1)
    }

    func testUpcomingBlocksAreChronologicalAndExcludeCurrentBlock() {
        let current = block(title: "Current", startOffset: 0, endOffset: 60)
        let later = block(title: "Later", startOffset: 120, endOffset: 180)
        let next = block(title: "Next", startOffset: 60, endOffset: 120)

        let result = ScheduleTimeline.upcomingBlocks(
            in: [later, current, next],
            after: start.addingTimeInterval(30)
        )

        XCTAssertEqual(result.map(\.title), ["Next", "Later"])
    }

    private func block(title: String, startOffset: TimeInterval, endOffset: TimeInterval) -> ScheduleBlock {
        ScheduleBlock(
            title: title,
            category: .project,
            kind: .mission,
            rigidity: .flexible,
            start: start.addingTimeInterval(startOffset),
            end: start.addingTimeInterval(endOffset)
        )
    }
}
