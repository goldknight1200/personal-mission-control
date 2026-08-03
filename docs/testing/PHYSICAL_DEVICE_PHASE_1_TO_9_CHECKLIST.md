# Physical Device Phase 1–9 Checklist

Use this checklist only after the core tests, iOS simulator tests, Debug build,
and Release build pass on the exact candidate commit. This is a Phase 1–9
verification artifact; it does not authorize Phase 10.

## Automated prerequisite handoff

This handoff records automated evidence only. It does not mark any physical
checkbox below as passed.

| Field | Value |
| --- | --- |
| Implementation revision | `68e00784c7cee37ff5509da1fcc02647701560e6` |
| Validation revision | `4efab53684c3965ba50252ba991908363e9bf9b5` (implementation unchanged; documentation handoff included) |
| Workflow run | [`30343457516`](https://github.com/goldknight1200/personal-mission-control/actions/runs/30343457516) |
| Confirmed automated gates | Static validation; 151/151 core tests; 22/22 application tests; unsigned Debug and Release builds; three-profile launch smoke; successful workflow conclusion |
| Authored skip-marker audit | 0 skip/disabled markers across 173 authored tests |
| Launch artifact | `launch-smoke-30343457516-1`; Home screenshots visually inspected on 2026-08-03 for launch coherence |
| Still requiring configuration/manual validation | Signed device, accounts and permissions, full accessibility/usability matrix, device performance, archive/TestFlight, and beta operations |
| Physical evidence | None recorded; every physical checklist item remains open |

Do not begin the physical run until all entry gates pass on the exact final
candidate commit. If the final candidate differs from the implementation
revision above, replace this handoff with evidence for that candidate.

## Test record

| Field | Value |
| --- | --- |
| Candidate commit | |
| Git status clean | ☐ Yes ☐ No |
| App version/build | |
| Xcode version | |
| macOS version/architecture | |
| Device model | |
| iOS version | |
| Signing team | |
| Bundle identifier | |
| HealthKit capability provisioned | ☐ Yes ☐ No ☐ Not tested |
| Locale/language | |
| Region | |
| Profile time zone | |
| System time zone | |
| Tester | |
| Date/time | |
| Evidence folder/link | |

For every item, mark one result and attach a screenshot, screen recording, log,
or written observation where useful:

```text
Result: ☐ Pass ☐ Fail ☐ Blocked ☐ N/A
Evidence:
Defect ID / notes:
```

## Entry gates

- [x] `swift test --package-path Packages/MissionControlCore` passed.
- [x] iOS simulator XCTest passed on the validation commit.
- [x] unsigned Debug simulator build passed.
- [x] unsigned Release simulator build passed.
- [x] app launched on small, common, and large supported iPhone simulators.
- [ ] candidate commit and build number are recorded above.
- [ ] the device is backed up and contains only test data/accounts suitable for
      the permission and deletion scenarios.
- [ ] HealthKit signing capability and all expected Info.plist purpose strings
      were inspected in the built app.
- [ ] a test calendar, representative iCalendar feed, optional test AI
      endpoint, rota images, backup destination, and Shortcuts/Siri access are
      available where applicable.

Stop and file a release blocker if the app crashes, corrupts or loses data,
duplicates externally managed events, bypasses confirmation, applies an AI/OCR
proposal directly, exposes a secret, or produces overlapping/invalid fixed
schedule blocks.

## Phase 1 — Local vertical slice

### Installation, launch, and local operation

- [ ] Fresh install launches without account creation or network access.
- [ ] Airplane-mode fresh launch reaches a usable local Home.
- [ ] First-run data is coherent and clearly sample/seed data where applicable.
- [ ] Relaunch restores the same durable state.
- [ ] Restart the iPhone, relaunch the app, and confirm durable state,
      permissions, and the current schedule remain coherent.
- [ ] Force-quit during ordinary navigation does not corrupt the snapshot.
- [ ] Settings allow editing personal defaults rather than presenting hidden
      constants as fixed truth.

### Navigation and Home

- [ ] Goals, Lists, Home, Plan, and settings destinations are reachable.
- [ ] The central microphone action is reachable and does not obscure tab
      controls.
- [ ] Home visibly distinguishes Now, Next, and Later.
- [ ] preparation/travel/transitions are visually subdued but readable.
- [ ] progress orb, current mission, mini-goals, and upcoming timeline agree
      with Plan for the same instant.
- [ ] Home scrolls when content exceeds the display.
- [ ] app background/foreground and device lock/unlock preserve the current
      mission state.

### Basic execution and persistence

- [ ] Complete a mission in one tap and verify Home/Plan/history update.
- [ ] Correct actual duration and verify the correction persists after relaunch.
- [ ] Complete, partially complete, skip, and reopen representative missions.
- [ ] Empty-store and reset states do not recreate duplicate seed records.
- [ ] Rapidly save several edits, force-quit, and confirm the last acknowledged
      durable state returns.

## Phase 2 — Deterministic scheduling and replanning

### Seven-day plan

- [ ] Generate a seven-day plan twice without changing inputs; block identity,
      ordering, explanations, and conflicts are stable.
- [ ] fixed/external commitments remain exact and immutable.
- [ ] sleep, meals, transitions, protected activities, projects, routines,
      chores, and free time appear in documented planning order.
- [ ] no two schedule blocks overlap.
- [ ] block start/end values remain within the displayed day/time-zone model.
- [ ] unscheduled work is explained rather than silently omitted.
- [ ] legitimate free time and recovery remain possible outcomes.

### Replanning

- [ ] Start a mission late and verify past blocks remain frozen.
- [ ] Verify an in-progress mission is preserved during replan.
- [ ] Change a future fixed commitment; unaffected future blocks move as little
      as practical.
- [ ] Add an impossible fixed conflict and verify an explicit conflict rather
      than an invalid overlapping plan.
- [ ] Confirm protected/user-approved items are not silently displaced.
- [ ] Verify placement, omission, movement, recovery, and confirmation
      explanations are understandable and match the resulting blocks.
- [ ] Change device clock/time zone and confirm the lifecycle replan is bounded
      and does not duplicate blocks.

## Phase 3 — Voice review and commands

### Authorization and recording

- [ ] No microphone/Speech prompt appears before the user invokes voice.
- [ ] Allow microphone and Speech access; press-and-hold starts recording and
      release stops it.
- [ ] Deny microphone, deny Speech, and later change each permission in
      Settings; the app explains the state and text entry remains usable.
- [ ] Test phone call/audio interruption, app backgrounding, device lock, and
      retry; no stale recording remains active.
- [ ] Verify audio is not retained after transcription under the default policy.

### Review-before-send

- [ ] A transcript is shown in editable review before interpretation/mutation.
- [ ] Edit changes the confirmed text.
- [ ] Retry produces a new capture without applying the old transcript.
- [ ] Cancel applies nothing.
- [ ] Leaving review and returning does not apply anything.
- [ ] Send produces a typed proposal/confirmation where required.
- [ ] Raw versus confirmed text and warning/confirmation state behave according
      to the retention setting.

### Representative commands

- [ ] Add a Today item.
- [ ] Add a shopping item.
- [ ] Record a work shift using `09:00 to 17:00`.
- [ ] Record a work shift using `09:00 - 17:00`.
- [ ] Record a batch of shifts and review each before saving.
- [ ] Mark a mission started earlier.
- [ ] Move a mission and inspect affected range/consequences.
- [ ] Skip a mission and inspect consequences.
- [ ] Attempt an ambiguous/unsupported command; nothing mutates silently.
- [ ] Change the plan after proposal creation, then try the stale proposal; it
      must be rejected/reviewed again, including when the changed block is a
      second occurrence of the same mission.

## Phase 4 — Notifications, recovery, history, and consistency

### Permission and reconciliation

- [ ] No notification prompt appears before the relevant user action/settings.
- [ ] Test allow, deny, and later Settings changes.
- [ ] Verify pre-start, start, 15-minute-late, and 30-minute-late notifications.
- [ ] Move, complete, skip, and delete a planned mission; obsolete pending
      notifications are cancelled and replacements are unique.
- [ ] Perform rapid consecutive plan edits; final pending notifications match
      only the final plan.
- [ ] Cross a device clock/time-zone change; pending notifications reconcile.
- [ ] Inspect notification previews while locked for unintended sensitive detail.

### Actions and lifecycle

- [ ] **Already Started** corrects actual start without creating duplicate
      completion/start records.
- [ ] **Start Now** preserves history and replans future work.
- [ ] **Replan** presents/evaluates alternatives without silently choosing a
      consequential action.
- [ ] **Skip** records the disposition and consequence.
- [ ] Run each action foregrounded, backgrounded, locked, and after app
      termination where iOS permits.
- [ ] Duplicate notification action delivery is idempotent.

### Reflection/history

- [ ] Morning “Anything changed?” updates a provisional plan.
- [ ] Evening remains passive when nothing is unresolved.
- [ ] Unresolved items receive explicit disposition choices.
- [ ] Weekly football, gym, project, nutrition, and sleep metrics compare
      planned/target versus actual without shaming language.
- [ ] Repeated misses surface cause reassessment instead of endless automatic
      rescheduling.

## Phase 5 — Goals, projects, lists, routines, shopping, and shifts

### Goals and projects

- [ ] Create, edit, deactivate/reactivate, and delete a goal.
- [ ] Create unlimited projects and associate/disassociate them with goals.
- [ ] Exercise active priority, maintained, and backlog project states.
- [ ] Add/change/remove a user-approved priority override.
- [ ] Verify maintained projects receive reasonable exposure without forced
      daily allocation.
- [ ] Repeatedly skip a project mission and verify priority reassessment.
- [ ] Verify delete confirmations and historical display after source deletion.

### Lists and routines

- [ ] Create/edit/complete/delete Today one-offs.
- [ ] Create/edit/complete/delete shopping items.
- [ ] Create/edit/enable/disable/delete routines.
- [ ] Verify household recurrence rules across at least two weeks.
- [ ] Verify due-window behavior before, inside, and after the window.
- [ ] Verify compatible errands/chores bundle without violating fixed events.
- [ ] Long lists remain responsive, searchable/readable, and scroll correctly.

### Work shifts

- [ ] Enter one shift manually and verify exact start/end/location.
- [ ] Enter a natural-language batch and review additions, changes, conflicts,
      and unparsed text.
- [ ] Cancel review and verify nothing saves.
- [ ] Confirm selected entries only; verify fixed immutable blocks and one
      persistence record per shift.
- [ ] Edit/delete a local shift and verify replan/notifications reconcile.

## Phase 6 — Nutrition and inventory

- [ ] Edit calorie, protein, substantial-meal, meal-time, deficit, eating-block,
      and shopping-lead targets.
- [ ] Planned intake displays approximate rather than falsely precise claims.
- [ ] Create/edit/delete meal templates and their inventory usage.
- [ ] Plan/unplan meals for several days.
- [ ] Create exact-quantity and qualitative inventory items.
- [ ] Move inventory through sufficient, low, and depleted states.
- [ ] A clear deficit produces an understandable warning, useful suggestion,
      and feasible eating block.
- [ ] Reject/edit/accept the eating suggestion; only the confirmed result
      changes the plan.
- [ ] A likely shortage proposes shopping before depletion.
- [ ] Shopping combines with a compatible trip/work location when feasible and
      stays separate when constraints conflict.
- [ ] Negative/non-finite values cannot be entered or restored.
- [ ] Relaunch preserves all nutrition/inventory edits and generated decisions.

## Phase 7 — Workout execution and recovery

### Program management and scheduling

- [ ] Create/edit/approve/disable a program.
- [ ] Exercise/session order, sets, rep ranges, rest, target/prior load, and
      selected exercises remain exact.
- [ ] Scheduler never invents an exercise/session outside the approved program.
- [ ] Weekly session target and preferred days behave across a full week.
- [ ] Two unresolved occurrences of the same workout can receive different
      dispositions without collapsing into one.
- [ ] Match proximity and post-match recovery restrict affected work.
- [ ] Low sleep context changes demanding work only according to editable
      deterministic thresholds.
- [ ] Body-area pain blocks affected exercises with an explanation.
- [ ] Clearance/reassessment is explicit, logged, and required before blocked
      exercises return.

### Execution

- [ ] Start the scheduled session and verify current exercise/set detail.
- [ ] Log actual weight/reps and complete/skip sets.
- [ ] Rest timer starts, updates, survives background/foreground, and alerts
      once at the correct time.
- [ ] Shorten a session only through the explicit supported flow.
- [ ] Complete and partially complete sessions; history and future planning use
      the correct result.
- [ ] Force-quit during an in-progress workout and recover without duplicate or
      lost set logs.

## Phase 8 — Apple integrations

### Calendar

- [ ] Fresh launch shows no Calendar prompt.
- [ ] Select app-owned write-only export and test allow/deny/settings change.
- [ ] Select import/sync and test full-access allow/deny/settings change.
- [ ] Import timed and all-day events from at least two calendars.
- [ ] Exact times, time zones, location, external identity, and immutable state
      are preserved.
- [ ] Edit/move/delete an imported event in Apple Calendar; bounded refresh
      updates/removes one local item without duplication.
- [ ] Create/edit a local fixed commitment with export enabled; the same marked
      app-owned event is updated, not recreated.
- [ ] Make destination calendar unavailable; failure is reported and no
      duplicate replacement appears.
- [ ] The app never edits/deletes an external event it does not own.

### Health

- [ ] Fresh launch shows no Health prompt.
- [ ] Enable sleep read; prompt requests only Sleep Analysis read access.
- [ ] Test allow, deny, limited-date, and empty-result states.
- [ ] Empty results are not described as proof of denial.
- [ ] Only derived duration/window enters planning; raw samples are not shown,
      backed up, logged, or sent to AI.
- [ ] Disable Health; derived context clears without harming local planning.
- [ ] Health-derived text remains non-medical and non-diagnostic.

### App Intents, Shortcuts, and Siri

- [ ] All six App Shortcuts are discoverable.
- [ ] Run each foregrounded and backgrounded.
- [ ] Test Siri phrases in the device language with supplied task/shopping
      parameters.
- [ ] Open capture presents review and does not auto-start the microphone.
- [ ] Consequential intent actions do not bypass confirmation/consequence rules.
- [ ] Denied/unavailable dependencies return useful failure dialogs.

### iCalendar

- [ ] Add a representative HTTPS feed and a `webcal://` equivalent.
- [ ] Initial import preserves UID, exact time, and externally managed state.
- [ ] Changed UID content updates the existing item.
- [ ] `STATUS:CANCELLED` removes the correct fixture.
- [ ] A feed-removed fixture reconciles without deleting unrelated events.
- [ ] Airplane mode, timeout, invalid data, and server errors preserve prior
      good local fixtures and expose a bounded failure.

## Phase 9 — Optional AI/OCR, hardening, privacy, and beta

### Optional AI

- [ ] Deterministic local planning works with AI disabled and no credential.
- [ ] Invalid HTTP, embedded credential, query credential, and non-HTTPS
      endpoint configurations are rejected.
- [ ] Save/change/delete a test credential and verify expected Keychain behavior.
- [ ] Inspect the exact outgoing payload before Send.
- [ ] Payload excludes raw calendar data, Health samples, audio, OCR image,
      unrelated titles, and secrets.
- [ ] Test title sharing off/on and work-shift sharing off/on.
- [ ] Reject an AI proposal; state remains byte-for-byte logically unchanged.
- [ ] Confirm an AI proposal; only typed reviewed mutations apply through the
      deterministic planner.
- [ ] Provider response with unknown fields, mission ID, mutation, schema,
      oversized body, redirect, malformed JSON, 4xx, 5xx, timeout, and offline
      state is rejected or safely falls back.
- [ ] Stale proposals are rejected after any relevant plan occurrence changes.
- [ ] AI never marks its own output confirmed or writes storage directly.

### OCR shift import

- [ ] Select a clear rota photo using PhotosPicker.
- [ ] Select a clear image/document from local storage and iCloud Drive.
- [ ] Cancel selection; manual text/voice entry remains available.
- [ ] Test blur, glare, rotation, handwriting, low contrast, ambiguous digits,
      no text, unsupported file, and unreadable file.
- [ ] Low-confidence text is excluded and ambiguity is disclosed.
- [ ] Existing shift changes/conflicts are highlighted.
- [ ] Apply selected entries only after explicit confirmation.
- [ ] Verify the selected image is not uploaded or retained by the app.

### Backup, restore, deletion, and migration

- [ ] Export a representative schema-10 backup.
- [ ] Inspect that it excludes Keychain credential, raw Health samples, audio,
      and OCR image bytes.
- [ ] Restore into a clean app and compare representative goals, projects,
      missions, plans, history, nutrition, workouts, integrations, and settings.
- [ ] Reject oversized, malformed, future-schema, invalid-time-zone,
      invalid-interval, duplicate-ID, nested-duplicate, and negative-value
      backups without replacing good local state.
- [ ] Install over a representative older build/payload and verify one
      idempotent migration to schema 10.
- [ ] Exercise destructive local-data deletion confirmation.
- [ ] Verify durable snapshot and AI credential deletion while avoiding claims
      about provider-owned or already-exported calendar data.
- [ ] Reinstall and record actual Keychain behavior for this signing environment.

### Time, time zone, offline, and failure handling

- [ ] Test Europe/Berlin spring DST transition.
- [ ] Test Europe/Berlin fall DST transition.
- [ ] Travel/simulate a time-zone change with fixed-profile behavior.
- [ ] Repeat with follow-system behavior.
- [ ] External event instants, local wall-clock intent, notifications, and
      regenerated blocks remain coherent.
- [ ] Exercise all primary screens in airplane mode.
- [ ] Rapid edits, force-quit, storage failure, corrupted restore, provider
      failure, and permission revocation fail without partial mutation.

### Accessibility and visual fidelity

- [ ] Test every primary and modal screen at all Dynamic Type sizes, including
      every accessibility size.
- [ ] Test VoiceOver order, label, value, hint/action, modal focus, error
      announcement, and destructive confirmation.
- [ ] Test light, dark, and increased-contrast appearances.
- [ ] Verify category meaning is never color-only.
- [ ] Test Reduce Motion for menu, progress orb, microphone, plan changes, and
      modal transitions.
- [ ] Test Button Shapes, Bold Text, Reduce Transparency, and Smart Invert where
      applicable.
- [ ] Test small, common, and large supported iPhones.
- [ ] Rotate through every orientation the app declares as supported; the
      navigation shell, primary controls, sheets, and forms remain usable.
- [ ] Test long provider/error strings and substantial English text expansion.
- [ ] Record the English-only limitation and confirm no clipped release-blocking
      content.

### Performance and stability

Record Instruments/build configuration, duration, peak memory, dataset size,
thermal state, and threshold decision for each measurement.

- [ ] Cold launch with representative data.
- [ ] Home first meaningful render.
- [ ] Day/Week/Month plan inspection and scrolling.
- [ ] Typical-week initial planning.
- [ ] 25 successive replans.
- [ ] 200-item backlog plan.
- [ ] At least 10,000 completions.
- [ ] At least 5,000 workout sets.
- [ ] At least 1,000 command records.
- [ ] At least 1,000 external calendar items.
- [ ] History summary calculation.
- [ ] Backup encoding and restore validation.
- [ ] Notification reconciliation after rapid plan changes.
- [ ] Thirty-minute mixed-use soak with background/foreground cycles.
- [ ] Record Energy Log, battery impact, and thermal-state observations during
      the mixed-use soak and a representative planning/replanning workload.
- [ ] No crash, hang, runaway memory, duplicate records, or invalid overlap.

### Signing, privacy, TestFlight, and operations

- [ ] Development and distribution signing use the intended team/bundle ID.
- [ ] HealthKit capability is present in the signed archive.
- [ ] Release archive validates successfully.
- [ ] Privacy nutrition labels match Calendar, Health, Speech, microphone,
      selected files/photos, Keychain, provider, backup, and diagnostics use.
- [ ] Purpose text was reviewed against actual runtime prompts.
- [ ] Privacy policy and support URLs are live and accurate.
- [ ] Export-compliance answers are recorded.
- [ ] TestFlight description, tester instructions, feedback address, provider
      setup, and known limitations are complete.
- [ ] Crash/diagnostic process does not collect sensitive payloads by default.
- [ ] Backup recovery and deletion support procedures are rehearsed.
- [ ] Beta testers complete the synthetic week and judge explanations coherent.

## Cross-phase regression sweep

- [ ] One authoritative schedule is visible consistently in Home, Plan,
      notifications, execution, history, integrations, and Shortcuts.
- [ ] No duplicate scheduler/replanner result appears after any integration
      refresh.
- [ ] External/fixed commitments never move during local replan.
- [ ] AI/OCR/Speech proposals never mutate before explicit Send/confirmation.
- [ ] Replanning preserves past and in-progress state across every input path.
- [ ] Notification requests match final schedule after Calendar, Health,
      voice/text, workout, nutrition, and time-zone changes.
- [ ] Backup/restore preserves schema and behavior across all Phase 1–9 entities.
- [ ] Offline mode leaves deterministic planning, management, execution, and
      history usable.
- [ ] All editable defaults remain editable after migration/restore.
- [ ] Free time and recovery remain legitimate plan outcomes.
- [ ] No raw sensitive data or credential appears in UI diagnostics, logs,
      backup, screenshots, or provider payload.

## Exit record

| Category | Pass | Fail | Blocked | N/A | Defect IDs |
| --- | ---: | ---: | ---: | ---: | --- |
| Phase 1 | | | | | |
| Phase 2 | | | | | |
| Phase 3 | | | | | |
| Phase 4 | | | | | |
| Phase 5 | | | | | |
| Phase 6 | | | | | |
| Phase 7 | | | | | |
| Phase 8 | | | | | |
| Phase 9 | | | | | |
| Cross-phase | | | | | |

Final physical-device result:

- [ ] **PASS**
- [ ] **PASS WITH RISKS** — accepted risks listed below
- [ ] **FAIL — STABILIZATION REQUIRED**

Accepted risks:

```text

```

Release blockers/high-severity defects:

```text

```

Tester sign-off:

```text
Name:
Date:
Signature/approval reference:
```

Phase 10 remains **NO-GO** until the full audit is updated with green automated,
simulator, Release, physical-device, accessibility, performance, signing, and
operational evidence.
