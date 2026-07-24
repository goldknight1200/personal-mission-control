import MissionControlCore
import SwiftUI

struct VoiceCommandFlowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var capture: VoiceCaptureViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var transcriptIsFocused: Bool
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            Group {
                switch capture.phase {
                case .review:
                    reviewView
                case .confirmation:
                    confirmationView
                case .completed:
                    completionView
                case .requestingPermission, .recording, .transcribing:
                    ProgressView("Finishing transcript…")
                case .idle, .failed:
                    ContentUnavailableView(
                        "Voice capture ended",
                        systemImage: "mic.slash",
                        description: Text("No command was applied.")
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        capture.dismissReview()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(capture.phase == .confirmation)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if capture.phase == .review,
               capture.rawTranscript.isEmpty,
               capture.confirmedTranscript.isEmpty {
                isEditing = true
                transcriptIsFocused = true
            }
        }
    }

    private var navigationTitle: String {
        switch capture.phase {
        case .confirmation: "Confirm changes"
        case .completed: "Command applied"
        default: "Review transcript"
        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nothing is sent on release", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let onDevice = capture.usedOnDeviceRecognition {
                    Label(
                        onDevice
                            ? "Transcribed on device"
                            : "Apple system speech fallback was used",
                        systemImage: onDevice ? "iphone" : "network"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                TextEditor(text: $capture.confirmedTranscript)
                    .focused($transcriptIsFocused)
                    .disabled(!isEditing)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(isEditing ? 0.075 : 0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isEditing ? Color.accentColor.opacity(0.55) : .clear,
                                lineWidth: 1
                            )
                    )
            }

            if let error = capture.reviewError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Retry") {
                    capture.retry()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(isEditing ? "Done editing" : "Edit") {
                    isEditing.toggle()
                    transcriptIsFocused = isEditing
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Send", action: sendTranscript)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        capture.confirmedTranscript
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
            }
        }
        .padding(22)
    }

    private var confirmationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(
                    "Review the schedule consequences before applying.",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.headline)
                .foregroundStyle(.orange)

                if let command = capture.pendingCommand {
                    commandSummary(command)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        capture.editTranscript()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Confirm & Apply", action: confirmCommand)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(22)
        }
    }

    @ViewBuilder
    private func commandSummary(_ command: StructuredCommand) -> some View {
        section(title: "Detected") {
            HStack {
                Text("Overall confidence")
                Spacer()
                Text(command.confidence, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
            }
            Divider()
            ForEach(Array(command.detectedIntents.enumerated()), id: \.offset) { _, intent in
                HStack {
                    Text(intent.kind.displayName)
                    Spacer()
                    Text(intent.confidence, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                }
            }
        }

        section(title: "Proposed changes") {
            ForEach(Array(command.proposedMutations.enumerated()), id: \.offset) { _, mutation in
                Label(mutation.summary, systemImage: "arrow.right.circle")
            }
        }

        if command.affectedScheduleRange.start != nil
            || command.affectedScheduleRange.end != nil {
            section(title: "Affected schedule") {
                Text(affectedRange(command.affectedScheduleRange))
                    .foregroundStyle(.secondary)
            }
        }

        if !command.confirmationRequirement.reasons.isEmpty {
            section(title: "Why confirmation is required") {
                ForEach(command.confirmationRequirement.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "checkmark.shield")
                }
            }
        }

        if !command.warnings.isEmpty {
            section(title: "Warnings & consequences") {
                ForEach(command.warnings) { warning in
                    Label(
                        warning.message,
                        systemImage: warning.severity == .consequence
                            ? "exclamationmark.triangle.fill"
                            : "info.circle"
                    )
                    .foregroundStyle(
                        warning.severity == .consequence ? Color.orange : Color.secondary
                    )
                }
            }
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .missionControlCard()
    }

    private var completionView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(capture.successMessage ?? "Change applied locally.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Done") {
                capture.dismissReview()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }

    private func sendTranscript() {
        transcriptIsFocused = false
        isEditing = false
        handle(
            model.submitVoiceCommand(
                rawTranscript: capture.rawTranscript,
                confirmedTranscript: capture.confirmedTranscript
            )
        )
    }

    private func confirmCommand() {
        guard let command = capture.pendingCommand else {
            capture.editTranscript()
            capture.showReviewError("The prepared command is no longer available.")
            return
        }
        handle(model.confirmVoiceCommand(command))
    }

    private func handle(_ submission: VoiceCommandSubmission) {
        switch submission {
        case let .applied(result):
            capture.showApplied(result)
        case let .confirmationRequired(command):
            capture.showConfirmation(command)
        case let .rejected(message):
            capture.editTranscript()
            capture.showReviewError(message)
        }
    }

    private func affectedRange(_ range: AffectedScheduleRange) -> String {
        switch (range.start, range.end) {
        case let (start?, end?):
            "\(start.formatted(date: .abbreviated, time: .shortened)) – "
                + "\(end.formatted(date: .abbreviated, time: .shortened))"
        case let (start?, nil):
            "From \(start.formatted(date: .abbreviated, time: .shortened))"
        case let (nil, end?):
            "Until \(end.formatted(date: .abbreviated, time: .shortened))"
        case (nil, nil):
            "No schedule range"
        }
    }
}
