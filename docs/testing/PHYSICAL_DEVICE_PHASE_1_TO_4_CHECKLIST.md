# Physical iPhone Phase 1–4 Checklist

Status: **NOT RUN**

This checklist is the remaining human/device gate for the stabilized Phase 1–4
application. Simulator and unit-test results must not be copied into the
result column. Run it on at least one supported iPhone using a clean install
and an upgrade install when a real earlier build is available.

## Test record

| Field | Value |
|---|---|
| Tester | |
| Date and local timezone | |
| Device model | |
| iOS version | |
| App branch and commit | |
| Install type (clean/upgrade) | |
| Previous app/schema version, if upgraded | |
| Notification authorization at start | |
| Microphone/Speech authorization at start | |
| Overall result (Pass/Fail/Blocked) | |

For every item, record `Pass`, `Fail`, or `Blocked` plus a short observation
and a screenshot/screen recording or device log when useful.

## Launch, storage, and recovery

| ID | Check | Result | Evidence/notes |
|---|---|---|---|
| D-01 | Clean install launches without a crash and shows an understandable populated or empty Home state. | Not run | |
| D-02 | Force-close and relaunch preserve missions, plan, checklists, starts, completions, skips, partials, recovery choices, and routine state. | Not run | |
| D-03 | Restart the iPhone and confirm the same authoritative state remains. | Not run | |
| D-04 | Upgrade from an available Phase 1–4 build; confirm migration preserves meaning and the second launch is unchanged. | Not run | |
| D-05 | If a safely prepared corrupt test store is available, confirm the app shows recovery/session-only behavior and does not overwrite it. Preserve a copy before testing. | Not run | |
| D-06 | Force-quit during a representative edit, then relaunch; confirm no false durable-success state or partial destructive write. | Not run | |
| D-07 | Confirm development/test fixtures never appear in a production-installed data container unexpectedly. | Not run | |

## Notifications

| ID | Check | Result | Evidence/notes |
|---|---|---|---|
| N-01 | Deny notification permission; the app remains usable and reports the state honestly. | Not run | |
| N-02 | Later enable notifications in Settings, return to the app, and refresh; reminders become available without reinstalling. | Not run | |
| N-03 | Receive the 15-minute pre-start notification at the correct local time. | Not run | |
| N-04 | Receive the start-time, 15-minute-late, and 30-minute-late stages without duplicates. | Not run | |
| N-05 | Exercise Already Started, Start Now, Replan, and Skip actions from delivered notifications, including a cold launch. | Not run | |
| N-06 | Complete or skip a mission; obsolete delivered/pending notifications are removed. | Not run | |
| N-07 | Replan or move a mission rapidly several times; only the final schedule has pending notifications. | Not run | |
| N-08 | Relaunch after notifications were scheduled; pending requests still correspond to persisted block identities. | Not run | |

## Microphone, Speech, and command review

| ID | Check | Result | Evidence/notes |
|---|---|---|---|
| V-01 | Deny microphone/Speech permission; recording does not begin, the failure is visible, and typed fallback remains available. | Not run | |
| V-02 | Later approve permissions in Settings and successfully start/stop recording. | Not run | |
| V-03 | Press, hold, release, and cancel behave consistently; the central microphone remains reachable on all tabs. | Not run | |
| V-04 | Interrupt recording with a phone/audio interruption; capture stops safely and offers retry. | Not run | |
| V-05 | Review and edit the transcript before submission; raw and confirmed text remain distinct. | Not run | |
| V-06 | Reject/cancel a transcript; no authoritative state, history, notification, or plan changes. | Not run | |
| V-07 | Confirm low-risk checklist/inventory commands and compare the result with the equivalent interface path. | Not run | |
| V-08 | Confirm Start/Already Started/Replan/Skip and compare history, plan, confirmation, and recovery results with interface actions. | Not run | |
| V-09 | Submit malformed, empty, ambiguous, and past-date commands; failures are visible and do not mutate state. | Not run | |

## Home, interaction, and accessibility

| ID | Check | Result | Evidence/notes |
|---|---|---|---|
| U-01 | Top-right menu opens from the right and every Phase 1–4 destination remains dismissible. | Not run | |
| U-02 | Current-time circle, progress ring, dominant current mission, mini-checklist, Next, and later cards render correctly. | Not run | |
| U-03 | Preparation/travel blocks are visible but quieter; category accents remain consistent. | Not run | |
| U-04 | Scroll through a full day to the final mission without clipped or unreachable controls. | Not run | |
| U-05 | Start, completion, partial, skip, recovery, and replan actions refresh Home immediately. | Not run | |
| U-06 | Empty, loading, permission-denied, persistence-error, and session-only states use clear language and do not imply success. | Not run | |
| U-07 | Test all supported Dynamic Type sizes, including accessibility sizes, in portrait and landscape where supported. | Not run | |
| U-08 | With VoiceOver, verify meaningful labels, logical reading order, button traits, adjustable controls, and no focus traps. | Not run | |
| U-09 | Background and foreground the app during idle, recording, command review, and an execution prompt; state remains coherent. | Not run | |
| U-10 | Check Reduce Motion, Increase Contrast, Bold Text, and light/dark appearance for usable content. | Not run | |

## Real clock, timezone, network, and stability

| ID | Check | Result | Evidence/notes |
|---|---|---|---|
| T-01 | Cross midnight with a task in progress; history and the next day remain correctly separated. | Not run | |
| T-02 | Change timezone, foreground/relaunch, and confirm dates, current mission, fixed commitments, and notifications are not duplicated or lost. | Not run | |
| T-03 | Exercise a daylight-saving transition if the test date/zone permits; confirm valid durations and notification times. | Not run | |
| T-04 | Disable network access; all Phase 1–4 local scheduling, execution, persistence, and typed-command paths remain usable. | Not run | |
| T-05 | Repeat planning, voice review, and execution actions for 15–30 minutes; note hangs, crashes, heat, battery drain, or obvious memory growth. | Not run | |
| T-06 | Verify no duplicate task, history, recovery, or notification growth after repeated taps/deliveries. | Not run | |

## Sign-off

- [ ] Every row has a result and observation.
- [ ] Failures have a reproducible sequence and attached evidence.
- [ ] Upgrade evidence names the actual prior build/schema.
- [ ] Notification timing was observed on-device, not inferred.
- [ ] Voice results used real microphone/Speech services.
- [ ] Accessibility results were checked with device settings enabled.
- [ ] The final result and any release blocker were copied into the operational
      audit.

Tester signature: ____________________  Date: ____________________
