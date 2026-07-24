# CI Validation

The repository uses
[`macos-validation.yml`](../.github/workflows/macos-validation.yml) as the
macOS/Xcode gate for the stabilized Phase 1–4 source. Creating the workflow
does not make the audit green: its three gates must complete successfully on
GitHub before Phase 5 begins.

## Triggers and cost control

The workflow runs for:

- pull requests targeting `main`;
- pushes to `main`, which was also the current audit branch when the workflow
  was added;
- manual `workflow_dispatch` runs.

Pull-request and push runs use path filters. Swift source, tests, the local
package, package manifests/lockfiles, the Xcode project and shared scheme,
build configuration, entitlements, Info plists, application resources, and
workflow changes trigger validation. Documentation-only changes do not consume
macOS runner time. A manual run is always available.

Concurrency is grouped by workflow and pull request or branch. A newer run
cancels an obsolete run for the same change line.

The workflow grants the GitHub token only read access to repository contents.
It uses no repository secrets, signing identity, provisioning profile,
deployment step, or external service.

## Runner and Xcode

The job uses the pinned GitHub-hosted `macos-15` image and explicitly selects:

```text
/Applications/Xcode_16.4.app/Contents/Developer
```

This matches the project’s Xcode 16 metadata, iOS 17 deployment target, and
Swift tools 5.9 package manifest. GitHub’s current macOS 15 image inventory is
documented in the
[runner-images repository](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
The workflow fails with an installed-Xcode listing if the pinned path is no
longer present; update the pin deliberately after verifying project
compatibility.

Near the start of every run, CI prints:

```sh
sw_vers
uname -m
xcodebuild -version
swift --version
xcrun simctl list devices available
```

## Simulator selection

The workflow reads `simctl`’s JSON output and considers available iPhone
devices running iOS 17 or newer. It deterministically ranks candidates by:

1. newest installed iOS runtime;
2. newest numbered iPhone model;
3. model tier;
4. name and UDID as stable tie-breakers.

The selected UDID is passed to both Xcode gates. No specifically named iPhone
simulator is required. If no suitable simulator exists, the selector emits a
clear GitHub Actions error and the device inventory is retained with the
failure diagnostics.

## Validation gates

The three required gates and the Debug runtime smoke step are separately named
and summarized in the GitHub job summary.

### Gate 1 — Core Swift package tests

```sh
swift test --package-path Packages/MissionControlCore
```

This compiles `MissionControlCore` and executes the real
`MissionControlCoreTests` suite.

### Gate 2 — iOS simulator tests

```sh
xcodebuild \
  -project PersonalMissionControl.xcodeproj \
  -scheme PersonalMissionControl \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath DerivedData \
  -resultBundlePath TestResults/PersonalMissionControlTests.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The committed shared scheme builds the `PersonalMissionControl` application
and runs the `PersonalMissionControlTests` unit-test target. The scheme does not
skip the test target.

### Gate 3 — Unsigned Release simulator build

```sh
xcodebuild \
  -project PersonalMissionControl.xcodeproj \
  -scheme PersonalMissionControl \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath DerivedData-Release \
  -resultBundlePath TestResults/PersonalMissionControl-Release.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This validates whole-module Release compilation without code signing.

### Debug runtime and multi-size UI smoke

After the simulator XCTest step produces the Debug app, CI selects three
distinct iPhone profiles from the newest installed iOS runtime: the smallest
available profile, a common current profile, and the largest available
profile. It boots each simulator by UDID, installs a clean app container,
launches the application, waits for first render, captures a screenshot,
verifies the installed app container, terminates the app, and shuts down the
simulator.

The retained `ui-smoke-<run>-<attempt>` artifact contains `small.png`,
`common.png`, and `large.png`. These screenshots prove clean Debug launch and
first-frame rendering on representative sizes. They do not replace interactive
XCUITest, Dynamic Type, VoiceOver, notification delivery, microphone, or
physical-device validation.

The simulator test and Release gates are allowed to run even if the core gate
fails, so one CI run can expose independent failures without spending on a
second macOS job.

## Reading failures

The failing step identifies the gate:

- **Gate 1**: core compilation, dependency resolution, or core XCTest failure;
- **Simulator selection**: runner image or simulator-runtime problem;
- **Gate 2**: Xcode project, app/test compilation, test-host, or app XCTest
  failure;
- **Gate 3**: Release-only compilation or optimization failure.

Commands use `pipefail`, so piping output through `tee` cannot hide a nonzero
Swift or Xcode result. On failure, CI uploads a seven-day artifact containing
only:

- core, simulator-test, Release-build, and simulator-inventory logs;
- Debug launch/UI-smoke logs and any screenshots created before failure;
- generated `.xcresult` bundles that exist.

`DerivedData`, `.build`, app bundles, and other large generated folders are not
uploaded.

Establish the root cause before editing. Do not disable tests, suppress a real
failure, loosen product rules, or change approved behavior merely to obtain a
green workflow.

## Windows and local validation

Windows development can validate repository structure, YAML structure, text
formatting, project/scheme references, test inventory, conflict markers, and
`git diff --check`.

Windows cannot validate:

- the Swift package compiler or XCTest runtime when Swift is unavailable;
- Xcode project compilation;
- iOS simulator tests;
- Release compilation with the Apple SDK.

GitHub Actions supplies those missing macOS/Xcode checks. A workflow definition
is not evidence that any gate passed; use the actual Actions run and its job
summary.

## Physical iPhone validation

CI does not replace device testing for:

- microphone and Speech permission transitions and live capture;
- on-device speech recognition and system fallback behavior;
- local-notification delivery, actions, and cold-launch routing;
- persistence upgrades from a previously installed app build;
- VoiceOver, Dynamic Type, reduced motion, and real-device layout/performance.

## Manual run

1. Open the repository’s **Actions** tab.
2. Select **macOS Validation**.
3. Choose **Run workflow**.
4. Select the branch containing the workflow.
5. Inspect all three gate outcomes and any uploaded failure artifact.

Update the Phase 1–4 audit documents with CI results only after the GitHub
Actions run has genuinely completed.
