import MissionControlCore
import SwiftUI

struct HistoryConsistencyView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let summary = model.weeklyConsistency()

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("This week")
                    .font(.title2.weight(.semibold))

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    metric(
                        "Football",
                        "\(summary.footballCompleted)/\(summary.footballPlanned)",
                        "sessions",
                        "figure.soccer"
                    )
                    metric(
                        "Gym",
                        "\(summary.gymCompleted)",
                        "target \(summary.gymTargetMinimum)–\(summary.gymTargetPreferred)",
                        "dumbbell"
                    )
                    metric(
                        "Project",
                        duration(summary.projectActualMinutes),
                        "of \(duration(summary.projectPlannedMinutes))",
                        "hammer"
                    )
                    metric(
                        "Nutrition",
                        "\(summary.nutritionTargetDays)",
                        "target days",
                        "fork.knife"
                    )
                    metric(
                        "Sleep",
                        "\(summary.sleepTargetNights)",
                        "target nights",
                        "moon.zzz"
                    )
                }

                Text("Recent execution")
                    .font(.headline)
                    .padding(.top, 4)

                if model.snapshot.completions.isEmpty {
                    ContentUnavailableView(
                        "No execution history yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Completed, partial, and skipped missions will appear here.")
                    )
                } else {
                    ForEach(
                        model.snapshot.completions.sorted(by: {
                            $0.completedAt > $1.completedAt
                        })
                    ) { record in
                        historyRow(record)
                    }
                }
            }
            .padding(20)
        }
    }

    private func metric(
        _ title: String,
        _ value: String,
        _ detail: String,
        _ icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .missionControlCard()
    }

    private func historyRow(_ record: CompletionRecord) -> some View {
        let mission = model.snapshot.mission(withID: record.missionID)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(mission?.title ?? "Mission")
                    .font(.headline)
                Spacer()
                Text(record.status.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color(for: record.status))
            }
            HStack {
                Text(record.completedAt, style: .date)
                Spacer()
                Text("\(record.actualDurationMinutes) actual / \(record.plannedDurationMinutes) planned min")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let reason = record.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .missionControlCard()
    }

    private func duration(_ minutes: Int) -> String {
        if minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h"
        }
        return String(format: "%.1fh", Double(minutes) / 60)
    }

    private func color(for status: MissionOutcomeStatus) -> Color {
        switch status {
        case .completed: .green
        case .partial: .orange
        case .skipped: .secondary
        }
    }
}
