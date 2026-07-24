# Personal Mission Control repository instructions

## Mission

Build a native, voice-first iPhone personal operating system that reduces the burden of deciding what to do next. Optimize for consistency, relevance, recovery, and explainable adaptation rather than filling every open minute or maximizing a single score.

## Source of truth

Read these files before changing behavior:

1. `docs/PRODUCT_SPEC.md` for product rules and editable baseline values.
2. `docs/ARCHITECTURE.md` for boundaries, data flow, persistence, and testing.
3. `docs/ROADMAP.md` for current phase scope and acceptance criteria.

The checked-in Word prompt pack is reference material. Repository Markdown is the implementation contract. When a real preference or durable product decision changes, update the relevant document in the same change set.

## Current phase

Phases 1 through 4 are present in source. Phase 2 supplies the production
deterministic seven-day planner and minimal-change replanner used by Home,
Plan, voice-command mutations, and active-execution recovery. Do not begin
Phase 5 without an explicit request.

## Architecture rules

- Keep domain types, validation, deterministic planning, and replanning in `MissionControlCore`. It must not import SwiftUI, SwiftData, EventKit, HealthKit, Speech, UserNotifications, AppIntents, or networking SDKs.
- Put Apple-framework implementations behind protocols. Domain code depends on protocols and value types, never concrete adapters.
- AI may interpret confirmed language into proposed structured mutations and concise explanations. It must not be required to plan, validate, detect conflicts, or replan.
- Keep the product local-first. Minimize and explicitly disclose any context sent to a future AI provider.
- Do not persist raw recordings by default. Never put credentials or tokens in source control.
- Model time with explicit time zones, calendar semantics, and an injectable clock. Preserve exact imported event times; generated flexible blocks may snap to five-minute boundaries.
- Freeze completed history and preserve in-progress work during replanning. Prefer stable schedules and record explainable decisions.

## Product behavior rules

- All personal baseline values are defaults, not hidden constants, and must remain editable.
- Fixed, protected, flexible, deferrable, and droppable work have distinct behavior.
- Protect sleep, meals, recovery, and genuine free time. Unexpected availability is not automatically a productivity slot.
- A protected or consequential skip may require a warning and explicit confirmation, but the user always retains final control.
- Voice actions are only proposed after transcription and are never applied until the user confirms the editable transcript and sends it.
- UI language is direct, calm, concise, and non-gamified.

## Implementation workflow

- Make scoped, reviewable changes and preserve unrelated work.
- Add deterministic unit tests before relying on UI tests for scheduling or replanning rules.
- Do not weaken constraints or silently delete behavior to make a test pass.
- Avoid third-party dependencies unless a platform framework cannot reasonably satisfy the requirement and the dependency is explicitly documented.
- Keep signing, capabilities, entitlements, accounts, and permission-dependent behavior out of source control unless represented by safe project configuration.

## Validation

Run the strongest checks supported by the current environment and report exact commands and results.

Core package:

```sh
swift test --package-path Packages/MissionControlCore
```

iOS project on macOS with Xcode:

```sh
xcodebuild -project PersonalMissionControl.xcodeproj -scheme PersonalMissionControl -destination 'generic/platform=iOS Simulator' build
```

Never claim Xcode, simulator, device, signing, permissions, or tests were validated when the environment cannot perform them. Separate implemented, compiled/tested, and device-only validation in handoff notes.
