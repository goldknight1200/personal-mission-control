# Roadmap

Each phase begins with an audit of the prior acceptance criteria. Later phases extend stable boundaries rather than rewriting them without an explicit migration reason.

Stabilization evidence as of 2026-07-27: revision
`68e00784c7cee37ff5509da1fcc02647701560e6` passed static validation, all 151
core tests, all 22 application/simulator tests, and the unsigned Debug build in
the authoritative macOS/Xcode workflow. The final launch-smoke and unsigned
Release conclusions could not be re-read after the authenticated GitHub account
reached its usage limit, so they remain open rather than inferred. No
physical-device checklist item is implied by this automated evidence.

## Phase 1 — Local vertical slice

Audited completion status as of 2026-07-26: **Complete with risks**.
The implementation passed the recorded core, complete simulator-test, and
unsigned Debug gates; launch-smoke confirmation and physical-device validation
remain pending.

Implement the core domain model, SwiftData adapter, app navigation, editable seed profile, structured sample inputs, and minimal execution-focused Home experience.

Acceptance criteria:

- Domain types cover the product-contract model without importing Apple UI/persistence frameworks.
- Repository protocols have an in-memory test implementation and a SwiftData app adapter with round-trip tests.
- Home identifies Now, Next, and Later; preparation/travel are visibly subdued.
- The user can one-tap complete a mission and optionally correct actual duration.
- Goals, Lists, Plan, and settings destinations exist as honest placeholders or first slices; no fake integrations.
- Seed defaults are editable data, not scattered constants.
- The app launches with local sample/seed state and without an account or network.

## Phase 2 — Deterministic scheduling and replanning

Audited completion status as of 2026-07-26: **Complete with risks**.
The intended source is present; recovered planner/replanning corrections,
including unique project occurrence allocation, passed the recorded automated
tests. Launch-smoke confirmation and physical-device validation remain pending.

Implement the seven-day staged planner, detailed current-day timeline, explainable decisions, conflict reporting, and minimal-change replanning.

Acceptance criteria:

- Hard constraints are processed before ranked soft constraints; no opaque single-score planner.
- Fixed/external work, sleep, meals, transitions, protected activities, projects, routines, chores, and free time follow the documented order.
- Replanning freezes history, preserves in-progress work, and minimally moves unaffected future blocks.
- Scheduling decisions explain placements, omissions, moves, conflicts, recovery choices, and confirmation requirements.
- All scheduler cases listed in `docs/ARCHITECTURE.md` have deterministic unit tests.
- A late-start structured input updates the Home timeline without network or AI.

## Phase 3 — Voice review and command pipeline

Audited completion status as of 2026-07-26: **Complete with risks**.
The intended source passed the recorded automated gates; simulator microphone,
live Speech, launch-smoke confirmation, and physical-device validation remain
pending.
Schedule-affecting commands feed confirmed typed requests to the deterministic
Phase 2 replanner.

Add press-and-hold recording, release-to-stop, transcription availability handling, editable review, and typed command proposals.

Acceptance criteria:

- No transcript is processed or applied before Send.
- Review offers Send, Edit, Retry, and cancel; text entry remains available.
- Raw and confirmed transcripts, intents/confidence, entities, mutations, affected range, warnings, and confirmation state follow the command contract.
- A baseline local/rule-based interpreter handles key commands and feeds deterministic validation/replanning.
- Audio is deleted after transcription by default; denial, unavailability, interruption, and retry paths are tested.
- No raw calendar or HealthKit dataset is sent to a provider.

## Phase 4 — Notifications, recovery, history, and consistency

Audited completion status as of 2026-07-26: **Complete with risks**.
The intended source and notification adapter corrections passed the recorded
automated gates; launch-smoke confirmation, notification-action, and
physical-device validation remain pending.
Recovery operations use the deterministic Phase 2 replanner after explicit
decisions.

Implement actionable local notifications, missed-start recovery, daily check-ins, completion history, and weekly adherence summaries.

Acceptance criteria:

- Default pre-start, start, 15-minute-late, and 30-minute-late states reconcile when plans change.
- Already Started corrects actual start; Start Now replans; Replan evaluates alternatives; Skip records consequences.
- Morning planning is provisional with a lightweight “Anything changed?” path.
- Evening is passive unless unresolved items require a disposition.
- Weekly football, gym, project, nutrition, and sleep metrics compare actual with planned/target without shaming language.
- Repeated misses surface a cause-reassessment flow rather than endless automatic rescheduling.

## Phase 5 — Goals, projects, lists, routines, shopping, and shifts

Audited completion status as of 2026-07-26: **Complete with risks**.
The intended source passed the recorded automated gates; launch-smoke
confirmation, full management/voice UI journeys, and physical-device
validation remain pending.

Build complete management flows for structured work and recurring responsibilities.

Acceptance criteria:

- Goals and unlimited projects support active priority, maintained, and backlog state plus user-approved priority overrides.
- Today one-offs, shopping, and routines have focused list experiences and due-window behavior.
- Work shifts can be entered naturally in batches, reviewed as fixed events, and confirmed before saving.
- Recurrence and due windows handle the household seed rules and efficient compatible bundling.
- Important maintained projects receive reasonable exposure without forced daily allocation.
- Repeated project skips trigger priority reassessment.

## Phase 6 — Nutrition and food inventory

Audited completion status as of 2026-07-26: **Complete with risks**.
The intended source passed the recorded automated gates; launch-smoke
confirmation, full management UI journeys, and physical-device validation
remain pending.

Implement nutrition targets, meal templates/plans, low-friction inventory, shortage prediction, and meal/shopping scheduling.

Acceptance criteria:

- Planned intake estimates calories/protein and substantial-meal coverage without demanding exact tracking.
- Clear deficits create an explainable warning, useful suggestion, and suitable eating block.
- Inventory supports quantities and qualitative remaining/low states.
- Likely shortages produce proposed shopping items before depletion and combine with suitable trips/work when practical.
- All targets, cadence, and inference thresholds are editable.

## Phase 7 — Workout execution and recovery constraints

Audited completion status as of 2026-07-26: **Complete with risks**.
The intended source and occurrence-recovery corrections passed the recorded
automated gates; launch-smoke confirmation, rest-timer interaction, and
physical-device validation remain pending.

Implement user-approved programs, session execution, set/rest state, logs, and recovery-aware scheduling.

Acceptance criteria:

- Programs preserve exact exercises, sets, rep ranges, rest, prior performance, and actual weight/reps.
- The current exercise/set and rest timer can become the active mission detail.
- The product never invents random workouts outside the approved program.
- Match proximity, post-match recovery, sleep context, and body-area pain flags deterministically restrict affected work.
- Clearance/reassessment is explicit and logged; blocked exercises do not silently return.

## Phase 8 — Apple platform integrations

Audited completion status as of 2026-07-26: **Partial**.
Concrete adapters compiled and their core/application tests passed in the
recorded automated gates. Launch-smoke confirmation, signed-device entitlement,
Siri, Calendar, and Health validation remain pending.

Add permission-aware Calendar, Health sleep, Siri/App Intents, App Shortcuts, and iCal adapters.

Acceptance criteria:

- Every adapter conforms to a core protocol and has a denial/unavailable fallback.
- Calendar imports retain exact times and immutable/external metadata without leaking EventKit types into the core.
- Health integration reads the minimum sleep/recovery context after explicit permission and keeps raw samples on device.
- App Intents expose safe, confirmation-appropriate actions without bypassing consequence rules.
- iCal import supports externally managed fixtures with reconciliation tests.
- Entitlements, purpose strings, availability, simulator limits, and device-only validation are documented.

## Phase 9 — Optional AI/OCR, hardening, privacy, and beta

Audited completion status as of 2026-07-26: **Partial**.
Substantial optional AI/OCR and hardening source compiled and passed the
recorded core/application test and unsigned Debug gates. Launch-smoke and
unsigned Release conclusions, signed-device, configured-provider,
accessibility, supported-device performance, TestFlight, and full beta
validation remain pending. Production readiness is not claimed.

Add an optional minimal-context AI interpreter, optional shift-image extraction, production hardening, privacy controls, and beta readiness.

Acceptance criteria:

- AI is opt-in/configurable, has no direct write authority, and is unnecessary for deterministic planning.
- The app shows a concise confirmation summary for every proposed AI/OCR mutation.
- Provider payloads are minimized and inspectable; credentials use secure storage.
- Manual text/voice shift entry remains available when OCR fails or is disabled.
- Privacy review covers permissions, retention/deletion, exports, logs, recordings, calendar, health, and provider disclosure.
- Performance, migration, accessibility, localization/time-zone, offline, and failure-path tests pass on supported devices.
- Signing, entitlements, TestFlight metadata, and beta feedback/crash processes are ready and documented.

## Cross-phase release gates

- Planning remains deterministic, testable, and available without an AI service.
- Personal defaults remain editable.
- Free time and recovery remain legitimate outcomes.
- Consequential actions are explicit, explainable, and user-controlled.
- New Apple/framework dependencies stay behind protocols with denied-permission behavior.
- Exact build/test commands and unvalidated device/account requirements are reported for every handoff.
