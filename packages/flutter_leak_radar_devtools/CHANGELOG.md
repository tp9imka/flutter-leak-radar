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
