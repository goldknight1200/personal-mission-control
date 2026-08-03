# Personal Mission Control

Personal Mission Control is a native iPhone app intended to turn goals, obligations, routines, recovery needs, and changing daily input into a realistic plan. The deterministic core remains useful offline; future AI support is limited to interpreting confirmed natural-language input into proposed structured changes.

## Status

Phases 1 through 9 are implemented in source:

- framework-independent domain models, editable personal defaults, repository protocols, and a staged deterministic planner/replanner in the local core package;
- schema-versioned local SwiftData persistence with an in-memory fallback;
- structured local seed inputs, a persisted seven-day generated plan, completion/checklist interactions, and editable profile/category accents;
- exact fixed commitments, protected sleep and meals, real preparation/travel/recovery time, routine due windows, project minimum blocks, recovery restrictions, and preserved free time;
- stable `SchedulingDecision` explanations, explicit conflict records, and minimal-change same-day replanning that freezes history and in-progress work;
- Home, Goals, Lists, and Plan navigation with a press-and-hold central microphone and right-side settings menu;
- editable transcript review with explicit Send, Edit, Retry, and Cancel actions;
- a deterministic local interpreter, typed mutation/confirmation contract, atomic persistence, and structured replanning requests applied by the local engine;
- on-device Apple Speech recognition when available, system speech fallback otherwise, and typed-entry fallback for denied or unavailable speech;
- actionable local mission notifications with deterministic pre-start, start, late-15, and late-30 reconciliation;
- explicit Already Started, Start Now, Replan, and consequential Skip recovery flows;
- lightweight morning and passive evening surfaces, persisted planned-versus-actual history, repeated-miss diagnosis, and weekly consistency summaries;
- complete broad-goal, project, mission, one-off, shopping, and routine management with user-owned priorities, weekly planned/actual project hours, flexible cadence anchors, and compatible-work metadata;
- shopping-to-mission checklists, optional inventory links, purchased state, and deterministic supermarket-shift bundling when the due window fits;
- reviewed monthly work-shift entry from text or ephemeral voice transcription, including multiple ranges, inferred-date warnings, existing-shift changes, conflict disclosure, and fixed-commitment replanning;
- useful Day, Week, and Month inspection with fixed commitments beyond the seven-day generated horizon and persisted manual occurrence adjustments;
- editable approximate nutrition targets and deficit thresholds, reusable meal templates, planned meals, and a seven-day calories/protein/substantial-meal coverage view;
- deterministic deficit suggestions that choose a practical saved option or generic eating block, explain the approximate shortfall, schedule around fixed work and sleep, and remain editable or declineable;
- qualitative, exact-quantity, and meals-remaining inventory; optional completion decrement; voice/text inventory updates; and shortage-driven Shopping proposals that reuse supermarket-shift bundling;
- editable two-to-three-day meal-prep cadence through the existing flexible routine planner;
- user-approved workout programs with exact ordered sessions, exercises, sets, rep targets/ranges, rest times, optional load/progression notes, and a seeded four-session upper/lower rotation;
- occurrence-aware gym scheduling that follows the approved rotation and weekly target while filtering heavy lower-body work around matches, post-match recovery, football training, under-six-hour sleep context, and active body-area pain flags;
- a current-gym Home detail and workout execution flow with actual weight/reps per set, previous performance, persisted current-set/rest state, explicit completion, and occurrence-only shortened-session suggestions;
- explicit pain reassessment/clearance records that restore affected exercises without medical claims or silent template changes;
- opt-in EventKit write-only or full-access modes, exact immutable calendar imports, app-owned event export/update markers, and source-key reconciliation without silent duplication;
- opt-in HealthKit Sleep Analysis read access that keeps raw samples in the adapter and stores only an optional derived sleep window/duration as non-medical recovery context;
- Siri and Shortcuts actions for what is next, Today/Shopping capture, current-mission completion, reviewed capture opening, and deterministic same-day replanning;
- read-only HTTPS/webcal fixture subscriptions with UID-based updates, cancellation and coverage-safe deletion, plus externally managed scheduler protection;
- explicit disabled, denied, restricted, limited, and unavailable integration fallbacks with the local app remaining fully functional;
- an opt-in custom HTTPS JSON AI adapter with a strict versioned response contract, a minimum-context request preview, device-Keychain bearer credentials, local output validation, mandatory AI proposal confirmation, and deterministic local fallback;
- optional photo/file rota extraction using on-device Vision text recognition, low-confidence ambiguity disclosure, existing-shift comparison, zero preselection, and the same confirmed fixed-commitment flow as manual shift entry;
- schema-10 privacy settings, command-transcript redaction, full local JSON backup/validated restore, destructive local-data reset, dataset-growth inspection, significant-time/DST replanning, and serialized notification reconciliation after edits;
- Dynamic Type scaling for the Home time surface and microphone control, reduced-motion handling for primary animations, semantic system colors that adapt to light/dark appearance, and color-independent text/icon labels;
- a repeatable synthetic-week acceptance fixture covering shifts, training, a match, approved workouts, a deadline, food coverage, household routines, late wake-up, missed start, pain, and a fixed-schedule change;
- XCTest coverage for planning/replanning constraints, command fixtures, mutation application, confirmation gates, notification recalculation, lateness boundaries, execution history, weekly aggregation, capture state, persistence failures, core models, and the SwiftData adapter.

No account, AI provider, or app-owned raw-audio file is required. Phase 9 is
implemented in source, and validation revision
`4efab53684c3965ba50252ba991908363e9bf9b5` passed the recorded macOS/Xcode
core tests, complete simulator tests, unsigned Debug/Release builds, and
three-profile launch smoke. This is not a production-readiness claim:
signed-device, configured-provider, comprehensive accessibility,
supported-device performance, archive/TestFlight, and full beta validation
remain open.

## Requirements

- macOS with Xcode 15 or newer to open and build the iOS project;
- iOS 17 minimum deployment target;
- no third-party packages or backend services.

The repository does not pin a single Xcode release. Use the latest stable Xcode installed in the build environment and keep source compatibility explicit when adopting newer APIs.

## Open and validate

Open `PersonalMissionControl.xcodeproj` in Xcode. The app target consumes the local `Packages/MissionControlCore` package.

Run the pure-Swift package tests:

```sh
swift test --package-path Packages/MissionControlCore
```

Build the app shell on a macOS Xcode host:

```sh
xcodebuild -project PersonalMissionControl.xcodeproj -scheme PersonalMissionControl -destination 'generic/platform=iOS Simulator' build
```

Speech, microphone, Calendar, Health sleep, and local-notification permission
paths are configured. Live Apple integration validation still requires an iOS
simulator/device on a macOS Xcode host; HealthKit, Siri phrase registration,
provisioned entitlements, and permission transitions require a signed real
device. See `docs/PHASE_8_DEVICE_VALIDATION.md`.

## Repository map

```text
PersonalMissionControl.xcodeproj/  Native iOS app project
PersonalMissionControl/App/       SwiftUI composition root and app state
PersonalMissionControl/Features/  Home, Goals, Lists, Plan, Workout, and settings UI
PersonalMissionControl/Persistence/ SwiftData repository adapter
PersonalMissionControl/Voice/     Apple Speech adapter and capture state
PersonalMissionControl/Notifications/ UserNotifications adapter
PersonalMissionControl/Platform/  EventKit, HealthKit, iCal, App Intents, Keychain, AI, and Vision adapters
PersonalMissionControlTests/      App-adapter round-trip tests
Packages/MissionControlCore/      Pure-Swift domain/execution package and tests
docs/                             Product, architecture, and phased roadmap contracts
AGENTS.md                         Repository-specific engineering instructions
```

See `docs/ROADMAP.md` before starting a new phase.
See `docs/PHASE_9_BETA_VALIDATION.md` for the Phase 9 acceptance and release
gate matrix.
