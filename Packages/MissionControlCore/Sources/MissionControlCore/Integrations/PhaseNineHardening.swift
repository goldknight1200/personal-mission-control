import Foundation

public enum WorkShiftImageImportCoordinator {
    public static func review(
        recognition: WorkShiftImageRecognition,
        title: String,
        location: String?,
        referenceDate: Date,
        timeZoneIdentifier: String,
        existingCommitments: [FixedCommitment],
        minimumConfidence: Double = 0.72
    ) -> WorkShiftImageReview {
        let usableLines = recognition.lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.confidence >= minimumConfidence
        }
        let recognizedText = usableLines
            .map(\.text)
            .joined(separator: "\n")
        let parsed = WorkShiftBatchParser().parse(
            recognizedText,
            title: title,
            location: location,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            existingCommitments: existingCommitments
        )
        var ambiguities = recognition.lines
            .filter {
                !$0.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty && $0.confidence < minimumConfidence
            }
            .map {
                "Low-confidence text was not used: \"\($0.text)\""
            }
        if let unparsed = parsed.unparsedInput {
            ambiguities.append(
                "No reliable date/time range could be extracted from: \"\(unparsed)\""
            )
        }
        if recognition.lines.isEmpty {
            ambiguities.append("No text was detected in the selected image.")
        }
        return WorkShiftImageReview(
            recognizedText: recognizedText,
            parseResult: parsed,
            ambiguities: ambiguities
        )
    }
}

public enum SnapshotIntegrityValidator {
    public static func issues(
        in snapshot: MissionControlSnapshot
    ) -> [SnapshotIntegrityIssue] {
        var issues: [SnapshotIntegrityIssue] = []
        if snapshot.schemaVersion < 1
            || snapshot.schemaVersion
                > MissionControlSnapshot.currentSchemaVersion {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .unsupportedSchema,
                    message:
                        "Snapshot schema \(snapshot.schemaVersion) is not supported."
                )
            )
        }
        if TimeZone(identifier: snapshot.profile.timeZoneIdentifier) == nil {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidTimeZone,
                    message: "The profile time zone is invalid."
                )
            )
        }
        for commitment in snapshot.fixedCommitments
        where !commitment.start.timeIntervalSinceReferenceDate.isFinite
            || !commitment.end.timeIntervalSinceReferenceDate.isFinite
            || commitment.end <= commitment.start {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidInterval,
                    message:
                        "Fixed commitment \(commitment.id.rawValue.uuidString) has an invalid interval."
                )
            )
        }
        for block in snapshot.scheduleBlocks
        where !block.start.timeIntervalSinceReferenceDate.isFinite
            || !block.end.timeIntervalSinceReferenceDate.isFinite
            || block.end <= block.start {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidInterval,
                    message:
                        "Schedule block \(block.id.rawValue.uuidString) has an invalid interval."
                )
            )
        }
        appendDuplicateIssue(
            ids: snapshot.goals.map(\.id),
            collection: "goals",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.projects.map(\.id),
            collection: "projects",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.missions.map(\.id),
            collection: "missions",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.fixedCommitments.map(\.id),
            collection: "fixed commitments",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.scheduleBlocks.map(\.id),
            collection: "schedule blocks",
            to: &issues
        )
        return issues
    }

    private static func appendDuplicateIssue(
        ids: [EntityID],
        collection: String,
        to issues: inout [SnapshotIntegrityIssue]
    ) {
        guard Set(ids).count != ids.count else { return }
        issues.append(
            SnapshotIntegrityIssue(
                kind: .duplicateIdentifier,
                message: "Duplicate identifiers were found in \(collection)."
            )
        )
    }
}

public enum MissionControlBackupService {
    public static func encode(
        snapshot: MissionControlSnapshot,
        exportedAt: Date
    ) throws -> Data {
        let issues = SnapshotIntegrityValidator.issues(in: snapshot)
        guard issues.isEmpty else {
            throw MissionControlBackupError.invalidSnapshot(issues)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            MissionControlBackup(
                exportedAt: exportedAt,
                snapshot: snapshot
            )
        )
    }

    public static func decode(
        _ data: Data,
        maximumBytes: Int = 25_000_000
    ) throws -> MissionControlBackup {
        guard data.count <= maximumBytes else {
            throw MissionControlBackupError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let backup = try decoder.decode(MissionControlBackup.self, from: data)
        guard
            backup.formatVersion
                == MissionControlBackup.currentFormatVersion
        else {
            throw MissionControlBackupError.unsupportedFormat
        }
        let issues = SnapshotIntegrityValidator.issues(in: backup.snapshot)
        guard issues.isEmpty else {
            throw MissionControlBackupError.invalidSnapshot(issues)
        }
        return backup
    }
}

public enum MissionControlBackupError: Error, Equatable {
    case fileTooLarge
    case unsupportedFormat
    case invalidSnapshot([SnapshotIntegrityIssue])
}

public enum SnapshotDatasetProfiler {
    public static func profile(
        _ snapshot: MissionControlSnapshot
    ) -> SnapshotDatasetProfile {
        let workoutSetCount = snapshot.workoutLogs.reduce(into: 0) {
            partial, log in
            partial += log.exerciseLogs.reduce(into: 0) {
                $0 += $1.setLogs.count
            }
        }
        return SnapshotDatasetProfile(
            historyRecordCount:
                snapshot.completions.count
                + snapshot.missionStartRecords.count
                + snapshot.dailyCheckIns.count
                + snapshot.missDiagnostics.count,
            scheduleBlockCount: snapshot.scheduleBlocks.count,
            commandCount: snapshot.commandHistory.count,
            externalItemCount: snapshot.externalCalendarItems.count,
            workoutSetCount: workoutSetCount
        )
    }
}
