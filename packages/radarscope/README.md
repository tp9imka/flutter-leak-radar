# radarscope

[![pub.dev](https://img.shields.io/pub/v/radarscope.svg)](https://pub.dev/packages/radarscope)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Umbrella package for the Radar observability suite. One import, one
`Radar.init` call, one unified overlay badge and dashboard — composes
[`flutter_leak_radar`](https://pub.dev/packages/flutter_leak_radar) and
[`flutter_perf_radar`](https://pub.dev/packages/flutter_perf_radar) without
duplicating any domain logic.

---

## Installation

```yaml
dependencies:
  radarscope: ^0.1.0
```

This single dependency pulls in `flutter_leak_radar`, `flutter_perf_radar`,
and `radar_trace`.

---

## Quick start

```dart
import 'package:radarscope/radarscope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Radar.init(RadarConfig.standard());
  runApp(
    Radar.overlay(child: const MyApp()),
  );
}
```

That's it. Both the memory leak detector and the performance tracer are
active in debug/profile builds and are complete no-ops in release.

### Wire the navigator observer

```dart
MaterialApp(
  navigatorObservers: [Radar.navigatorObserver],
  home: ...,
)
```

---

## Usage

### Tracing operations

```dart
// Synchronous.
final result = Radar.trace('parse_config', () => parseConfig(raw));

// Async.
final user = await Radar.traceAsync('fetch_user', () => api.getUser(id));

// Manual start/stop.
final handle = Radar.start('image_decode');
decoder.decode(bytes, onDone: () => handle.stop());
```

### Tracking object lifetimes (leak detection)

```dart
class MyController {
  MyController() {
    Radar.track(this, tag: 'MyController');
  }

  void dispose() {
    Radar.markDisposed(this);
    // ... release resources
  }
}
```

### Opening the unified inspector

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const RadarScreen()),
);
```

`RadarScreen` shows a **Leaks** tab (powered by `LeakRadarView`) and a
**Performance** tab (powered by `PerfRadarView`) in a single dark-theme
scaffold.

### Custom configuration

```dart
await Radar.init(RadarConfig(
  leak: LeakRadarConfig.standard(
    autoScan: AutoScan(onNavigation: true, period: Duration(minutes: 2)),
    showOverlay: true,
  ),
  perf: PerfRadarConfig(
    enabled: kDebugMode || kProfileMode,
    showOverlay: true,
    stallThresholdMicros: 100000,
  ),
));
```

---

## Features

- **One-import story** — `import 'package:radarscope/radarscope.dart'` re-exports all
  public symbols from `flutter_leak_radar`, `flutter_perf_radar`, and the
  `radar_trace` types needed by `Radar.start()` consumers.
- **Single `Radar.init` call** — initialises both engines in parallel via
  `Future.wait`.
- **Unified overlay** — `Radar.overlay(child: ...)` renders one draggable badge
  combining leak count and perf health. Badge colour reflects the worst signal:
  green (clean), amber (jank/errors), red (critical leaks).
- **`RadarScreen`** — two-tab unified dashboard. No extra wiring needed.
- **`RadarConfig.standard()`** — opinionated defaults for both domains;
  override either independently via named arguments.
- **Zero-throw contract** — `Radar` delegates to each domain facade and never
  throws into the host app.
- **Complete no-op in release** — all calls are safe to leave in production
  code. No build flavours or conditional guards required.

---

## Related packages

| Package | Purpose |
|---|---|
| [`flutter_leak_radar`](https://pub.dev/packages/flutter_leak_radar) | On-device memory leak detector — heap growth, precise retention, overlay. |
| [`flutter_perf_radar`](https://pub.dev/packages/flutter_perf_radar) | Frame timing, jank, stall detection, rebuild counting, overlay. |
| [`radar_trace`](https://pub.dev/packages/radar_trace) | Pure-Dart tracer engine — spans, histograms, Zone nesting. |
| [`flutter_leak_radar_lint`](https://pub.dev/packages/flutter_leak_radar_lint) | Static analysis: undisposed controllers, uncancelled subscriptions. |

---

## License

MIT — see [LICENSE](LICENSE).
