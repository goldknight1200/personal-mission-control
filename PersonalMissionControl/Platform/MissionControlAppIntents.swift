import AppIntents
import Foundation
import MissionControlCore

extension Notification.Name {
    static let missionControlCaptureRequested = Notification.Name(
        "missionControlCaptureRequested"
    )
}

@MainActor
final class MissionControlIntentBridge {
    static let shared = MissionControlIntentBridge()
    private static let pendingCaptureKey =
        "MissionControl.PendingCaptureIntent"

    private weak var model: AppModel?

    private init() {}

    func configure(model: AppModel) {
        self.model = model
    }

    func whatsNext(at date: Date = Date()) -> String {
        guard let model else {
            return "Open Mission Control to load the local plan."
        }
        let blocks = model.snapshot.scheduleBlocks.sorted {
            $0.start < $1.start
        }
        guard
            let block = ScheduleTimeline.currentBlock(
                in: blocks,
                at: date
            ) ?? blocks.first(where: { $0.start > date })
        else {
            return "Nothing else is planned right now."
        }
        let prefix = block.start <= date && date < block.end
            ? "Current"
            : "Next"
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(prefix): \(block.title) at \(formatter.string(from: block.start))."
    }

    func addTask(_ title: String) -> String {
        guard let model else {
            return "Open Mission Control before adding an item."
        }
        let trimmed = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return "No item was added because the task was empty."
        }
        model.addChecklistItem(kind: .today, title: trimmed)
        return "Added \(trimmed) to Today."
    }

    func addShoppingItem(_ title: String) -> String {
        guard let model else {
            return "Open Mission Control before adding a shopping item."
        }
        let trimmed = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return "No item was added because the shopping item was empty."
        }
        model.addChecklistItem(kind: .shopping, title: trimmed)
        return "Added \(trimmed) to Shopping."
    }

    func completeCurrent(at date: Date = Date()) -> String {
        guard let model else {
            return "Open Mission Control to load the current mission."
        }
        guard
            let title = model.completeCurrentMissionFromSystemAction(at: date)
        else {
            return "There is no current mission to complete."
        }
        return "Completed \(title)."
    }

    func replanToday(at date: Date = Date()) -> String {
        guard let model else {
            return "Open Mission Control to load the local plan."
        }
        return model.replanTodayFromSystemAction(at: date)
            ? "Today has been replanned."
            : "The local plan could not be updated."
    }

    func requestCapture() {
        UserDefaults.standard.set(
            true,
            forKey: Self.pendingCaptureKey
        )
        NotificationCenter.default.post(
            name: .missionControlCaptureRequested,
            object: nil
        )
    }

    func consumeCaptureRequest() -> Bool {
        let requested = UserDefaults.standard.bool(
            forKey: Self.pendingCaptureKey
        )
        if requested {
            UserDefaults.standard.removeObject(
                forKey: Self.pendingCaptureKey
            )
        }
        return requested
    }
}

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next?"
    static let description = IntentDescription(
        "Returns the current or next block from the local Mission Control plan."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let value = await MissionControlIntentBridge.shared.whatsNext()
        return .result(value: value)
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a task or item"
    static let description = IntentDescription(
        "Adds a one-off item to the local Today checklist."
    )

    @Parameter(title: "Task")
    var task: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$task) to Today")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let value = await MissionControlIntentBridge.shared.addTask(task)
        return .result(value: value)
    }
}

struct AddShoppingItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a shopping item"
    static let description = IntentDescription(
        "Adds an item to the local Shopping checklist."
    )

    @Parameter(title: "Item")
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to Shopping")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let value = await MissionControlIntentBridge.shared
            .addShoppingItem(item)
        return .result(value: value)
    }
}

struct CompleteCurrentMissionIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete current mission"
    static let description = IntentDescription(
        "Marks the currently scheduled mission complete."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let value = await MissionControlIntentBridge.shared.completeCurrent()
        return .result(value: value)
    }
}

struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open voice capture"
    static let description = IntentDescription(
        "Opens Mission Control's reviewed capture flow."
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MissionControlIntentBridge.shared.requestCapture()
        return .result()
    }
}

struct ReplanTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Replan today"
    static let description = IntentDescription(
        "Rebuilds today's local deterministic plan."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let value = await MissionControlIntentBridge.shared.replanToday()
        return .result(value: value)
    }
}

struct MissionControlShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "Ask \(.applicationName) what's next"
            ],
            shortTitle: "What's next?",
            systemImageName: "arrow.right.circle"
        )
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add an item in \(.applicationName)"
            ],
            shortTitle: "Add task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Add groceries in \(.applicationName)"
            ],
            shortTitle: "Add shopping item",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: CompleteCurrentMissionIntent(),
            phrases: [
                "Complete my current mission in \(.applicationName)"
            ],
            shortTitle: "Complete mission",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: OpenCaptureIntent(),
            phrases: [
                "Open capture in \(.applicationName)",
                "Start voice capture in \(.applicationName)"
            ],
            shortTitle: "Open capture",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: ReplanTodayIntent(),
            phrases: [
                "Replan today in \(.applicationName)"
            ],
            shortTitle: "Replan today",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
