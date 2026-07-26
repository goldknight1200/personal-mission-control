# Phase 8 Apple integration validation

Phase 8 keeps every Apple integration optional. Core package tests use protocol
fakes, but the following behavior cannot be fully established by the Windows
workspace or pure-Swift tests.

## Capability and entitlement inventory

| Integration | Requested capability | Purpose/configuration | Deliberately absent |
| --- | --- | --- | --- |
| EventKit import and sync | iOS Calendar full access, requested only after the user selects Import and sync | `NSCalendarsFullAccessUsageDescription` | No Calendar entitlement is required on iOS |
| EventKit app-owned export | iOS Calendar write-only access when Add new app events only is selected; full access for later update/delete | `NSCalendarsWriteOnlyAccessUsageDescription` | Write-only mode never claims it can read or update previously created events; the app never modifies an event unless it carries the Mission Control ownership marker |
| HealthKit sleep | `com.apple.developer.healthkit` plus read access to `HKCategoryTypeIdentifierSleepAnalysis` | `NSHealthShareUsageDescription` | No HealthKit write type and no `NSHealthUpdateUsageDescription` because the app writes no health data |
| App Intents / App Shortcuts | App Intents registered by the app target | Phrase definitions include the application name and required item parameters | No SiriKit entitlement; no custom SiriKit intent extension |
| iCal subscriptions | Outbound HTTPS fetch after the user adds/enables a feed | `webcal://` is normalized to HTTPS; standard App Transport Security remains enabled | No account, provider token, background-fetch entitlement, or arbitrary HTTP exception |

Automatic signing must provision the HealthKit capability for
`com.ethanshahzad.PersonalMissionControl`. If the development team cannot
provision that capability, the app must still build/run after HealthKit is
disabled for that signing configuration, and the local planner remains usable.

## Signed real-device checks

1. Install on an iPhone running iOS 17 or later with a development profile that
   includes HealthKit.
2. Verify the app launch does not show Calendar or Health permission prompts.
3. In Calendar integrations, select **Add new app events only**. Verify the
   write-only prompt uses the configured purpose text. Deny it, relaunch, and
   confirm planning, editing, and replanning still work.
4. Change to **Import and sync**. Verify the full-access prompt or Settings
   transition. Import events from two calendars, including all-day and timed
   events, and confirm exact times and immutable behavior in Day/Week/Month.
5. Edit, move, and delete an imported event in Apple Calendar. Return to the
   app and verify `EKEventStoreChanged` causes a bounded refetch, updates the
   existing local commitment rather than duplicating it, and removes only the
   deleted external item.
6. In **Import and sync**, enable app-owned export. Create and edit a local fixed commitment, sync
   twice, and verify one marked Apple Calendar event is updated. Delete or make
   the destination calendar unavailable and confirm the app reports the
   failure without creating a replacement duplicate.
7. In Health integration, enable sleep. Verify the Health prompt requests only
   Sleep Analysis read access. Test allow, deny, and limited-date access. An
   empty query must show no data and must not be labelled as proof of denial.
8. With recent sleep samples available, refresh in the morning and verify only
   a derived duration/window appears. Confirm it is described as planning
   context, not a medical or readiness conclusion. Disable the integration and
   verify the Health-derived context is removed without affecting the app.
9. In Shortcuts, locate all six App Shortcuts. Run each in the foreground and
   background. Test Siri phrases in the device language, including a supplied
   task/shopping parameter. Confirm Open capture presents the reviewed capture
   flow and does not start microphone recording automatically.
10. Add a representative HTTPS or webcal football fixture feed. Verify UID
    updates, a `STATUS:CANCELLED` fixture, and a removed fixture. Then test
    airplane mode or a server error and confirm prior local fixtures remain
    intact.

## Simulator and automated coverage

- Pure-core tests cover denied Calendar access, idempotent external update,
  bounded deletion, app-owned identity persistence, optional Health data,
  derived recovery context, iCalendar parsing, cancellation, and schema-8
  migration defaults.
- An iOS Simulator can exercise settings layout, most EventKit behavior, iCal
  networking, and Shortcuts discovery, but it is not the release gate for
  Health data availability, provisioned entitlements, Siri voice invocation, or
  real permission history.
- `xcodebuild` on macOS remains required to compile the Apple framework adapters
  and generated entitlement/Info.plist configuration.
