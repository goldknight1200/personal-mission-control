import Foundation

public struct ICalendarParser {
    public init() {}

    public func parse(
        _ text: String,
        subscription: ICalSubscription,
        interval: DateInterval,
        fetchedAt: Date,
        defaultTimeZone: TimeZone = .current
    ) throws -> ExternalEventBatch {
        let lines = unfoldedLines(in: text)
        guard lines.contains(where: {
            $0.uppercased() == "BEGIN:VCALENDAR"
        }), lines.contains(where: {
            $0.uppercased() == "END:VCALENDAR"
        }) else {
            throw PlatformIntegrationError.invalidICalendar
        }
        let eventStarts = lines.filter {
            $0.uppercased() == "BEGIN:VEVENT"
        }.count
        let eventEnds = lines.filter {
            $0.uppercased() == "END:VEVENT"
        }.count
        guard eventStarts == eventEnds else {
            throw PlatformIntegrationError.invalidICalendar
        }

        var components: [[String]] = []
        var current: [String]?
        var malformedEventNesting = false
        for line in lines {
            switch line.uppercased() {
            case "BEGIN:VEVENT":
                if current != nil {
                    malformedEventNesting = true
                }
                current = []
            case "END:VEVENT":
                if let current {
                    components.append(current)
                } else {
                    malformedEventNesting = true
                }
                current = nil
            default:
                current?.append(line)
            }
        }
        guard
            !malformedEventNesting,
            current == nil,
            components.count == eventStarts
        else {
            throw PlatformIntegrationError.invalidICalendar
        }

        let sourceID = subscription.id.rawValue.uuidString
        var events: [ExternalCalendarEvent] = []
        for component in components {
            guard let parsed = event(
                from: component,
                sourceID: sourceID,
                isFootball: subscription.isFootballFixtures,
                defaultTimeZone: defaultTimeZone
            ) else {
                throw PlatformIntegrationError.invalidICalendar
            }
            if parsed.isCancelled
                || (
                    parsed.end > interval.start
                        && parsed.start < interval.end
                ) {
                events.append(parsed)
            }
        }

        return ExternalEventBatch(
            sourceKind: .iCal,
            sourceIdentifier: sourceID,
            coveredInterval: interval,
            events: events,
            fetchedAt: fetchedAt
        )
    }

    private func event(
        from lines: [String],
        sourceID: String,
        isFootball: Bool,
        defaultTimeZone: TimeZone
    ) -> ExternalCalendarEvent? {
        let properties = lines.compactMap(parseProperty)
        guard
            let uid = value(named: "UID", in: properties),
            !uid.isEmpty,
            let startProperty = properties.first(where: {
                $0.name == "DTSTART"
            }),
            let startValue = parseDate(
                startProperty,
                defaultTimeZone: defaultTimeZone
            )
        else {
            return nil
        }
        let endProperty = properties.first(where: { $0.name == "DTEND" })
        let parsedEnd = endProperty.flatMap {
            parseDate($0, defaultTimeZone: defaultTimeZone)?.date
        }
        let defaultDuration: TimeInterval =
            startValue.isAllDay ? 86_400 : 3_600
        let end = parsedEnd ?? startValue.date.addingTimeInterval(
            defaultDuration
        )
        guard end > startValue.date else { return nil }

        let recurrenceID = properties.first(where: {
            $0.name == "RECURRENCE-ID"
        }).map(\.value)
        let externalID = recurrenceID.map { "\(uid)|\($0)" } ?? uid
        let status = value(named: "STATUS", in: properties)?.uppercased()
        let modified = properties.first(where: {
            $0.name == "LAST-MODIFIED"
        }).flatMap {
            parseDate($0, defaultTimeZone: defaultTimeZone)?.date
        }
        let summary = unescape(
            value(named: "SUMMARY", in: properties) ?? "External event"
        )
        return ExternalCalendarEvent(
            sourceKind: .iCal,
            sourceIdentifier: sourceID,
            externalIdentifier: externalID,
            title: summary,
            category: isFootball ? .football : .personal,
            start: startValue.date,
            end: end,
            location: value(named: "LOCATION", in: properties).map(unescape),
            isAllDay: startValue.isAllDay,
            isFootballMatch: isFootball,
            isAppOwned: false,
            isCancelled: status == "CANCELLED",
            lastModifiedAt: modified
        )
    }

    private struct Property {
        var name: String
        var parameters: [String: String]
        var value: String
    }

    private struct ParsedDate {
        var date: Date
        var isAllDay: Bool
    }

    private func parseProperty(_ line: String) -> Property? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])
        let headParts = head.split(separator: ";", omittingEmptySubsequences: true)
        guard let name = headParts.first else { return nil }
        var parameters: [String: String] = [:]
        for component in headParts.dropFirst() {
            let pair = component.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            if pair.count == 2 {
                parameters[String(pair[0]).uppercased()] =
                    String(pair[1]).trimmingCharacters(in:
                        CharacterSet(charactersIn: "\"")
                    )
            }
        }
        return Property(
            name: String(name).uppercased(),
            parameters: parameters,
            value: value
        )
    }

    private func value(
        named name: String,
        in properties: [Property]
    ) -> String? {
        properties.first(where: { $0.name == name })?.value
    }

    private func parseDate(
        _ property: Property,
        defaultTimeZone: TimeZone
    ) -> ParsedDate? {
        let isAllDay = property.parameters["VALUE"]?.uppercased() == "DATE"
            || property.value.count == 8
        let timeZone: TimeZone
        if property.value.hasSuffix("Z") {
            timeZone = TimeZone(secondsFromGMT: 0) ?? defaultTimeZone
        } else if
            let identifier = property.parameters["TZID"],
            let specified = TimeZone(identifier: identifier)
        {
            timeZone = specified
        } else {
            timeZone = defaultTimeZone
        }

        let formats: [String]
        if isAllDay {
            formats = ["yyyyMMdd"]
        } else if property.value.hasSuffix("Z") {
            formats = ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd'T'HHmm'Z'"]
        } else {
            formats = ["yyyyMMdd'T'HHmmss", "yyyyMMdd'T'HHmm"]
        }
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: property.value) {
                return ParsedDate(date: date, isAllDay: isAllDay)
            }
        }
        return nil
    }

    private func unfoldedLines(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init) {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")),
               !lines.isEmpty {
                lines[lines.count - 1] += String(raw.dropFirst())
            } else {
                lines.append(raw)
            }
        }
        return lines
    }

    private func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
