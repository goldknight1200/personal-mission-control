# Phase 1–4 Cross-Phase Consistency Audit

Audit date: 2026-07-24

Scope: repository behavior and architecture through the end of Phase 4 only

Result: **PASS WITH RISKS**

Development gate: **Do not begin Phase 5 until the macOS/Xcode validation in this report is green.**

## 1. Executive summary

The repository now has one coherent Phase 1–4 architecture:

- `MissionControlCore` owns persistence-agnostic domain values, deterministic
  scheduling/replanning, confirmed-command application, execution history, and
  notification policy.
- The iOS target owns SwiftUI state and Apple adapters for SwiftData, Speech,
  and UserNotifications.
- `SchedulingEngine` and `ReplanningEngine` are the authoritative paths for
  schedule generation and schedule-affecting mutations.
- Voice interpretation produces typed proposals and has no direct write
  authority. Explicit send and consequence confirmation remain mandatory.

The wrong implementation order did create material defects. Phase 3 and Phase
4 originally treated execution state as mission-wide, while the later Phase 2
planner reused one mission across several approved-workout schedule
occurrences. Phase 4 skip, partial-completion, and recovery records were also
not fully understood by the later replanner. These conflicts could move or
suppress the wrong occurrence, retain skipped work, resurrect completed
routines, ignore “tomorrow” or “backlog,” and leave voice skips out of
execution history.

The safely fixable Critical and High issues found in this pass were corrected
at narrow boundaries. Snapshot schema 5 adds optional block identity to start
history, legacy records remain decodable, execution mutations now delegate to
the shared domain service, and planning consumes Phase 4 outcome/disposition
history. A separate Critical data-preservation issue was fixed: if durable
state cannot be loaded or migrated, the app now enters visible session-only
mode and cannot overwrite the unreadable store with demo data.

Static repository checks pass. The source contains 97 XCTest methods, including
focused regressions added by this pass. No Swift compiler, Xcode, simulator, or
macOS CI workflow is available in the current Windows environment, so no build
or XCTest result is claimed. That missing executable validation is the reason
for both the **PASS WITH RISKS** result and the Phase 5 hold.

## 2. Evidence reviewed

The audit reviewed:

- `AGENTS.md`, `README.md`, `docs/PRODUCT_SPEC.md`,
  `docs/ROADMAP.md`, and `docs/ARCHITECTURE.md`;
- all Swift source, tests, Xcode project configuration, ignore rules, and
  tracked/untracked repository files;
- all 151 paragraphs and 15 tables in
  `Personal_Mission_Control_Codex_Prompt_Pack_v0.1.docx`, including the Phase
  1–4 prompts and acceptance criteria;
- local commits, reflog-recoverable commits, branches, tags, remotes, and
  relevant trees/diffs;
- remote branch, tag, and pull-ref advertisements from the configured GitHub
  origin.

The DOCX was structurally extracted with the bundled `python-docx` runtime.
Visual DOCX rendering was attempted with the required renderer, but the host
does not have LibreOffice/`soffice`; this did not prevent requirements
extraction because the document structure and text were readable.

## 3. Intended and actual phase order

### Intended order

1. Phase 1 — local domain/persistence foundation and native vertical slice.
2. Phase 2 — deterministic seven-day scheduling and affected-range replanning.
3. Phase 3 — reviewed voice capture and confirmed structured-command pipeline.
4. Phase 4 — notifications, execution recovery, history, reflection, and
   consistency.

### Actual order

1. Phase 1.
2. Phase 3.
3. Phase 4.
4. Phase 2.

The current worktree contains the combined implementation. Git does not contain
usable per-phase snapshots: `main` has two commits, and the annotated
`v0.2-phase-2-baseline` tag peels to a commit whose tree contains only
`.gitattributes`. The two unreachable commits found by `git fsck` also contain
only `.gitattributes`. The configured remote advertises only `main`, the same
tag, and no pull refs. Consequently, phase-order reconstruction is based on the
approved prompt pack, current source, documentation, and identifiable
cross-phase assumptions—not on reliable historical diffs.

## 4. Phase dependency map

| Phase | Intended responsibilities | Models, storage, services, and UI | Assumptions about earlier phases | Current classification |
|---|---|---|---|---|
| 1 | Local-first domain, editable seed/profile, persistence boundary, app composition, five-destination navigation, Home vertical slice | `MissionControlSnapshot`, profile/goals/projects/missions/routines/checklists/completions, `MissionControlRepository`, SwiftData snapshot adapter, `AppModel`, Home/Goals/Lists/Plan/root navigation | No scheduler yet; local state is authoritative and later phases extend the typed snapshot | Satisfied differently but safely. The one-record JSON/SwiftData adapter is simple but versioned and isolated. |
| 2 | Deterministic seven-day plan and affected-range replan; fixed commitments, sleep, food coverage, project minimums, recurrence, recovery constraints, conflicts, decision trace, stability | Scheduling entities, policy fields, `PlanningInput`, `SchedulingEngine`, `ReplanningEngine`, `ScheduleReplanning`, plan metadata/decisions/conflicts, scheduling projections for workouts/nutrition | Phase 1 IDs, dates, repository, profile, missions, routines, and Home timeline are stable | Satisfied correctly after stabilization. Core remains synchronous and side-effect free. |
| 3 | Ephemeral speech capture, transcript review/edit, explicit Send, local typed interpretation, consequence confirmation, atomic application, replan request | `StructuredCommand`, intents/entities/mutations/warnings, `LocalCommandParser`, `CommandMutationApplicator`, Speech port/adapter/view model/review UI, command history | A Phase 2 replanner exists and is the only scheduling authority | Previously duplicated/partially incompatible; now satisfied. Start and skip mutations delegate to Phase 4 execution semantics and schedule effects go through `ScheduleReplanning`. |
| 4 | Stable per-block notifications, due/late recovery actions, current mission, actual timing, partial/skip history, daily reflection, weekly consistency, repeated-miss feedback | Notification entities/planner/port/adapter/settings; mission-start, completion, disposition, check-in, diagnostic records; execution/history views | Phase 2 can preserve actual history, understand Phase 4 dispositions, and replan only the affected future | Previously incompatible in several paths; now satisfied for the supported flows. Device behavior and concurrent notification reconciliation remain validation risks. |

### Detailed phase inventory

| Area | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|---|---|---|---|---|
| Domain models | Profile, goals, projects, missions, routines, fixed commitments, blocks, checklists, completions | Policy, plan metadata, decisions/conflicts, recovery/nutrition/workout scheduling projections | Confirmed transcript, intent/entity, proposed mutation, warning, work-shift payload, command history | Notification request/action, start record, disposition, check-in, diagnostic, weekly summary |
| Services/ports | Repository | Planning/replanning and stable identifiers | Command interpreter and speech transcription | Notification service, execution/recovery, reflection/consistency |
| Storage/migration | One SwiftData record containing typed JSON snapshot | New optional/defaulted snapshot collections and policy fields | Command and pain/inventory/start/replan history | Notification/execution/reflection history; schema 5 block-aware starts |
| Scheduling | Timeline selection only | Authoritative seven-day planner and affected-range replanner | Typed commands emit replan requests | Execution actions emit replan requests and history inputs consumed by Phase 2 |
| UI/navigation | Root composition, Home, Goals, Lists, Plan, center microphone slot, side menu | Plan trace/profile controls and generated Home timeline | Capture/review/confirmation flow | Execution prompts, notification settings, history/consistency |
| Notifications | None | Stable block IDs become a prerequisite | None | UserNotifications adapter and per-block four-stage reconciliation |
| Voice/AI | Microphone navigation placeholder | Deterministic mutation boundary expected | Local parser plus Apple Speech; no AI provider or direct schedule output | Morning changes may use the same confirmed voice path |
| Integrations | SwiftData | None beyond local core | Speech/microphone permission | UserNotifications permission/actions |
| Tests | Domain, repository, timeline, seed, SwiftData round trip | Scheduler/replanner constraints, determinism, stability, migration defaults | Parser, applicator, voice view-model confirmation/atomicity | Notifications, execution, reflection, consistency, adapter failure paths |
| Configuration | iOS 17, Swift tools 5.9, local package | Editable wake/sleep/grid/travel/meal policy | Speech purpose/availability requirements in project configuration | Notification categories/actions registered at launch |
| Earlier-phase assumption | Foundation phase | Stable Phase 1 IDs/profile/repository | Phase 2 is already authoritative | Phase 2 understands Phase 4 history and Phase 3 command effects |

### Phase 3/4 dependencies on Phase 2

| Dependency | Before this pass | Current state |
|---|---|---|
| Confirmed late-wake, mission-move, shift, pain, start, and skip commands invoke one replanner | Present, but start/skip state changes were partly duplicated | **Satisfied correctly**; typed commands call shared execution services and `ScheduleReplanning`. |
| “Already started” preserves only the active occurrence | Mission-wide `.inProgress` could freeze/move every workout occurrence | **Fixed** with block-aware start records and schema-4 fallback. |
| Skip removes affected future work but preserves history | Replanner froze all completion records, including `.skipped` | **Fixed**; only completed/partial actual history is frozen. |
| Partial completion records actual work and replans the remainder | Phase 4 wrote history without Phase 2 replanning and used scheduled rather than actual start | **Fixed**; it uses the actual-start record and the replanner. |
| Recovery choices remain authoritative planning inputs | Phase 2 ignored Phase 4 dispositions | **Fixed** for singular missions and one active approved-workout recovery choice. |
| Repeated workout actions target one occurrence | Mission-level status/disposition could affect the weekly series | **Fixed** for starts, outcomes, notifications, tomorrow, backlog, and day replacement. Multiple simultaneous dispositions remain a Medium risk. |
| Routine completion survives plan regeneration | Generated routine mission could be recreated as planned | **Fixed**; resolved occurrence IDs are excluded and historical generated missions are retained. |
| Phase 4 notifications follow Phase 2 block identity | Starting one occurrence suppressed reminders for all occurrences | **Fixed**; pending requests are evaluated per block. |
| Fixed commitments remain exact | Command adds a typed `FixedCommitment`; Phase 2 reconstructs exact block and reports overlaps | **Satisfied correctly**. |
| Deterministic command application is atomic | Copy/apply/replan/save/publish path already existed | **Satisfied differently but safely**; duplicate command IDs are now idempotent. |

## 5. Repository architecture and structure

### Module boundaries

```text
PersonalMissionControl (iOS app)
  SwiftUI, AppModel, SwiftData, Speech, UserNotifications
                  |
                  v
MissionControlCore (local Swift package)
  Domain, Commands, Scheduling, Execution, Ports, Seed
```

- Core imports are Foundation-only. No SwiftUI, SwiftData, Speech, or
  UserNotifications type crosses into the package.
- The core scheduler/replanner has no persistence or platform side effects.
- `AppModel` performs copy-mutate-replan-save-publish operations on the main
  actor.
- The SwiftData adapter stores one versioned typed JSON payload. This is a
  deliberate adapter decision, not a second domain model.
- `PendingRequestScheduleReplanner` is an isolated test/fallback bridge, not a
  production scheduler competing with `ReplanningEngine`.

### Structure findings

- No duplicate declared type names were found across core and app source.
- No second scheduling engine, parallel persistence model, circular import, or
  cross-layer UI write was found.
- All app/test Swift filenames are referenced by the Xcode project; Swift
  package files are package-discovered.
- No third-party package, backend, API key, credential, tracked environment
  file, build output, Xcode user state, or Office lock file is tracked.
- The Office owner-file pattern `~$*.docx` was missing and is now ignored.
- The only placeholder/stub matches are documented future-phase destinations;
  they do not claim Phase 5–9 behavior.
- Git emits LF-to-CRLF warnings because `.gitattributes` only uses
  `* text=auto`. This is Low risk but should be normalized in a separate,
  intentional repository-hygiene change.
- Dead-code certainty requires a successful compiler/indexer run. Static
  inspection did not identify an obsolete authoritative implementation safe
  to delete.

## 6. Data models and persistence

### Identity and time

- `EntityID` remains the stable entity identity.
- Absolute `Date` values are used for schedule instants and history.
- Local day, recurrence, and horizon decisions explicitly select the profile
  time zone (`Europe/Berlin` in the seed).
- Durations are consistently integer minutes; schedule storage uses `Date`
  endpoints.
- Half-open schedule intervals are covered by timeline tests.

The material identity correction is that a reusable mission may own several
schedule blocks. Mission identity names the work definition; schedule-block
identity names the execution occurrence. `MissionStartRecord` now has an
optional `scheduleBlockID`. New state is written at snapshot schema 5. Old
schema-4 records decode with `nil` and use a deterministic active/upcoming/last
block fallback.

### Persistence compatibility

- Snapshot collections added after Phase 1 use `decodeIfPresent` defaults.
- Legacy planning-policy and nutrition fields have explicit decode defaults.
- SwiftData rejects a future schema version.
- Older supported records are decoded, promoted to the current schema, encoded,
  and saved through a rollback-protected context.
- Representative Phase 1 payload and legacy start-record fixtures exist.
- Actual production snapshots from the historical phase points do not exist in
  Git, so fixture coverage cannot be compared byte-for-byte with a real old
  store.

### Data-loss protection

Before this pass, a load/decode/migration failure caused `AppModel` to create
demo state and later allowed that demo state to be written through the same
repository. That could destroy the only corrupted-but-recoverable payload.

Now a load failure:

1. publishes a visible session-only notice;
2. keeps an in-memory seed so the UI remains usable;
3. disables every repository write for that `AppModel` lifetime;
4. permits in-session mutations without claiming durable success.

No automatic deletion or overwrite of the unreadable record is performed.

## 7. Scheduling and replanning audit

The authoritative pipeline is:

```text
validated mutation
  -> MissionControlSnapshot working copy
  -> typed ReplanRequest(s)
  -> ReplanningEngine
  -> PlanningInput
  -> SchedulingEngine
  -> SchedulingResult + decisions/conflicts
  -> atomic repository save
  -> AppModel publish
  -> notification reconciliation
```

Confirmed behavior in source and focused tests:

- exact fixed commitments are reconstructed and never snapped;
- overlapping fixed commitments remain exact and emit a blocking conflict;
- generated mission blocks use the configured five-minute grid;
- sleep, essential meal coverage, preparation, travel, recovery, and optional
  free time participate as explicit stages;
- projects receive at least the configured 30-minute useful block;
- recovery context, match proximity, and active pain flags restrict demanding
  physical work;
- recurrence uses explicit due windows and a stable cadence epoch;
- replanning freezes past, completed/partial actual history, the one
  block-specific in-progress occurrence, and unaffected future work;
- skip does not freeze the skipped future block;
- later-today/tomorrow create bounded due windows;
- weekly-backlog/drop exclude a singular mission or one approved-workout
  occurrence from current allocation;
- resolved routine occurrences do not regenerate;
- workout occurrence matching is local-day based rather than array-index based;
- notification identity is mission + block + stage;
- the same structured input and stable identifier generator produce stable
  plan/decision output.

No old score-based priority path or UI-side placement logic was found.

## 8. End-to-end Phase 1–4 flows and sources of truth

| Flow | Trace | Authoritative state transitions | Result |
|---|---|---|---|
| A. Create and schedule | Reviewed voice text → parser → proposed work shift → explicit confirmation → `FixedCommitment` → replan → save → Home timeline | Parser proposes; applicator validates; Phase 2 planner places; repository commits; `AppModel` publishes | Satisfied for Phase 1–4 supported creation. A general task editor is Phase 5, not silently implemented here. |
| B. Voice input | Press/hold or typed fallback → ephemeral transcript → editable review → explicit Send → typed proposal → consequence sheet if required → apply/replan | Speech adapter owns capture only; `StructuredCommand` is proposal/history; applicator and replanner own mutation | Satisfied. Release/review alone cannot mutate state; duplicate IDs are idempotent. |
| C. Missed task | Per-block pre/start/+15/+30 notification → action → execution service → replan/save → reconcile pending requests | Notification planner owns desired requests; `MissionExecution` owns outcome; Phase 2 owns schedule | Satisfied in source; delivery/action routing still needs an iPhone. |
| D. Current mission | Current time → `ScheduleTimeline` → Home progress/mini-goals → completion/partial → execution history/replan | Timeline owns selection; AppModel routes input; core owns history and schedule | Satisfied. Partial duration uses the matching actual-start record. |
| E. Weekly planning | Profile/goals/projects/commitments/routines → `PlanningInput` → seven-day result → daily timeline and decision trace | Snapshot inputs and Phase 2 planner | Satisfied. |
| F. Project protection | High-value project mission → minimum useful duration → placement → repeated-miss diagnostic/reassessment request | Phase 2 policy and Phase 4 diagnostic history | Satisfied for minimum allocation/reassessment. Explicit remaining-segment modeling is a Medium product-model risk. |
| G. Gym session | Approved-workout projection → weekly occurrences → prep/travel/recovery → per-block execution → recovery-aware replan | `ApprovedWorkout` is scheduling input; block ID is execution occurrence | Satisfied through Phase 4. Exercises/sets/reps/rest are intentionally Phase 7. |
| H. Food planning | Profile targets (~3,400 kcal/~180 g) + nutrition need/deficit → protected eating coverage → schedule | Phase 2 nutrition projection and profile | Satisfied at Phase 2 projection depth. Meal templates, macro detail, inventory inference, and shopping generation are Phase 6. |
| I. Recovery | Sleep under six hours, match proximity, or pain flag → candidate restriction/omission → replan/conflict trace | Recovery context/pain history and Phase 2 rules | Satisfied in deterministic fixtures. HealthKit is Phase 8 and is not claimed. |
| J. Household recurrence | Recurrence → nominal occurrence ID/due window → compatible bundling → completion history → next occurrence | Routine definition, stable generated ID, Phase 2 planner, completion history | Satisfied. Monthly recurrence without an anchor remains visible as a warning rather than guessed. |

## 9. UI and navigation consistency

Static inspection confirms:

- Home remains a continuous vertical execution timeline.
- The top-right menu opens deeper administrative destinations.
- Current mission time/progress, mini-goals, chronological upcoming cards,
  category accents, and subdued preparation/travel cards remain present.
- Bottom navigation remains Home, Goals, central Microphone, Lists, and Plan.
- Voice capture/review is a modal workflow rather than a competing destination.
- The side menu does not duplicate the primary execution flow.
- Views call `AppModel`; they do not directly write SwiftData or schedule blocks.
- Error/permission states exist for persistence, speech, and notifications.
- Calendar, Health, nutrition-detail, workout-detail, and AI destinations are
  labeled as future integrations rather than mocked as complete.

Stale “Phase 1 only” copy in Goals and incorrect Calendar/Health phase text
were corrected. No redesign was performed.

Common iPhone layout, Dynamic Type, VoiceOver, reduced motion, and live refresh
after actual notification actions remain simulator/device validation items.

## 10. Error handling, concurrency, and safety

### Corrected

- Empty/unknown voice input is rejected without mutation.
- High-impact commands require final confirmation.
- Duplicate prepared-command application is idempotent.
- Fully past work shifts are rejected by both interpreter and authoritative
  applicator; an already-started but still active shift is explicitly warned.
- Fixed overlaps remain visible conflicts.
- No-space candidates become unscheduled decisions rather than disappearing.
- Repository saves use working copies and publish only after a successful save.
- Repository load/migration failure cannot overwrite durable state.
- Denied/unavailable Speech and notification services retain safe fallback UI.

### Remaining concurrency/state risks

- Notification reconciliation is launched as a main-actor task after mutations.
  Core state access is isolated, but multiple rapidly queued reconciliations
  are not explicitly coalesced into a single revisioned drain. Stable request
  IDs make the end state repairable, but this should be stress-tested and then
  serialized if stale adapter calls are observed.
- A consequence-confirmation sheet does not carry a snapshot revision token.
  Another app event can update state before confirmation. The applicator
  revalidates identifiers and dates against current state, but it does not
  reject solely because the proposal was prepared from an older revision.
- Session-only mode protects corrupted storage but has no export/repair UI.
  That recovery workflow belongs in a later authorized hardening scope.

## 11. Issues found and status

### Critical

| ID | Issue and root cause | Phase-order relationship | Status |
|---|---|---|---|
| C-01 | Load/migration failure could be followed by fallback-seed writes, overwriting the unreadable durable record. Phase 1 recovery assumed ordinary save failures and did not anticipate a later, growing snapshot schema. | Exposed by later phases; not solely caused by order | **Fixed.** Repository writes are disabled after load failure; session mode is visible and regression tested. |

### High

| ID | Issue and root cause | Phase-order relationship | Status |
|---|---|---|---|
| H-01 | Mission-wide in-progress state was applied to every Phase 2 occurrence of a reusable workout mission. | Directly caused | **Fixed.** Block-aware starts, locks, lateness, notifications, schema migration, and tests. |
| H-02 | Replanner froze every completion record, so Phase 4 `.skipped` blocks could remain in the future plan. | Directly caused | **Fixed.** Only completed/partial actual history is immutable. |
| H-03 | Phase 4 partial completion bypassed Phase 2 replanning and inferred work from scheduled start. | Directly caused | **Fixed.** Actual-start duration and affected-range replan are authoritative. |
| H-04 | Phase 2 ignored Phase 4 recovery dispositions; tomorrow/backlog could collapse to ordinary replanning. | Directly caused | **Fixed.** Dispositions become due-window/deferred planning inputs, including one workout occurrence. |
| H-05 | Generated routine occurrences could be resurrected, and skipped workout days could shift array-index pairing and duplicate/move other occurrences. | Directly caused | **Fixed.** Completion-aware generation and day-keyed matching. |
| H-06 | Phase 3 reimplemented start/skip mutations and voice skip did not create Phase 4 execution history. | Directly caused | **Fixed.** `CommandMutationApplicator` delegates to `MissionExecution`; all schedule effects use `ScheduleReplanning`. |

No known Critical or High issue remains open.

### Medium

| ID | Issue | Relationship | Status |
|---|---|---|---|
| M-01 | The same prepared command could be applied twice. | Exposed by Phase 3 confirmation state | **Fixed** with command-ID idempotency. |
| M-02 | A typed past shift could bypass parser warnings. | Unrelated safety gap | **Fixed** at parser and applicator boundaries. |
| M-03 | Actual duration could include a late-start delay. | Phase 4/2 integration gap | **Fixed** using block-specific start history. |
| M-04 | Several simultaneous unresolved dispositions for the same reusable workout series collapse to the latest mission-scoped planning projection. | Caused by mission/occurrence mismatch | **Open, documented.** One active recovery choice is correct; multi-disposition modeling needs a separate, tested domain change. |
| M-05 | Notification reconciliation is not revision-coalesced. | Unrelated async adapter risk | **Open, device/stress validation required.** |
| M-06 | Prepared confirmations have no snapshot revision token. | Unrelated stale-state risk | **Open, revalidation is partial.** |
| M-07 | Real historical Phase 1–4 payloads and commits are unavailable. | Repository-history problem | **Open.** Representative fixtures are the available evidence. |
| M-08 | No macOS CI workflow exists; no Swift/Xcode validation ran. | Repository configuration gap | **Open and release-blocking.** |
| M-09 | Project minimum placement does not model a named “remaining duration” segment separately. | Phase 2 model ambiguity | **Open, document before changing behavior.** |
| M-10 | UI/accessibility and Apple-adapter coverage is limited to view-model/adapter tests. | Test-depth gap | **Open, simulator/device validation required.** |

### Low

| ID | Issue | Status |
|---|---|---|
| L-01 | Phase baseline tag/history is misleading and cannot reconstruct phases. | Documented; do not rewrite published history during this pass. |
| L-02 | Office owner/lock file was unignored. | Fixed with `~$*.docx`. |
| L-03 | Goals and integration placeholder copy was stale. | Fixed without redesign. |
| L-04 | LF/CRLF behavior is not explicitly normalized. | Documented; no bulk line-ending rewrite performed. |
| L-05 | Monthly recurrence lacks a persisted anchor. | Existing deterministic warning retained; no guessed behavior added. |

## 12. Fixes implemented and files modified

The implemented corrections are the fixed Critical/High/Medium items in
Section 11: safe session-only persistence fallback, occurrence-aware execution,
completion/disposition-aware replanning, shared voice/execution mutation logic,
actual-start duration accounting, command idempotency, past-date validation,
and narrow UI/repository hygiene. Their file-level scope is listed below.

### Core behavior and persistence

- `Packages/MissionControlCore/Sources/MissionControlCore/Domain/CommandSupportEntities.swift`
- `Packages/MissionControlCore/Sources/MissionControlCore/Domain/MissionControlSnapshot.swift`
- `Packages/MissionControlCore/Sources/MissionControlCore/Commands/CommandMutationApplicator.swift`
- `Packages/MissionControlCore/Sources/MissionControlCore/Commands/LocalCommandParser.swift`
- `Packages/MissionControlCore/Sources/MissionControlCore/Execution/MissionExecution.swift`
- `Packages/MissionControlCore/Sources/MissionControlCore/Execution/NotificationSchedulePlanner.swift`
- `Packages/MissionControlCore/Sources/MissionControlCore/Scheduling/PlanningContracts.swift`
- `Packages/MissionControlCore/Sources/MissionControlCore/Scheduling/ReplanningEngine.swift`
- `Packages/MissionControlCore/Sources/MissionControlCore/Scheduling/SchedulingEngine.swift`
- `PersonalMissionControl/App/AppModel.swift`

### Tests

- `Packages/MissionControlCore/Tests/MissionControlCoreTests/CommandMutationApplicatorTests.swift`
- `Packages/MissionControlCore/Tests/MissionControlCoreTests/DomainModelTests.swift`
- `Packages/MissionControlCore/Tests/MissionControlCoreTests/LocalCommandParserTests.swift`
- `Packages/MissionControlCore/Tests/MissionControlCoreTests/NotificationSchedulePlannerTests.swift`
- `Packages/MissionControlCore/Tests/MissionControlCoreTests/ReplanningEngineTests.swift`
- `Packages/MissionControlCore/Tests/MissionControlCoreTests/SchedulingEngineTests.swift`
- `PersonalMissionControlTests/ExecutionFlowTests.swift`

### Documentation/UI hygiene

- `docs/ARCHITECTURE.md`
- `PersonalMissionControl/Features/Goals/GoalsView.swift`
- `PersonalMissionControl/UI/SharedViews.swift`
- `.gitignore`

The worktree already contained extensive user-owned Phase 2–4 changes before
this audit. They were preserved; no reset, broad revert, history rewrite, or
unrelated deletion was performed.

## 13. Focused tests added or strengthened

The suite now contains 97 XCTest methods: 83 core-package tests and 14 app
tests. Material audit regressions include:

- legacy Phase 1 snapshot defaults and legacy start-record decoding;
- no durable overwrite after repository load failure;
- actual-start-aware partial completion and replanning;
- Phase 4 skip history removes the future block;
- tomorrow and weekly backlog remain distinct;
- one repeated mission start does not move every occurrence;
- one in-progress occurrence does not suppress later reminders;
- resolved routine occurrence does not reappear;
- skipped workout day preserves other occurrences and finds a replacement;
- workout tomorrow/backlog recovery changes one occurrence, not the series;
- same prepared command is idempotent;
- voice skip creates Phase 4 completion history;
- past shifts are rejected by parser and applicator.

Existing focused coverage also maps to fixed overlap reporting, exact fixed
times, five-minute grid placement, sleep and food protection, 30-minute project
minimums, travel/preparation/recovery, football-match proximity, pain blocking,
calorie deficit, recurrence/due windows, schedule determinism and stability,
voice confirmation, permission denial, persistence rollback, and SwiftData
migration.

These tests were inspected and statically referenced, but **not executed** on
this host.

## 14. Commands and validation results

### Requirements and repository inspection

| Command/check | Result |
|---|---|
| `rg --files -uu .` | Completed; full repository inventory reviewed. |
| Bundled Python `Document("Personal_Mission_Control_Codex_Prompt_Pack_v0.1.docx")` structural extraction | Completed: 151 paragraphs, 15 tables, 137 non-empty paragraphs. |
| Bundled `render_docx.py ... --output_dir .audit-temp/prompt-pack-render` | Attempted; not executable because LibreOffice/`soffice` is absent. |
| `git log --all --decorate --oneline --graph -20` | Completed; two reachable commits. |
| `git branch -a -vv` / `git tag -n` / `git remote -v` | Completed; only `main`, origin/main, and the Phase 2 tag. |
| `git fsck --no-reflogs --unreachable --no-progress` | Completed; two unreachable `.gitattributes`-only commits found. |
| `git ls-tree -r --name-only <phase/tag commits>` | Completed; confirmed baseline/history limitation. |
| `git ls-remote --heads --tags origin` | Completed against GitHub; only remote `main` and the Phase 2 tag. |
| `git ls-remote origin 'refs/pull/*/head'` | Completed; no pull refs advertised. |

### Static safety and structure

| Command/check | Result |
|---|---|
| `git diff --check` | **Pass**; no whitespace errors. LF→CRLF warnings remain. |
| `rg -n "^(<<<<<<<\|=======\|>>>>>>>)" --glob '!.git/**' .` | **Pass**; no conflict markers. |
| TODO/FIXME/stub/placeholder scan | Completed; only documented phase/status copy found. |
| Secret/credential-pattern scan | **Pass**; documentation references only, no credential found. |
| Tracked generated/secret filename scan | **Pass**. |
| Core import-boundary check | **Pass**; Foundation only. |
| Duplicate declared type-name check | **Pass**. |
| App/test Xcode project filename-reference check | **Pass**. |
| Swift delimiter-count check across 59 Swift files | **Pass** as a coarse syntax check; it is not a compiler. |
| GitHub workflow inventory | None present. |

### Build and tests

| Exact command | Result |
|---|---|
| `swift test --package-path Packages\MissionControlCore` | **Not executable**: `swift` is not installed. |
| `xcodebuild -project PersonalMissionControl.xcodeproj -scheme PersonalMissionControl -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test` | **Not executable**: `xcodebuild` is not installed. |
| `gh --version` / `gh auth status` | **Not executable**: GitHub CLI is not installed. Remote refs were checked with Git instead. |

No test was delegated to GitHub Actions because the repository has no workflow
and the audited changes are local/uncommitted. No green build or test status is
claimed.

## 15. Required GitHub/macOS CI validation

Before Phase 5, a macOS runner with a supported stable Xcode must execute:

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

CI must retain and report failures; no test should be disabled to make the
workflow green. At minimum, verify Swift 5.9 language compatibility, actor
isolation, Xcode project membership, schema-1/schema-4 migration fixtures, and
all cross-phase regressions listed above.

Because no workflow exists, the next repository-maintenance action should add
or run an approved macOS validation workflow and record its Xcode version.

## 16. Required physical-device validation

An iPhone running the supported iOS range must verify:

- microphone and Speech authorization denied/allowed transitions;
- press/hold capture, partial transcript updates, release-to-review, edit,
  explicit Send, cancel, retry, and audio-buffer disposal;
- on-device recognition when available and Apple fallback behavior otherwise;
- notification authorization, all four offsets, stable replacement/cancel,
  action-category routing, cold launch, and rapid successive replans;
- complete, partial, already-started, start-now, tomorrow, backlog, and skip
  actions from notification and in-app surfaces;
- SwiftData persistence across termination/relaunch and upgrade from an actual
  older installed build if one can be produced;
- common iPhone sizes, Dynamic Type, VoiceOver actions/labels, color
  independence, and reduced motion.

HealthKit and EventKit behavior is not a Phase 1–4 requirement; their current
destinations correctly remain unavailable/future-facing.

## 17. Remaining risks

1. Compilation, XCTest, simulator UI, and release build are unverified.
2. The repository has no macOS CI workflow.
3. The combined Phase 2–4 source and tests are mostly uncommitted/untracked, so
   audit reproducibility depends on preserving this worktree.
4. No real historical persisted payload or usable per-phase Git tree exists.
5. Multiple simultaneous recovery dispositions for one reusable workout series
   need a richer occurrence-level projection.
6. Notification reconciliation should be stress-tested for rapid mutations and
   revision-coalesced if stale adapter calls appear.
7. Confirmation proposals have no state-revision token.
8. Project remainder semantics and monthly recurrence anchoring need explicit
   product decisions before changing behavior.
9. Device accessibility and Apple permission/action behavior remain unverified.

## 18. Recommended next phase and go/no-go

**Current recommendation: NO-GO for starting Phase 5 until the macOS core
tests, iOS simulator tests, and release build are green.**

If those checks pass without weakening tests, development may continue to
**Phase 5 — Goals, projects, lists, routines, shopping, and shifts**. Phase 6
nutrition detail, Phase 7 workout execution, Phase 8 Apple integrations, and
Phase 9 optional AI remain out of scope and were not started.

Architecturally, no known Critical or High inconsistency remains through Phase
4. The repository is therefore classified **PASS WITH RISKS**, with executable
toolchain validation as the mandatory next action.
