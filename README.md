# Personal Mission Control

Personal Mission Control is a native iPhone app intended to turn goals, obligations, routines, recovery needs, and changing daily input into a realistic plan. The deterministic core remains useful offline; future AI support is limited to interpreting confirmed natural-language input into proposed structured changes.

## Status

Phase 1 local vertical slice is implemented:

- framework-independent domain models, editable personal defaults, repository protocols, and deterministic timeline-selection helpers in the local core package;
- schema-versioned local SwiftData persistence with an in-memory fallback;
- a persistent seed schedule, completion/checklist interactions, and editable profile/category accents;
- Home, Goals, Lists, and Plan navigation with a central Phase 3 microphone placeholder and right-side settings menu;
- XCTest coverage for core models, seed data, repository round trips, timeline selection/progress, and the SwiftData adapter.

The full scheduling/replanning engine, voice capture, notifications, and permission-backed Apple integrations intentionally remain in later phases. SwiftData is the only Apple-framework adapter introduced in Phase 1; no account or network is required.

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

Permission-backed capabilities and device integrations are not configured in Phase 1. Normal local app signing still requires a macOS/Xcode development environment.

## Repository map

```text
PersonalMissionControl.xcodeproj/  Native iOS app project
PersonalMissionControl/App/       SwiftUI composition root and app state
PersonalMissionControl/Features/  Home, Goals, Lists, Plan, and settings UI
PersonalMissionControl/Persistence/ SwiftData repository adapter
PersonalMissionControlTests/      App-adapter round-trip tests
Packages/MissionControlCore/      Pure-Swift domain/scheduling package and tests
docs/                             Product, architecture, and phased roadmap contracts
AGENTS.md                         Repository-specific engineering instructions
```

See `docs/ROADMAP.md` before starting a new phase.
