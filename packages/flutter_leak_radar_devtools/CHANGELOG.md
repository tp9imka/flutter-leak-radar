## 0.3.0

Package-origin attribution across the memory views (aligns with `leak_graph`
0.3.0's attribution core and `radar_ui` 0.3.1's origin chips).

- The diff table and class histogram group classes by their owning (anchor)
  package: the project's own classes are pinned and expanded first, dependency
  groups and a single merged runtime group collapse to a rollup — the "which
  are MINE" view. `origin:` filter terms (`origin:project`,
  `origin:dependency`, `origin:framework`, `origin:sdk`) select by owner.
- Class rows and retaining-path hops carry an origin chip (`yours` /
  `dependency` / `framework` / `sdk`) classified against the resolved
  project-package set.
- The project-package set is resolved from the debugged app's project over the
  Dart Tooling Daemon (`DtdProjectContext`), with a manual override.

## 0.2.1

- Session state (captured snapshots, diff selection, active view) now survives
  DevTools disposing the extension iframe on tab switches — persisted to
  `.dart_tool/` via the Dart Tooling Daemon and rehydrated on relaunch, with a
  bounded history and a "restored" indicator. Degrades to in-memory when no DTD
  connection is available.
- A single selected snapshot can be compared against an empty baseline (an
  absolute "show all classes" view), not only two snapshots against each other.
- The class detail panel shows how a class's instances distribute across their
  distinct shortest retaining paths, each row expandable to the full hop chain.

## 0.2.0

### Memory companion redesign

- Capture-list model: capture any number of heap snapshots (not just A/B),
  list them, export any to JSON, and diff **any two**. New `MemoryController`
  replaces the A/B-only `DiffController`; `SnapshotBundle` gains
  `toJson`/`fromJson` for export.
- Retaining paths + root grouping: the Retaining Paths view and a new
  class-detail panel group a class's instances by their closest GC-root kind,
  separating live-tree-retained objects from leak-prone ones, and show a
  representative path for any class (powered by `leak_graph`'s
  `classRootProfiles`). Fixes the previously-empty retaining-path screen.
- Class histogram: fixed the right-edge column overflow and added
  tap-a-class → root-breakdown + retaining path in the detail panel.
- Composable filter: `class:`/`library:` terms with `&&`/`||`/`!`/parentheses
  and removable chips, replacing the plain substring search (plain queries
  still work). Applied to the histogram and diff tables.
- State retention: controllers now live on a process-wide `RadarSession`, so
  captured snapshots, the diff selection, and the active view survive DevTools
  tab switches.

### Frames

- `PerfDataController.resetFrames()` — calls the connected app's new
  `ext.perf_radar.resetFrames` VM service extension, then refreshes so
  the Frames view reflects the zeroed measurement window. Never throws;
  logs and no-ops when the extension or connection is unavailable.
- `PerfResetFramesButton` — new toolbar action button (in
  `perf_state_views.dart`) shown next to the existing refresh button;
  disabled (nullable `onReset`) when there is no live connection to
  reset.
- `FramesView` — the Frames toolbar now shows "Reset counters" next to
  "Refresh", letting users measure a specific interval on demand.
