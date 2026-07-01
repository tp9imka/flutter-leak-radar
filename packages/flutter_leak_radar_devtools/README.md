# flutter_leak_radar_devtools

A DevTools extension for `flutter_leak_radar` providing heap, retaining-path,
and leak analysis on the host side — reliable because it uses DevTools'
existing DDS-served VM service connection, not a self-connect from inside the
app.

## How it works

`serviceManager.service` (from `package:devtools_extensions`) gives the
extension a live `VmService` that already bypasses DDS. Heap snapshots are
captured via `HeapSnapshotGraph.getSnapshot`, analysis runs in `compute()` via
`leak_graph`'s `GraphLeakAnalyzer`, and the diff is computed by `computeDiff`
(also in `leak_graph`).

## Workflow

The extension shows a left rail with a **Memory** section (Snapshots, Class
histogram, Retaining paths) plus **Performance** and **Stability** sections.
The Memory views are the core leak-analysis loop:

1. Open DevTools for an app that has `flutter_leak_radar` as a dependency, then
   open the **Leak Radar** tab.
2. In **Snapshots**, press **Capture** to take a heap snapshot. Capture as many
   as you like — each is added to the capture strip, where you can **export**
   any one to JSON or delete it. **Force GC** and **Clear all** are also there.
3. Exercise the app between captures (e.g. navigate into a screen and back out,
   several times) to isolate what grows.
4. Select **any two** snapshots in the strip to diff them (the older becomes
   baseline **A**, the newer becomes comparison **B**). The diff table ranks
   classes by growth (Δ instances / Δ bytes); tap a class to open its detail
   panel. When fewer than two are selected, the single-snapshot views focus the
   latest capture.
5. **Class histogram** lists every class in the focused snapshot (sortable by
   instances, bytes, or % of heap). Tap a class to see, in the detail panel, how
   its instances are retained — a breakdown by closest GC-root kind plus a
   representative retaining path.
6. **Retaining paths** groups every reachable class by the bucket of its
   dominant closest-root kind — **Leak-prone roots**, **Other roots**, and
   **Live tree** — so leak-prone objects surface above ones the widget tree
   legitimately retains. Selecting a class shows its full root breakdown and
   representative path.

### Filtering

The histogram, diff, and retaining-path tables share a composable filter:
`class:` and `library:` (alias `lib:`) terms, bare substring terms, and the
`&&` / `||` / `!` operators with parentheses (whitespace between terms is an
implicit `&&`). Each parsed term appears as a removable chip; a malformed
expression degrades to "match everything" and shows the parse error instead of
filtering.

### State retention

Controllers live on a process-wide `RadarSession`, so captured snapshots, the
diff selection, and the active rail view survive DevTools tab switches (which
otherwise dispose and rebuild the extension's Flutter tree).

### Frames counters

The **Performance ▸ Frames** view's toolbar has a **Reset counters** button
next to Refresh; it zeroes the connected app's accumulated frame statistics so
you can measure a specific interval, and is disabled when there is no live
connection.

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
7. Capture a snapshot, exercise the app, capture again, select the two to diff,
   then explore the class histogram and retaining paths.

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
- The capture list, diff table, class histogram, and retaining-paths views
  render correctly, including the class detail panel's root breakdown + path
- The capture→act→capture→diff loop works end-to-end in a real session
- `compute()` does not have cross-isolate serialization issues with `VmSnapshotGraphView`
  (if it does: move snapshot bytes to a `Uint8List` message and reconstruct the
  `VmSnapshotGraphView` inside `compute()` — see §6 Q2 of the spec)

## Spec open questions resolved

See the implementation plan at
`docs/superpowers/plans/2026-06-26-companion-devtools-extension.md`.
