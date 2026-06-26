# radar_trace

[![pub.dev](https://img.shields.io/pub/v/radar_trace.svg)](https://pub.dev/packages/radar_trace)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Pure-Dart tracer framework with monotonic spans, log-linear latency histograms,
Zone-based async nesting, and a lossless outlier ring. No Flutter dependency —
usable in CLI tools, servers, isolates, and Flutter apps alike.

---

## Installation

```yaml
dependencies:
  radar_trace: ^0.1.0
```

---

## Usage

### Synchronous tracing

```dart
import 'package:radar_trace/radar_trace.dart';

final tracer = Tracer();

// Wrap a synchronous operation — the span is recorded automatically.
final result = tracer.trace('parse_config', () {
  return parseConfig(rawBytes);
});

// With optional category and attributes.
tracer.trace(
  'db_query',
  () => db.query(sql),
  category: 'database',
  attributes: {'table': 'users'},
);
```

### Async tracing

```dart
final data = await tracer.traceAsync('fetch_user', () async {
  return await api.getUser(id);
});
```

Zone context is propagated across `await` boundaries, so spans started
inside `traceAsync` automatically become children of the outer span.

### Manual start → SpanHandle → stop/fail

```dart
// Useful when start and stop are in different callbacks.
final handle = tracer.start('upload_file', category: 'network');
try {
  await upload(file);
  handle.stop();   // records with SpanStatus.ok
} catch (e) {
  handle.fail(e);  // records with SpanStatus.error
}
```

Forgetting to call `stop` or `fail` is safe — the span is simply not
recorded. No leak or exception occurs.

### Reading aggregated statistics

```dart
final snap = tracer.snapshot();

for (final entry in snap.stats.entries) {
  final key = entry.key;          // TraceKey(name, category)
  final stats = entry.value;      // SpanKeyStatsSnapshot

  final hist = stats.histogram;
  print('${key.name}: '
        'count=${hist.count} '
        'p50=${hist.percentile(0.5)}µs '
        'p99=${hist.percentile(0.99)}µs '
        'max=${hist.max}µs');
}

if (snap.totalDropCount > 0) {
  print('${snap.totalDropCount} spans dropped (maxKeys reached)');
}
```

### Latency histograms

`LatencyHistogram` uses a log-linear bucket scheme (single-unit buckets for
1–7 µs, then 8 linear sub-buckets per power-of-two decade up to 60 s). Every
`record` call is O(1); `percentile` is O(buckets) ≈ O(1).

```dart
final hist = LatencyHistogram();
hist.record(142);    // 142 µs
hist.record(3_800);  // 3.8 ms
hist.record(15_200); // 15.2 ms

print('p50: ${hist.percentile(0.5)} µs');
print('p99: ${hist.percentile(0.99)} µs');
print('mean: ${hist.mean?.toStringAsFixed(1)} µs');
```

Observations above 60 s are counted in `dropCount` and excluded from
aggregates — never silently lost.

### Outlier ring

`OutlierRing` keeps the N slowest spans in a fixed-capacity ring buffer.
Each completed `SpanKeyStats` maintains one automatically.

```dart
final snap = tracer.snapshot();
final stats = snap.stats.values.first;

for (final span in stats.outliers) {
  print('slow span: ${span.name} ${span.durationMicros} µs');
}
```

### TraceRecorder options

```dart
final recorder = TraceRecorder(
  enabled: true,
  sampleRate: 0.1,      // record 10% of spans — reduce overhead on hot paths
  maxKeys: 512,         // cap distinct keys tracked
  outlierCapacity: 32,  // keep the 32 slowest spans per key
);

final tracer = Tracer(recorder: recorder);
```

---

## Features

- **Zero-throw contract** — recording errors never propagate to the host;
  bodies always receive their result or exception unmodified.
- **Zone-based async nesting** — parent spans are threaded through `Zone`
  values so nested `trace`/`traceAsync` calls build a proper call tree across
  `await` boundaries without manual context passing.
- **Log-linear histograms** — ~110 fixed buckets covering 1 µs–60 s with
  ~12.5 % relative error. O(1) record and percentile.
- **Lossless outlier ring** — keeps the N slowest exemplars per key so slow
  outliers are never silently averaged away.
- **Honest drop accounting** — spans beyond `maxKeys` or observations beyond
  60 s are counted in explicit drop fields rather than silently discarded.
- **Pure Dart** — no Flutter, no platform channels. Works in isolates, CLIs,
  servers, and Flutter apps.

---

## Related packages

| Package | Purpose |
|---|---|
| [`flutter_perf_radar`](https://pub.dev/packages/flutter_perf_radar) | Flutter facade: frame timing, jank, stall detection, `TracedSubtree`, overlay badge. Wraps `radar_trace`. |
| [`radar`](https://pub.dev/packages/radar) | Umbrella: one import for both `flutter_leak_radar` + `flutter_perf_radar`. |
| [`flutter_leak_radar`](https://pub.dev/packages/flutter_leak_radar) | On-device memory leak detector — heap growth, precise retention, overlay. |

---

## License

MIT — see [LICENSE](LICENSE).
