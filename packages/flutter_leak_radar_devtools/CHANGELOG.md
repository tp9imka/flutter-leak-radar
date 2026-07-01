## Unreleased

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
