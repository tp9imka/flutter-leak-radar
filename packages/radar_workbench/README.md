# radar_workbench

The shared, host-agnostic analysis engine behind the Radar suite's two
richer analysis surfaces: the [`flutter_leak_radar_devtools`
extension](../flutter_leak_radar_devtools/) and [Radar
Desktop](../radar_desktop/). It owns the heap-snapshot models, the
memory/performance/stability views, and the controllers and interfaces both
hosts build on — so behavior (diffing, filtering, force-GC, connection
handling) is implemented once and rendered by whichever shell embeds it.

## What it provides

- **Capture & snapshots** — snapshot analysis and bundling
  (`SnapshotAnalyzer`, `SnapshotBundle`), a `SnapshotSource` /
  `SnapshotExporter` abstraction so a host can supply live or offline data
  interchangeably.
- **Connections** — the `RadarConnection` interface a host implements to
  supply live-vs-disconnected state (the desktop app's `ws://` VM Service
  connection and the DevTools extension's `dtd` connection are both seams
  over this).
- **Memory** — `MemoryController`, `MemoryView`, class histograms, diff
  tables, retaining-paths view, root-kind UI, and `forceGc()`.
- **Perf** — `PerfDataController`, frames/traces views, perf snapshot DTOs.
- **Stability** — errors and stalls views.
- **Filtering** — a composable `FilterExpression` / `FilterBar` shared
  across all three domains.
- **Presentation shell** — `MainScaffold`, `LeftRail`, `ConnectionBar`,
  retaining-path tiles, and trend widgets used to assemble a full dashboard.
- **Session** — `RadarSession` and snapshot persistence/storage.

## Internal package

`radar_workbench` is **not published to pub.dev** (`publish_to: none`). It is
an internal, host-agnostic library — the DevTools extension and Radar
Desktop are its only intended embedders.

See the root [README](../../README.md) for how this fits into the wider
Radar suite.
