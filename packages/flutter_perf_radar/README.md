# flutter_perf_radar

[![pub.dev](https://img.shields.io/pub/v/flutter_perf_radar.svg)](https://pub.dev/packages/flutter_perf_radar)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

On-device performance and stability tracer for Flutter. Measures frame timing,
detects jank, captures unhandled errors, watches for main-thread stalls, and
counts per-subtree widget rebuilds — in debug and profile builds. Complete
no-op in release — no guards, no build flavours required.

---

## Installation

```yaml
dependencies:
  flutter_perf_radar: ^0.1.0
```

---

## Quick start

### 1. Initialise in `main()`

```dart
import 'package:flutter_perf_radar/flutter_perf_radar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PerfRadar.init(PerfRadarConfig.standard());
  runApp(const MyApp());
}
```

`PerfRadarConfig.standard()` enables the engine in debug and profile builds
(`kDebugMode || kProfileMode`) with a 250 ms stall threshold.

### 2. Add the overlay badge (optional)

```dart
// In your root widget's build method:
return PerfRadar.overlay(child: const MyApp());
```

The draggable badge shows live frame count and jank count. Tap to open the
full `PerfRadarScreen` dashboard.

### 3. Instrument custom operations

```dart
// Synchronous — span is recorded automatically.
final result = PerfRadar.trace('parse_json', () => jsonDecode(raw));

// Async.
final user = await PerfRadar.traceAsync('fetch_user', () => api.getUser(id));

// Manual start/stop for callback-bounded code.
final handle = PerfRadar.start('image_decode');
decoder.decode(bytes, onDone: () => handle.stop());
```

### 4. Open the inspector screen

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const PerfRadarScreen()),
);
```

The screen shows frame stats, span statistics with histograms, stability
counters (errors + stalls), and per-key rebuild counts.

---

## Frame timing and jank

`PerfRadar` hooks into `SchedulerBinding.addTimingsCallback`. Every frame
duration is recorded. Frames longer than `jankThresholdMicros` (default
16 667 µs ≈ 60 fps) are counted as jank.

```dart
final stats = PerfRadar.frameStats;
print('frames: ${stats.frameCount}  jank: ${stats.jankCount}');
```

### Resetting the counters

Frame and jank counts, the recent-frame ring, and the build/raster/total
latency histograms all accumulate since launch. Reset them to zero to
measure a specific interval — a single screen transition, a scroll, one
network round-trip — instead of since-launch totals:

```dart
PerfRadar.resetFrameStats(); // start of the window
// ... exercise the code path you want to measure ...
final stats = PerfRadar.frameStats; // stats for just this interval
```

`PerfRadar.resetFrameStats()` clears the counters, the recent-frame ring,
and every latency histogram; `jankThresholdMicros` is left untouched and
the engine keeps running. It delegates to `FrameStats.reset()` on the
underlying accumulator.

Three ways to trigger a reset:

- **Programmatically** — `PerfRadar.resetFrameStats()` from your own code.
- **From the dashboard** — the **Frames** tab shows a reset button
  (`FramesTab.onReset`, wired by `PerfRadarView` to `resetFrameStats()`
  plus an immediate refresh) whenever it is displayed inside
  `PerfRadarScreen`.
- **Over the VM service** — the `ext.perf_radar.resetFrames` extension
  (registered alongside `ext.perf_radar.snapshot`) calls
  `PerfRadar.resetFrameStats()` and acknowledges with `{"reset": true}`,
  so DevTools or any VM service client can zero the counters remotely.

All reset paths are no-ops in release builds.

---

## Stability: errors and stall watchdog

Unhandled errors are captured via `FlutterError.onError` and
`PlatformDispatcher.instance.onError`:

```dart
final snapshot = PerfRadar.stabilitySnapshot;
print('errors: ${snapshot.errorCount}  stalls: ${snapshot.stallCount}');

for (final err in snapshot.recentErrors) {
  print('${err.timestamp}: ${err.summary}');
}
```

The stall watchdog fires a periodic heartbeat on the main isolate. When the
heartbeat is delayed by more than `stallThresholdMicros`, a `StallRecord` is
emitted and retained:

```dart
for (final stall in snapshot.recentStalls) {
  print('stall: ${stall.durationMicros} µs at ${stall.timestamp}');
}
```

---

## TracedSubtree — rebuild counting

Wrap any widget subtree to count how many times it rebuilds:

```dart
TracedSubtree(
  label: 'home_feed',
  child: const HomeFeed(),
)
```

Each rebuild increments the span counter for key `rebuild:home_feed`.
Read counts from the span snapshot:

```dart
final snap = PerfRadar.snapshot();
for (final entry in snap.stats.entries) {
  if (entry.key.name.startsWith('rebuild:')) {
    print('${entry.key.name}: ${entry.value.histogram.count} rebuilds');
  }
}
```

When `PerfRadar` is disabled, `TracedSubtree` is a transparent pass-through
with zero overhead.

---

## Configuration reference

| Field | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `kDebugMode \|\| kProfileMode` | Master switch. |
| `showOverlay` | `bool` | `false` | Whether `PerfRadar.overlay()` renders the badge. |
| `jankThresholdMicros` | `int` | `16667` | Frames longer than this are counted as jank (~60 fps). |
| `stallThresholdMicros` | `int` | `250000` | Main-thread delays longer than this are counted as stalls. |
| `maxStallsRetained` | `int` | `50` | Rolling buffer depth for stall records. |
| `maxErrorsRetained` | `int` | `100` | Rolling buffer depth for error records. |

```dart
await PerfRadar.init(PerfRadarConfig(
  enabled: kDebugMode || kProfileMode,
  showOverlay: true,
  jankThresholdMicros: 8333,  // 120 fps threshold
  stallThresholdMicros: 100000,
));
```

---

## Debug/profile-only guarantee

The engine starts only when `PerfRadarConfig.enabled` is true and the build is
not release (`kPerfEnabled` guard). In release builds every call (`init`,
`trace`, `traceAsync`, `start`, `overlay`, `frameStats`, `stabilitySnapshot`)
is a synchronous no-op returning a safe default. Nothing is conditionally
compiled — no tree-shaking or build flavours required.

---

## Features

- **Frame timing and jank detection** via `SchedulerBinding` timing callbacks.
- **Duplicate call detection** — pass an optional `dedupKey` to
  `trace`/`traceAsync`/`start`, surfaced as a "N dup" count in the trace detail.
- **Stall correlation** — tapping a stall opens a detail screen correlating its
  blocking window with the instrumented spans that overlapped it.
- **Stall watchdog** — periodic heartbeat detects main-thread freezes above a
  configurable threshold.
- **Error capture** — `FlutterError.onError` + `PlatformDispatcher.onError`
  with rolling retention.
- **Span instrumentation** — `trace` / `traceAsync` / `start` → `SpanHandle`
  backed by [`radar_trace`](https://pub.dev/packages/radar_trace) histograms
  and Zone-based async nesting.
- **TracedSubtree** — zero-overhead rebuild counter for any widget subtree.
- **`PerfRadarScreen`** — self-contained dark-theme dashboard with frame,
  span, stability, and rebuild panels.
- **Draggable overlay badge** — live frame/jank indicator without leaving the
  running app.
- **Zero-throw contract** — the engine never throws into the host app.

---

## Related packages

| Package | Purpose |
|---|---|
| [`radar_trace`](https://pub.dev/packages/radar_trace) | The underlying span/histogram engine used by this package. |
| [`radarscope`](https://pub.dev/packages/radarscope) | Umbrella: one import across Memory, Performance, and Stability. |
| [`flutter_leak_radar`](https://pub.dev/packages/flutter_leak_radar) | On-device memory leak detector — heap growth, precise retention, overlay. |

---

## License

MIT — see [LICENSE](LICENSE).
