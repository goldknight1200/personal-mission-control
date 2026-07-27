# CI Validation

The `macOS Validation` workflow is the authoritative automated gate for the
Personal Mission Control application through Phase 9. Its configuration lives
at [`.github/workflows/macos-validation.yml`](../.github/workflows/macos-validation.yml).
Phase 10 is outside this workflow's current scope.

## Triggers and toolchain

The workflow runs for:

- pushes to `main` and branches matching `stabilize/**` when application,
  package, project, workflow, or validation-document inputs change;
- pull requests targeting `main` when those inputs change;
- manual `workflow_dispatch` runs.

Validation uses GitHub's `macos-15` runner and pins
`DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer`. The first step
fails clearly if that Xcode installation is unavailable. The run records the
macOS, architecture, Xcode, Swift, and available-simulator diagnostics as logs.
The concurrency key includes the checked-out SHA, so a documentation or
workflow revision receives evidence for that exact revision instead of
silently reusing a previous run.

## Validation gates

The job runs these gates against one checked-out commit:

1. **Core Swift package tests**
   - runs
     `swift test --package-path Packages/MissionControlCore`;
   - executes the complete `MissionControlCoreTests` suite, including planning,
     command, persistence-hardening, migration, and performance smoke tests.
2. **Complete iOS simulator test suite**
   - discovers all available iPhone simulators from `simctl` JSON;
   - selects a deterministic UDID on the newest supported iOS runtime; and
   - runs the `PersonalMissionControl` shared scheme's complete test action with
     signing disabled; and
   - publishes a structured `xcresulttool` test summary so executed, passed,
     failed, and skipped counts are visible independently of the raw build log.
3. **Unsigned Debug build**
   - builds the complete application for the generic iOS Simulator destination
     in Debug configuration with `CODE_SIGNING_ALLOWED=NO`.
4. **Unsigned Release build**
   - builds the complete application for the generic iOS Simulator destination
     in Release configuration with `CODE_SIGNING_ALLOWED=NO`.
5. **Representative launch smoke**
   - starts only after the complete simulator test action and unsigned Debug
     build have succeeded;
   - installs the Debug application on three distinct small, common, and large
     iPhone simulator profiles from the newest available iOS runtime;
   - launches the application, waits for the first frame, captures a screenshot,
     verifies that the app container exists, and terminates cleanly; and
   - uploads the three screenshots for inspection of the root view, navigation
     shell, primary controls, blank-state failures, and obvious clipping;
   - bounds every `simctl` subprocess to 180 seconds so a runner device-service
     failure cannot consume the whole job indefinitely.
6. **Static repository validation**
   - runs `git diff --check` and checks the committed patch for whitespace
     errors;
   - rejects unresolved conflict markers, credential-shaped content, and
     tracked build output;
   - rejects duplicate top-level production type declarations;
   - confirms that the core package does not import Apple application
     frameworks;
   - confirms the `PersonalMissionControl` shared scheme exists;
   - resolves the Swift package and Xcode project package dependencies; and
   - asks `xcodebuild` to enumerate the real project and shared scheme, which
     exposes broken project or target references before tests.

The job summary reports each gate independently, along with the test simulator,
runtime, launch-smoke profiles, and exact revision.

## Artifacts and evidence

Every successful launch-smoke run uploads a `launch-smoke-<run>-<attempt>`
artifact containing the small, common, and large screenshots for 14 days.
Failed runs upload logs, available result bundles, and any screenshots for seven
days under `macos-validation-failure-<run>-<attempt>`.

The logs include toolchain versions, device inventory, static checks, package
tests, application tests, the structured `.xcresult` summary, Debug and Release
builds, package resolution, and launch commands. An `.xcresult` bundle is
retained on failure when Xcode produced one.

## Interpreting failures

Start with the failed gate and its uploaded log:

- **Toolchain or simulator selection:** runner-image or workflow compatibility.
- **Static validation or dependency resolution:** repository hygiene,
  architecture layering, shared-scheme, project-reference, or dependency
  defect.
- **Core tests:** deterministic domain behavior or pure-Swift compilation.
- **Application tests:** Apple-layer compilation, actor isolation, persistence,
  migration, notification behavior, or application regression.
- **Debug/Release build:** configuration-specific compiler, linker, resource,
  or project defect.
- **Launch smoke:** installation, startup, lifecycle, bundle identifier, or
  first-frame defect. Inspect all screenshots before accepting the run.

Do not skip a legitimate test, weaken an assertion, suppress a compiler error,
or reset durable user data to turn a failure green. Fix the smallest verified
root cause, push a new commit, and validate that exact revision again.

## Windows, GitHub Actions, and physical devices

Windows can inspect source and project structure, run Git hygiene and
repository-relative documentation checks, count authored tests, and review
architecture. This repository does not provide a Windows Swift/Xcode toolchain,
so Windows results are not build or XCTest evidence.

GitHub Actions supplies the macOS/Xcode toolchain and validates the pure core
package, complete simulator XCTest action, unsigned Debug and Release builds,
dependency resolution, and representative simulator launches.

A green workflow does not prove real-device behavior. Installation and upgrade,
signing entitlements, notification delivery and action buttons, microphone and
live Speech recognition, Calendar and Health authorization, Siri/App Intents,
Keychain behavior, background delivery, device restart, clock/time-zone
changes, Dynamic Type, VoiceOver, orientation, energy, battery, thermal
behavior, archive validation, and TestFlight distribution remain governed by
[`docs/testing/PHYSICAL_DEVICE_PHASE_1_TO_9_CHECKLIST.md`](testing/PHYSICAL_DEVICE_PHASE_1_TO_9_CHECKLIST.md).
Leave those items unpassed until a human records evidence from a signed build on
a physical iPhone.
