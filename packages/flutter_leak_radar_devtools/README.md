# flutter_leak_radar_devtools

A DevTools extension for `flutter_leak_radar` providing diff-centric heap and
leak analysis on the host side — reliable because it uses DevTools' existing
DDS-served VM service connection, not a self-connect from inside the app.

## How it works

`serviceManager.service` (from `package:devtools_extensions`) gives the
extension a live `VmService` that already bypasses DDS. Heap snapshots are
captured via `HeapSnapshotGraph.getSnapshot`, analysis runs in `compute()` via
`leak_graph`'s `GraphLeakAnalyzer`, and the diff is computed by `computeDiff`
(also in `leak_graph`).

## Workflow

1. Open DevTools for an app that has `flutter_leak_radar` as a dependency.
2. Switch to the **Leak Radar** tab in DevTools.
3. Press **Capture A** to take a baseline snapshot.
4. Perform the action you suspect causes a leak in the app
   (e.g., navigate into a screen and back out, several times).
5. Press **Capture B** to take the comparison snapshot.
6. Inspect the **Diff** tab: classes that grew (positive Δ instances) are ranked.
7. Inspect the **Clusters** tab: `leak_graph` clusters from snapshot B with
   representative retaining paths.

## Building the web app (required before using in DevTools)

The `extension/devtools/build/` directory must contain a `flutter build web`
output for DevTools to load the extension UI.

```bash
cd packages/flutter_leak_radar_devtools
flutter build web --release \
  --output=extension/devtools/build
```

Copy (or symlink) the build output into `packages/flutter_leak_radar/extension/
devtools/build/` so the runtime package's discovery config finds it:

```bash
cp -r packages/flutter_leak_radar_devtools/extension/devtools/build \
      packages/flutter_leak_radar/extension/devtools/
```

## Local DevTools verification (step-by-step)

1. Build the web app per the section above.
2. Run the example app in profile mode on a device or simulator:
   ```bash
   cd example
   flutter run --profile
   ```
3. Open DevTools (from VS Code, IntelliJ, or `dart devtools`).
4. Connect to the running app's VM service.
5. Look for the **Leak Radar** tab in the DevTools top navigation.
6. The **Connection** banner should show "Connected — VM: … / Isolate: …"
7. Press Capture A, exercise the app, press Capture B, inspect Diff + Clusters.

## What is verified vs needs on-device verification

**Verified (this branch):**
- `flutter analyze` passes (no issues)
- `dart test` passes for `histogram_diff_test.dart` in `leak_graph` (7 tests)
- The entire extension compiles without error
- Pure-Dart diff logic (`computeDiff`) is unit-tested with TDD

**Needs on-device DevTools verification (human required):**
- The Leak Radar tab actually appears in DevTools after `flutter build web`
- `serviceManager.service` is non-null when the extension loads
- `HeapSnapshotGraph.getSnapshot` returns real data via the host connection
- The histogram table, diff view, and clusters view render correctly
- The capture→act→capture→diff loop works end-to-end in a real session
- `compute()` does not have cross-isolate serialization issues with `VmSnapshotGraphView`
  (if it does: move snapshot bytes to a `Uint8List` message and reconstruct the
  `VmSnapshotGraphView` inside `compute()` — see §6 Q2 of the spec)

## Spec open questions resolved

See the implementation plan at
`docs/superpowers/plans/2026-06-26-companion-devtools-extension.md`.
