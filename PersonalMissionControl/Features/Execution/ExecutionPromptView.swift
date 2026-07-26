import MissionControlCore
import SwiftUI

struct ExecutionPromptView: View {
    @ObservedObject var model: AppModel
    let prompt: MissionExecutionPrompt

    @State private var minutesAgo = 15

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch prompt {
                    case let .alreadyStarted(
                        missionID,
                        scheduleBlockID,
                        referenceDate,
                        suggestedMinutesAgo
                    ):
                        alreadyStartedContent(
                            missionID: missionID,
                            scheduleBlockID: scheduleBlockID,
                            referenceDate: referenceDate
                        )
                        .onAppear {
                            minutesAgo = suggestedMinutesAgo
                        }

                    case let .recovery(proposal, referenceDate):
                        recoveryContent(
                            proposal: proposal,
                            referenceDate: referenceDate
                        )

                    case let .confirmSkip(
                        missionID,
                        scheduleBlockID,
                        missionTitle,
                        consequence,
                        shortenedWorkout,
                        referenceDate
                    ):
                        skipConfirmationContent(
                            missionID: missionID,
                            scheduleBlockID: scheduleBlockID,
                            missionTitle: missionTitle,
                            consequence: consequence,
                            shortenedWorkout: shortenedWorkout,
                            referenceDate: referenceDate
                        )

                    case let .diagnostic(diagnostic):
                        diagnosticContent(diagnostic)
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.dismissExecutionPrompt)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isConsequentialSkip)
    }

    private var title: String {
        switch prompt {
        case .alreadyStarted: "Correct actual start"
        case .recovery: "Replan"
        case .confirmSkip: "Confirm skip"
        case .diagnostic: "What got in the way?"
        }
    }

    private var isConsequentialSkip: Bool {
        if case .confirmSkip = prompt { return true }
        return false
    }

    @ViewBuilder
    private func alreadyStartedContent(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        referenceDate: Date
    ) -> some View {
        Text("When did you actually begin?")
            .font(.title2.weight(.semibold))

        Stepper(value: $minutesAgo, in: 0...180, step: 5) {
            VStack(alignment: .leading, spacing: 4) {
                Text(minutesAgo == 0 ? "Just now" : "\(minutesAgo) minutes ago")
                    .font(.headline)
                Text("This corrects history and replans the remaining day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .missionControlCard()

        Button {
            model.confirmAlreadyStarted(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                minutesAgo: minutesAgo,
                at: referenceDate
            )
        } label: {
            Text("Confirm actual start")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private func recoveryContent(
        proposal: MissionRecoveryProposal,
        referenceDate: Date
    ) -> some View {
        Text(proposal.missionTitle)
            .font(.title2.weight(.semibold))

        Text("Choose where this mission goes. Each option records the decision and sends a typed replan request.")
            .foregroundStyle(.secondary)

        ForEach(proposal.alternatives) { alternative in
            Button {
                model.applyRecoveryAlternative(
                    alternative.kind,
                    proposal: proposal,
                    at: referenceDate
                )
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(alternative.kind.displayName)
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    Text(alternative.consequence)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let recommendation = alternative.recommendation {
                        Label(recommendation, systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .missionControlCard()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func skipConfirmationContent(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        missionTitle: String,
        consequence: String,
        shortenedWorkout: ShortenedWorkoutSuggestion?,
        referenceDate: Date
    ) -> some View {
        Label("Protected or consequential mission", systemImage: "shield.lefthalf.filled")
            .font(.headline)
            .foregroundStyle(.orange)

        Text(missionTitle)
            .font(.title2.weight(.semibold))

        Text(consequence)
            .foregroundStyle(.secondary)
            .missionControlCard()

        Text("The planner will not weaken the goal automatically. Confirm only if skipping is the deliberate choice.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        if let shortenedWorkout {
            Button {
                model.applyShortenedWorkoutSuggestion(
                    scheduleBlockID: scheduleBlockID,
                    suggestion: shortenedWorkout,
                    at: referenceDate
                )
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Do shortened approved session")
                        .font(.headline)
                    Text(shortenedWorkout.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
        }

        Button(role: .destructive) {
            model.confirmSkip(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                at: referenceDate
            )
        } label: {
            Text("Skip anyway")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private func diagnosticContent(_ diagnostic: RepeatedMissDiagnostic) -> some View {
        Text("\(diagnostic.missionTitle) has been missed \(diagnostic.recentMissCount) times recently.")
            .font(.title3.weight(.semibold))

        Text("What was the main cause? This shapes future recommendations without weakening protected goals.")
            .foregroundStyle(.secondary)

        ForEach(MissionMissCause.allCases) { cause in
            Button {
                model.classifyRepeatedMiss(diagnostic, cause: cause)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(cause.displayName)
                        .font(.headline)
                    Text(cause.recommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .missionControlCard()
            }
            .buttonStyle(.plain)
        }
    }
}
