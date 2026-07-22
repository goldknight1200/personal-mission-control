import MissionControlCore
import SwiftUI

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

                switch selectedRange {
                case .day:
                    List(model.snapshot.scheduleBlocks.sorted(by: { $0.start < $1.start })) { block in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    block.kind.isTransition
                                        ? Color.secondary.opacity(0.4)
                                        : model.snapshot.profile.color(for: block.category)
                                )
                                .frame(width: 4, height: 38)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(block.title)
                                    .foregroundStyle(block.kind.isTransition ? Color.secondary : Color.primary)
                                Text(block.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MissionControlFormatters.timeRange(block, profile: model.snapshot.profile))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .listStyle(.plain)
                case .week:
                    planPlaceholder(
                        title: "Seven-day planning arrives in Phase 2",
                        detail: "The domain already stores a seven-day horizon; deterministic placement is intentionally not implemented yet."
                    )
                case .month:
                    planPlaceholder(
                        title: "Month overview is not active yet",
                        detail: "This is an honest navigation destination, not generated schedule data."
                    )
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ScreenMenuButton(action: openMenu)
                }
            }
        }
    }

    private func planPlaceholder(title: String, detail: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "calendar")
        } description: {
            Text(detail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
