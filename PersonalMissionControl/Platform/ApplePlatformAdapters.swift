import EventKit
import Foundation
import HealthKit
import ImageIO
import MissionControlCore
import Security
import Vision

final class AppleCalendarService: CalendarProviding {
    var changeHandler: (() -> Void)?

    private let eventStore: EKEventStore
    private var changeObserver: NSObjectProtocol?

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.changeHandler?()
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    func authorizationState(
        for accessLevel: CalendarAccessLevel
    ) async -> PlatformAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess, .authorized:
            return .authorized
        case .writeOnly:
            return accessLevel == .writeOnly ? .authorized : .limited
        @unknown default:
            return .unavailable
        }
    }

    func requestAccess(
        _ accessLevel: CalendarAccessLevel
    ) async -> PlatformAuthorizationState {
        let granted: Bool = await withCheckedContinuation { continuation in
            let completion: EKEventStoreRequestAccessCompletionHandler = {
                granted,
                _ in
                continuation.resume(returning: granted)
            }
            switch accessLevel {
            case .writeOnly:
                eventStore.requestWriteOnlyAccessToEvents(
                    completion: completion
                )
            case .full:
                eventStore.requestFullAccessToEvents(
                    completion: completion
                )
            }
        }
        if !granted {
            return await authorizationState(for: accessLevel)
        }
        return await authorizationState(for: accessLevel)
    }

    func calendars() async -> [CalendarDescriptor] {
        eventStore.calendars(for: .event).map {
            CalendarDescriptor(
                id: $0.calendarIdentifier,
                title: $0.title,
                sourceTitle: $0.source.title,
                allowsContentModifications: $0.allowsContentModifications
            )
        }.sorted {
            if $0.sourceTitle == $1.sourceTitle {
                return $0.title.localizedCaseInsensitiveCompare($1.title)
                    == .orderedAscending
            }
            return $0.sourceTitle.localizedCaseInsensitiveCompare(
                $1.sourceTitle
            ) == .orderedAscending
        }
    }

    func events(
        in interval: DateInterval,
        calendarIDs: [String]
    ) async throws -> [ExternalCalendarEvent] {
        let selected: [EKCalendar]?
        if calendarIDs.isEmpty {
            selected = nil
        } else {
            let requested = Set(calendarIDs)
            selected = eventStore.calendars(for: .event).filter {
                requested.contains($0.calendarIdentifier)
            }
        }
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: selected
        )
        return eventStore.events(matching: predicate).compactMap { event in
            guard
                let start = event.startDate,
                let end = event.endDate,
                end > start
            else {
                return nil
            }
            let title = event.title?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return ExternalCalendarEvent(
                sourceKind: .eventKit,
                sourceIdentifier: event.calendar.calendarIdentifier,
                externalIdentifier: importIdentifier(for: event),
                title: title?.isEmpty == false ? title! : "Calendar event",
                category: category(for: title ?? ""),
                start: start,
                end: end,
                location: event.location,
                isAllDay: event.isAllDay,
                isFootballMatch: isFootballMatch(title ?? ""),
                isAppOwned: event.url?.scheme == "mission-control",
                isCancelled: event.status == .canceled,
                lastModifiedAt: event.lastModifiedDate
            )
        }
    }

    func upsertAppOwnedEvents(
        _ writes: [CalendarEventWrite]
    ) async throws -> [CalendarEventWriteResult] {
        var results: [CalendarEventWriteResult] = []
        let calendars = eventStore.calendars(for: .event)
        for write in writes {
            let event: EKEvent
            var needsSave = false
            let requestedDestination: EKCalendar?
            if let destinationID = write.destinationCalendarID {
                guard
                    let destination = calendars.first(where: {
                        $0.calendarIdentifier == destinationID
                    }),
                    destination.allowsContentModifications
                else {
                    throw PlatformIntegrationError.missingCalendar
                }
                requestedDestination = destination
            } else {
                requestedDestination = nil
            }
            if let identifier = write.externalIdentifier {
                guard
                    let existing = ownedEvent(
                        for: write,
                        preferredIdentifier: identifier
                    )
                else {
                    // Do not create a duplicate when a known exported event can
                    // no longer be resolved.
                    throw PlatformIntegrationError.ownedEventUnavailable
                }
                event = existing
            } else {
                event = EKEvent(eventStore: eventStore)
                let calendar = requestedDestination
                    ?? eventStore.defaultCalendarForNewEvents
                    ?? calendars.first
                guard let calendar, calendar.allowsContentModifications else {
                    throw PlatformIntegrationError.missingCalendar
                }
                event.calendar = calendar
                needsSave = true
            }
            if
                let destination = requestedDestination,
                event.calendar.calendarIdentifier
                    != destination.calendarIdentifier
            {
                event.calendar = destination
                needsSave = true
            }
            let markerURL = URL(
                string:
                    "mission-control://fixed/\(write.localFixedCommitmentID.rawValue.uuidString)"
            )
            if event.title != write.title {
                event.title = write.title
                needsSave = true
            }
            if event.startDate != write.start {
                event.startDate = write.start
                needsSave = true
            }
            if event.endDate != write.end {
                event.endDate = write.end
                needsSave = true
            }
            if event.location != write.location {
                event.location = write.location
                needsSave = true
            }
            if event.url != markerURL {
                event.url = markerURL
                needsSave = true
            }
            if needsSave {
                try eventStore.save(event, span: .thisEvent, commit: true)
            }
            guard let externalIdentifier = event.eventIdentifier else {
                throw PlatformIntegrationError.missingCalendar
            }
            results.append(
                CalendarEventWriteResult(
                    localFixedCommitmentID: write.localFixedCommitmentID,
                    sourceIdentifier: event.calendar.calendarIdentifier,
                    externalIdentifier: externalIdentifier,
                    lastModifiedAt: event.lastModifiedDate
                )
            )
        }
        return results
    }

    func deleteAppOwnedEvent(
        externalIdentifier: String
    ) async throws {
        guard let event = eventStore.event(withIdentifier: externalIdentifier)
        else {
            throw PlatformIntegrationError.ownedEventUnavailable
        }
        guard event.url?.scheme == "mission-control" else {
            throw PlatformIntegrationError.ownedEventUnavailable
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }

    private func category(for title: String) -> MissionCategory {
        let lowercased = title.lowercased()
        if isFootballMatch(title) {
            return .football
        }
        if lowercased.contains("work")
            || lowercased.contains("shift") {
            return .work
        }
        if lowercased.contains("gym")
            || lowercased.contains("workout") {
            return .gym
        }
        return .personal
    }

    private func isFootballMatch(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        return lowercased.contains("football")
            || lowercased.contains("fixture")
            || lowercased.contains("match")
    }

    private func importIdentifier(for event: EKEvent) -> String {
        let base = event.calendarItemExternalIdentifier
            ?? event.eventIdentifier
            ?? event.calendarItemIdentifier
        guard let occurrence = event.occurrenceDate else {
            return base
        }
        return "\(base)|\(occurrence.timeIntervalSinceReferenceDate)"
    }

    private func ownedEvent(
        for write: CalendarEventWrite,
        preferredIdentifier: String
    ) -> EKEvent? {
        let expectedURL = URL(
            string:
                "mission-control://fixed/\(write.localFixedCommitmentID.rawValue.uuidString)"
        )
        if
            let event = eventStore.event(
                withIdentifier: preferredIdentifier
            ),
            event.url == expectedURL
        {
            return event
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess
        else {
            return nil
        }
        let padding: TimeInterval = 31 * 86_400
        let predicate = eventStore.predicateForEvents(
            withStart: write.start.addingTimeInterval(-padding),
            end: write.end.addingTimeInterval(padding),
            calendars: nil
        )
        return eventStore.events(matching: predicate).first {
            $0.url == expectedURL
        }
    }
}

final class HealthKitSleepService: HealthContextProviding {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func availabilityState() async -> PlatformAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }
        guard let type = HKObjectType.categoryType(
            forIdentifier: .sleepAnalysis
        ) else {
            return .unavailable
        }
        let status: HKAuthorizationRequestStatus = await withCheckedContinuation {
            continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: [],
                read: [type]
            ) { status, _ in
                continuation.resume(returning: status)
            }
        }
        switch status {
        case .shouldRequest:
            return .notDetermined
        case .unnecessary:
            // HealthKit deliberately does not disclose whether read access was
            // denied. A successful request is represented as requested and an
            // empty query remains a valid fallback.
            return .requested
        case .unknown:
            return .requested
        @unknown default:
            return .unavailable
        }
    }

    func requestSleepReadAccess() async -> PlatformAuthorizationState {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let type = HKObjectType.categoryType(
                forIdentifier: .sleepAnalysis
            )
        else {
            return .unavailable
        }
        let requestSucceeded: Bool = await withCheckedContinuation {
            continuation in
            healthStore.requestAuthorization(
                toShare: [],
                read: [type]
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
        return requestSucceeded ? .requested : .denied
    }

    func sleepRecoverySample(
        endingAt date: Date
    ) async throws -> SleepRecoverySample? {
        guard let type = HKObjectType.categoryType(
            forIdentifier: .sleepAnalysis
        ) else {
            return nil
        }
        let start = date.addingTimeInterval(-36 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: date,
            options: [.strictStartDate, .strictEndDate]
        )
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation {
            continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(
                        key: HKSampleSortIdentifierStartDate,
                        ascending: true
                    )
                ]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: samples as? [HKCategorySample] ?? []
                    )
                }
            }
            healthStore.execute(query)
        }
        let asleep = samples.filter { sample in
            guard let value = HKCategoryValueSleepAnalysis(
                rawValue: sample.value
            ) else {
                return false
            }
            switch value {
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                return true
            case .inBed, .awake:
                return false
            @unknown default:
                return false
            }
        }.map {
            DateInterval(start: $0.startDate, end: $0.endDate)
        }
        let episodes = sleepEpisodes(asleep)
        guard let episode = episodes.max(by: {
            if $0.asleepDuration == $1.asleepDuration {
                return $0.end < $1.end
            }
            return $0.asleepDuration < $1.asleepDuration
        }) else {
            return nil
        }
        return SleepRecoverySample(
            sleepWindowStart: episode.start,
            sleepWindowEnd: episode.end,
            asleepMinutes: max(Int(episode.asleepDuration / 60), 0)
        )
    }

    private struct SleepEpisode {
        var start: Date
        var end: Date
        var asleepDuration: TimeInterval
    }

    private func sleepEpisodes(
        _ intervals: [DateInterval]
    ) -> [SleepEpisode] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var episodes: [SleepEpisode] = []
        for interval in sorted {
            guard var last = episodes.last else {
                episodes.append(
                    SleepEpisode(
                        start: interval.start,
                        end: interval.end,
                        asleepDuration: interval.duration
                    )
                )
                continue
            }
            if interval.start <= last.end.addingTimeInterval(90 * 60) {
                let uncoveredStart = max(interval.start, last.end)
                if interval.end > uncoveredStart {
                    last.asleepDuration += interval.end.timeIntervalSince(
                        uncoveredStart
                    )
                }
                last.end = max(last.end, interval.end)
                episodes[episodes.count - 1] = last
            } else {
                episodes.append(
                    SleepEpisode(
                        start: interval.start,
                        end: interval.end,
                        asleepDuration: interval.duration
                    )
                )
            }
        }
        return episodes
    }
}

final class URLSessionICalSubscriptionService:
    ICalSubscriptionProviding
{
    private let session: URLSession
    private let parser: ICalendarParser

    init(
        session: URLSession = .shared,
        parser: ICalendarParser = ICalendarParser()
    ) {
        self.session = session
        self.parser = parser
    }

    func events(
        for subscription: ICalSubscription,
        in interval: DateInterval,
        fetchedAt: Date,
        timeZoneIdentifier: String
    ) async throws -> ExternalEventBatch {
        guard let url = normalizedURL(subscription.urlString) else {
            throw PlatformIntegrationError.invalidSubscriptionURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200 ... 299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard data.count <= 2_000_000 else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw PlatformIntegrationError.invalidICalendar
        }
        return try parser.parse(
            text,
            subscription: subscription,
            interval: interval,
            fetchedAt: fetchedAt,
            defaultTimeZone:
                TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if trimmed.lowercased().hasPrefix("webcal://") {
            normalized = "https://"
                + String(trimmed.dropFirst("webcal://".count))
        } else {
            normalized = trimmed
        }
        guard
            let url = URL(string: normalized),
            url.scheme?.lowercased() == "https",
            url.host != nil
        else {
            return nil
        }
        return url
    }
}

final class KeychainSecretStore: SecretStoring {
    private let service: String

    init(
        service: String =
            "com.ethanshahzad.PersonalMissionControl.credentials"
    ) {
        self.service = service
    }

    func containsSecret(for key: String) -> Bool {
        (try? secret(for: key)) != nil
    }

    func secret(for key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainSecretStoreError.operationFailed(status)
        }
        return value
    }

    func setSecret(_ secret: String, for key: String) throws {
        let trimmed = secret.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else {
            try removeSecret(for: key)
            return
        }
        guard trimmed.count <= 4_096,
              trimmed.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw KeychainSecretStoreError.invalidSecret
        }
        let query = baseQuery(for: key)
        let update = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as [String: Any]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            update as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSecretStoreError.operationFailed(updateStatus)
        }
        var insertion = query
        update.forEach { insertion[$0.key] = $0.value }
        let insertStatus = SecItemAdd(
            insertion as CFDictionary,
            nil
        )
        guard insertStatus == errSecSuccess else {
            throw KeychainSecretStoreError.operationFailed(insertStatus)
        }
    }

    func removeSecret(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.operationFailed(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

enum KeychainSecretStoreError: Error {
    case invalidSecret
    case operationFailed(OSStatus)
}

struct CustomJSONAIProvider: AICommandProvider, @unchecked Sendable {
    static let credentialKey = "ai-provider-bearer-token"

    private struct RequestEnvelope: Encodable {
        var model: String
        var responseSchema: String
        var request: AIProviderRequest
    }

    private let endpoint: URL
    private let modelIdentifier: String
    private let secretStore: any SecretStoring
    private let session: URLSession

    init?(
        settings: AIIntegrationSettings,
        secretStore: any SecretStoring,
        session: URLSession? = nil
    ) {
        guard
            settings.isConfigured,
            let endpoint = URL(string: settings.endpointURLString),
            endpoint.scheme?.lowercased() == "https",
            endpoint.host != nil
        else {
            return nil
        }
        self.endpoint = endpoint
        modelIdentifier = settings.modelIdentifier
        self.secretStore = secretStore
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            self.session = URLSession(
                configuration: configuration,
                delegate: NoRedirectSessionDelegate(),
                delegateQueue: nil
            )
        }
    }

    func requestCommand(
        _ request: AIProviderRequest
    ) async throws -> AIProviderResponse {
        guard let credential = try secretStore.secret(
            for: Self.credentialKey
        ), !credential.isEmpty else {
            throw AICommandPipelineError.providerUnavailable
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(
            "Bearer \(credential)",
            forHTTPHeaderField: "Authorization"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        urlRequest.httpBody = try encoder.encode(
            RequestEnvelope(
                model: modelIdentifier,
                responseSchema: "mission-control.command.v1",
                request: request
            )
        )
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              http.url?.scheme?.lowercased() == "https",
              http.url?.host?.lowercased()
                == endpoint.host?.lowercased() else {
            throw AICommandPipelineError.providerUnavailable
        }
        return try AIProviderResponseDecoder.decode(data)
    }
}

private final class NoRedirectSessionDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler:
            @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct VisionWorkShiftImageTextRecognizer:
    WorkShiftImageTextRecognizing,
    @unchecked Sendable
{
    func recognizeText(in imageData: Data) async throws
        -> WorkShiftImageRecognition {
        guard
            let source = CGImageSourceCreateWithData(
                imageData as CFData,
                nil
            ),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw WorkShiftImageRecognitionError.unreadableImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any]
        let orientationRaw =
            (properties?[kCGImagePropertyOrientation] as? NSNumber)?
                .uint32Value ?? 1
        let orientation =
            CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up
        return try await withCheckedThrowingContinuation {
            (
                continuation:
                    CheckedContinuation<
                        WorkShiftImageRecognition,
                        Error
                    >
            ) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations =
                    (request.results as? [VNRecognizedTextObservation]) ?? []
                let ordered = observations.sorted {
                    if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 {
                        return $0.boundingBox.midY > $1.boundingBox.midY
                    }
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                let lines = ordered.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first
                    else {
                        return nil
                    }
                    return RecognizedTextLine(
                        text: candidate.string,
                        confidence: Double(candidate.confidence)
                    )
                }
                guard !lines.isEmpty else {
                    continuation.resume(
                        throwing:
                            WorkShiftImageRecognitionError.noTextFound
                    )
                    return
                }
                continuation.resume(
                    returning: WorkShiftImageRecognition(lines: lines)
                )
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-GB", "en-US", "de-DE"]
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(
                        cgImage: image,
                        orientation: orientation,
                        options: [:]
                    ).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
