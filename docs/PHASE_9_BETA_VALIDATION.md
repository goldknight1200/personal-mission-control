# Phase 9 beta and release validation

Phase 9 is complete in source, not validated as production-ready. The local
deterministic app remains the only scheduling authority and works with AI and
OCR disabled.

Phase 9 adds no entitlement. PhotosPicker/fileImporter provide explicit
per-item selection without broad Photo Library authorization or an
`NSPhotoLibraryUsageDescription`; Vision runs on device; ordinary Keychain
storage uses no access-group entitlement; the AI adapter permits HTTPS only and
adds no App Transport Security exception. Phase 8 HealthKit remains the only
checked-in entitlement.

## Implemented and unit-tested in source

- `AICommandInterpreter` is implemented by a provider-backed interpreter over
  an `AICommandProvider` protocol. It minimizes context, accepts only
  `mission-control.command.v1`, validates every field locally, converts output
  to existing typed mutations, requires confirmation for every AI proposal,
  and falls back to `LocalCommandParser` for commands that parser supports.
- The shipping provider adapter is user-configured HTTPS JSON. Its bearer
  credential is stored in Keychain under a device-only accessibility class.
  No endpoint, model, or secret is hard-coded. The exact minimized request is
  inspectable before Send and for the current app session. Embedded URL
  credentials/query strings are rejected, redirects are not followed, and the
  ephemeral URL session has no response cache.
- Vision OCR accepts an explicitly selected photo/file, does not retain the
  image, excludes low-confidence lines, discloses ambiguity, reuses the
  reviewed shift parser, highlights existing-shift changes/conflicts, and
  applies only selected confirmed entries.
- Snapshot schema 10 adds non-secret AI/privacy settings with schema-9
  defaults. Persistence validates schema, time zone, intervals, and key
  collection identifiers before save/load.
- Backup export includes one versioned JSON envelope. Restore validates format,
  size, schema, intervals, time zone, and duplicate identifiers before replacing
  the local snapshot. Keychain credentials, raw Health samples, and audio are
  excluded.
- Local-data deletion removes the durable snapshot and AI credential and
  creates an empty local profile after destructive confirmation. It does not
  claim to delete provider-owned data or already-exported Apple Calendar items.
- Significant time/time-zone changes replan and reschedule notifications.
  Notification reconciliation is serialized and reruns from the newest state
  after overlapping edits.
- Static source inspection found no `print`, `debugPrint`, `NSLog`, or Logger
  call that records transcripts, calendar titles, health details, schedule
  content, OCR text, or credentials.
- Core tests cover context minimization, mandatory AI confirmation, invalid
  provider fallback, unknown mission rejection, strict response fields, OCR
  ambiguity/change detection, backup round trip, schema-9 defaults, integrity
  rejection, notification replacement, DST exactness, large-history counting,
  and the synthetic-week scenario.

## Static accessibility and appearance audit

- The Home clock/orb and central microphone now use scaled metrics; the Home
  stack can grow rather than forcing the clock into the former fixed-height
  band.
- The menu, Home progress ring, and microphone press/record animations honor
  Reduce Motion.
- Buttons with symbol-only chrome retain explicit labels or ordinary labeled
  button content. Shift selection exposes a checkmark plus text, and every AI,
  OCR, backup, restore, and deletion action has a textual label.
- Category accents use adaptive SwiftUI system colors over semantic
  materials/backgrounds. Category/title/icon text remains present, so color is
  never the only scheduling cue.
- Static inspection cannot establish contrast ratios after system tint,
  increased-contrast settings, display accommodations, translations, or all
  accessibility Dynamic Type sizes. Those remain simulator/device gates below.

## Provider contract and user configuration

The custom endpoint receives an HTTPS `POST` with a bearer credential:

```json
{
  "model": "user-configured-model",
  "responseSchema": "mission-control.command.v1",
  "request": {
    "schemaVersion": 1,
    "confirmedText": "user-confirmed text",
    "referenceDate": "ISO-8601 instant",
    "timeZoneIdentifier": "Europe/Berlin",
    "relevantMissions": [],
    "relevantWorkShifts": [],
    "allowedMutationKinds": []
  }
}
```

The response must contain exactly the documented top-level structured fields
and only supported mutation fields. Unknown enum values or mutation kinds fail
decoding. The model cannot write storage, return a schedule, clear a safety
flag, modify an approved workout template, or mark its own output confirmed.

Example response:

```json
{
  "schemaVersion": 1,
  "detectedIntents": [
    {"kind": "addShoppingItem", "confidence": 0.94}
  ],
  "confidence": 0.94,
  "extractedEntities": [
    {
      "kind": "checklistItem",
      "value": "Bananas",
      "normalizedValue": "bananas"
    }
  ],
  "mutations": [
    {
      "kind": "addChecklistItem",
      "checklistKind": "shopping",
      "title": "Bananas"
    }
  ],
  "affectedScheduleRange": {},
  "warnings": []
}
```

Dates are ISO-8601 instants. Mission identifiers are the lower-case UUID
strings supplied in `relevantMissions`; locally invented or stale identifiers
are rejected. Supported mutation kinds and their optional fields are encoded
in the core `AIProviderMutation` contract and bounded again by the local
validator.

The user still has to provide:

- an HTTPS endpoint implementing that contract;
- its model identifier;
- a bearer credential saved through the in-app Keychain flow;
- explicit choices about sharing relevant mission titles and, separately,
  bounded work-shift times.

## Repeatable synthetic-week acceptance

The automated fixture
`PhaseNineBetaAcceptanceTests.testSyntheticWeekAndSuccessiveReplansRemainCoherent`
starts Monday 27 July 2026 in Europe/Berlin and contains:

- Monday/Wednesday/Friday work shifts, including a supermarket-tagged shift;
- Tuesday/Thursday football training and a Saturday externally managed match;
- the approved four-session upper/lower program;
- the seeded two-week priority project/deadline;
- seven-day planned meals, deficit coverage, inventory/shopping;
- groceries, meal prep, football laundry, tidying, trash, and bedsheets routines;
- a Tuesday late wake-up, a later missed project start, a shoulder pain flag, and
  a changed Wednesday shift.

At each stage it verifies exact fixed commitments, immutable external items,
non-overlapping blocks, approved workout session identity, food-deficit
coverage, applied replan requests, pain-restriction explanations, exact changed
shift times, and non-empty decision explanations.

## Requires macOS/Xcode and simulator

Run on the latest installed stable Xcode:

```sh
swift test --package-path Packages/MissionControlCore

xcodebuild \
  -project PersonalMissionControl.xcodeproj \
  -scheme PersonalMissionControl \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project PersonalMissionControl.xcodeproj \
  -scheme PersonalMissionControl \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Simulator inspection must cover:

1. all primary screens at every Dynamic Type size, including accessibility
   sizes, without hidden confirmation/destructive controls;
2. VoiceOver order, labels, values, and actions for Home, capture, shift review,
   AI settings, backup/restore, and deletion;
3. light/dark and increased-contrast appearances for every category accent;
   category meaning must remain available through text/icon, not color alone;
4. Reduce Motion behavior for the menu, Home progress ring, and microphone;
5. English text expansion and long provider/error strings. The app remains
   English-only in this source and localization is a known limitation;
6. offline/provider timeout, invalid JSON, 4xx/5xx, oversized response, missing
   credential, bad backup, unreadable image, and no-text OCR states;
7. rapid consecutive plan edits while inspecting the final pending local
   notifications.

## Requires signed real device

- Repeat all Phase 8 Calendar, Health, Siri, Speech, and notification checks in
  `PHASE_8_DEVICE_VALIDATION.md`.
- Select rota photos and files from iCloud Drive and local storage. Confirm the
  app does not request broad Photo Library access, does not upload the image,
  and manual text/voice entry remains usable after cancellation or failure.
- Exercise a configured provider over airplane-mode transitions and a live
  account. Inspect the payload, confirm no raw calendar/Health/audio content,
  reject a proposal, confirm one, and verify the deterministic decision trace.
- Travel between time zones with both fixed-profile and follow-system settings;
  cross the Europe/Berlin spring/fall DST boundaries and inspect exact external
  events, generated local blocks, and pending notifications.
- Export, terminate, reinstall/clear data, restore, and compare representative
  entities. Verify the Keychain/provider behavior expected for the chosen
  install/signing environment rather than assuming backup contains a secret.
- Profile cold load, Day/Week/Month inspection, history summary, planning,
  replanning, backup encoding, and notification reconciliation with at least
  10,000 completions, 5,000 workout sets, 1,000 commands, and 1,000 external
  items. Record device, OS, duration, peak memory, and any threshold decision.

## TestFlight and operational gates

Still required before any production-readiness statement:

- signing team, bundle identifier, provisioned HealthKit capability, and
  archive validation;
- privacy nutrition labels and purpose-text review matching actual provider and
  retention choices;
- TestFlight description, tester instructions, feedback address, privacy
  policy/support URLs, export-compliance answers, and provider-account setup;
- crash/diagnostic process that does not collect sensitive payloads by default;
- backup/restore recovery rehearsal and a deletion support policy;
- successful full synthetic-week runs by beta testers, including explanations
  judged coherent by a human.

## Final status matrix

| Category | Status |
| --- | --- |
| Implemented and unit-tested | Implemented in source; tests authored but not executed on this Windows host |
| Compiled/tested in Xcode or simulator | Not validated |
| Validated on a real device | Not validated |
| Requires user account/permission configuration | AI endpoint/model/credential; Calendar, Health, Speech, Notifications, Siri, photo/file selections as used |
| Known limitations | English-only UI; custom JSON endpoint rather than a bundled provider-specific account flow; no background OCR/feed refresh; no automatic cloud sync; external exported calendar items are not deleted by local reset; real-device performance thresholds remain unset |
