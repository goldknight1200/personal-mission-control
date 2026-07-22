import Foundation

public enum ScheduleTimeline {
    public static func currentBlock(in blocks: [ScheduleBlock], at date: Date) -> ScheduleBlock? {
        sorted(blocks).first(where: { $0.start <= date && date < $0.end })
    }

    public static func upcomingBlocks(in blocks: [ScheduleBlock], after date: Date) -> [ScheduleBlock] {
        sorted(blocks).filter { $0.start > date }
    }

    public static func progress(of block: ScheduleBlock, at date: Date) -> Double {
        guard date > block.start else { return 0 }
        guard date < block.end else { return 1 }

        let elapsed = date.timeIntervalSince(block.start)
        let duration = block.end.timeIntervalSince(block.start)
        return min(max(elapsed / duration, 0), 1)
    }

    private static func sorted(_ blocks: [ScheduleBlock]) -> [ScheduleBlock] {
        blocks.sorted {
            if $0.start == $1.start {
                return $0.id < $1.id
            }
            return $0.start < $1.start
        }
    }
}
