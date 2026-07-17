## 0.1.4

- Fix: the draggable badge's quick menu "Open Performance" now opens the
  Performance tab of `RadarScreen` instead of the Leaks tab.
- Require the current attribution feature set so a `radarscope` install pulls
  package-origin attribution end to end: `flutter_leak_radar ^0.3.0`,
  `radar_trace ^0.2.0`, `radar_ui ^0.3.1` (with `flutter_perf_radar ^0.1.1`).

## 0.1.3

- `Radar.trace` / `traceAsync` / `start` now accept an optional `dedupKey`,
  forwarded to `PerfRadar` for duplicate-invocation counting. The umbrella
  facade previously dropped it, so callers going through `Radar` couldn't use
  the tracer's duplicate detection.

## 0.1.2

- Require the latest radar packages so a `radarscope` install pulls the current
  feature set: `flutter_leak_radar ^0.2.1`, `flutter_perf_radar ^0.1.1`,
  `radar_trace ^0.1.2`, `radar_ui ^0.1.1`. No API change.

## 0.1.1
- use compatibility API for sharing reports

## 0.1.0

Initial release.

Umbrella package composing `flutter_leak_radar` and `flutter_perf_radar`
behind a single import and a unified facade.

- `Radar.init(RadarConfig)` — initialises both domain engines in parallel via
  `Future.wait`. `RadarConfig.standard()` delegates to each package's own
  `.standard()` factory.
- `Radar.overlay(child:)` — wraps the widget tree with a combined draggable
  badge reflecting the worst signal across both domains (green/amber/red).
- `RadarScreen` — two-tab unified inspector (`Leaks` + `Performance`) backed
  by `LeakRadarView` and `PerfRadarView`.
- `Radar.trace` / `Radar.traceAsync` / `Radar.start` — delegate to
  `PerfRadar` span instrumentation.
- `Radar.track` / `Radar.markDisposed` — delegate to `LeakRadar` object
  lifecycle tracking.
- `Radar.navigatorObserver` — `NavigatorObserver` from `LeakRadar` for
  navigation-triggered scans.
- `Radar.dispose()` — disposes both engines safely; `init` may be called again
  afterwards.
- Full re-export of `flutter_leak_radar`, `flutter_perf_radar`, and the
  `radar_trace` types needed by `Radar.start()` consumers (`SpanHandle`,
  `TraceSnapshot`).
- Zero-throw contract: all `Radar` methods delegate to domain facades that
  never throw into the host application.
- Complete no-op in release builds — no build flavours or guards required.
