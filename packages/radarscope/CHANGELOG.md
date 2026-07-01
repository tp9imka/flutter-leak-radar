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
