# Personal Mission Control

Personal Mission Control is a native iPhone app intended to turn goals, obligations, routines, recovery needs, and changing daily input into a realistic plan. The deterministic core remains useful offline; future AI support is limited to interpreting confirmed natural-language input into proposed structured changes.

## Status

Phases 1 through 4 are implemented in source:

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
- XCTest coverage for planning/replanning constraints, command fixtures, mutation application, confirmation gates, notification recalculation, lateness boundaries, execution history, weekly aggregation, capture state, persistence failures, core models, and the SwiftData adapter.

EventKit, HealthKit, App Intents, AI providers, and later-phase management
surfaces remain future work. No account, AI provider, or app-owned raw-audio
file is required.

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

Speech, microphone, and local-notification permission paths are configured.
Live capture and notification action behavior still require an iOS
simulator/device on a macOS Xcode host; normal local app signing requires the
same environment.

## Repository map

```text
PersonalMissionControl.xcodeproj/  Native iOS app project
PersonalMissionControl/App/       SwiftUI composition root and app state
PersonalMissionControl/Features/  Home, Goals, Lists, Plan, and settings UI
PersonalMissionControl/Persistence/ SwiftData repository adapter
PersonalMissionControl/Voice/     Apple Speech adapter and capture state
PersonalMissionControl/Notifications/ UserNotifications adapter
PersonalMissionControlTests/      App-adapter round-trip tests
Packages/MissionControlCore/      Pure-Swift domain/execution package and tests
docs/                             Product, architecture, and phased roadmap contracts
AGENTS.md                         Repository-specific engineering instructions
```

See `docs/ROADMAP.md` before starting a new phase.
