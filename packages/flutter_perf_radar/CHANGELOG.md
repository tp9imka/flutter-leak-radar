## Unreleased

- `FrameStats.reset()` / `PerfEngine.resetFrameStats()` /
  `PerfRadar.resetFrameStats()` — zero out frame/jank counters, the
  recent-frame ring, and all latency histograms so a fresh measurement
  window can be started without restarting the engine.
- `ext.perf_radar.resetFrames` — new VM service extension, registered
  alongside `ext.perf_radar.snapshot`, that calls
  `PerfRadar.resetFrameStats()` and acknowledges with `{"reset": true}`.
- `FramesTab` — new optional `onReset` callback; when provided, shows a
  small reset button in the Frames tab header. `PerfRadarView` wires this
  to `PerfRadar.resetFrameStats()` followed by an immediate refresh.

## 0.1.0

Initial release.

On-device Flutter performance and stability tracer — complete no-op in release
builds; full instrumentation in debug and profile.

- `PerfRadar.init(PerfRadarConfig)` — initialises the engine once from
  `main()`. `PerfRadarConfig.standard()` enables in debug/profile with a
  250 ms stall threshold.
- `PerfRadar.trace` / `PerfRadar.traceAsync` / `PerfRadar.start` →
  `SpanHandle` — synchronous, async, and manual span instrumentation backed by
  `radar_trace` log-linear histograms and Zone-based async nesting.
- `PerfRadar.frameStats` — `FrameStatsSnapshot` with total frame count and
  jank count (frames above `jankThresholdMicros`). Hooked via
  `SchedulerBinding.addTimingsCallback`.
- `PerfRadar.stabilitySnapshot` — `StabilitySnapshot` with error and stall
  counters plus rolling retention of recent `ErrorRecord` and `StallRecord`
  events.
- `StallWatchdog` — periodic heartbeat detects main-thread freezes above a
  configurable threshold (`stallThresholdMicros`).
- Error capture via `FlutterError.onError` and
  `PlatformDispatcher.instance.onError`.
- `TracedSubtree` — counts widget subtree rebuilds via the span system;
  transparent pass-through when disabled.
- `PerfRadarScreen` — full-screen dark-theme dashboard (Scaffold + AppBar +
  `PerfRadarView`).
- `PerfRadarOverlay` — draggable badge rendered by `PerfRadar.overlay()` when
  `showOverlay` is true.
- Zero-throw contract: the engine never throws into the host application.
