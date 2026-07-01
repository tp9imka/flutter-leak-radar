# flutter-leak-radar

**Radar** — an on-device + DevTools **observability suite** for Flutter. While your
app runs in debug or profile mode it surfaces three domains; in release it is a
complete no-op (no overhead, no code stripping required):

- **Memory** — leak detection: objects retained after they should be freed, per-class heap growth, and retaining paths.
- **Performance** — execution traces, frame/jank timing, widget rebuild counts, and startup time.
- **Stability** — uncaught errors and main-thread stalls.

It ships both an in-app **Inspector** (a draggable overlay badge that opens a
full-screen Leaks · Performance · Stability dashboard) and a host-side **DevTools
companion** (capture → act → capture → diff heap analysis plus dense trace tables).

## Packages

| Package | Role |
|---|---|
| [`radarscope`](packages/radarscope/) | **All-in-one umbrella** — one dependency, one import (`Radar.init(...)`) for Memory + Performance + Stability, the overlay badge, and the unified Inspector |
| [`flutter_leak_radar`](packages/flutter_leak_radar/) | Memory runtime — heap sampling, precise object tracking, retaining paths, the Leaks inspector |
| [`flutter_perf_radar`](packages/flutter_perf_radar/) | Performance + Stability runtime — tracing, frame/jank timing, rebuild counts, startup, error/stall capture |
| [`flutter_leak_radar_lint`](packages/flutter_leak_radar_lint/) | Static analysis — `custom_lint` rules that catch undisposed controllers, uncancelled subscriptions, and similar patterns at edit time |
| [`flutter_leak_radar_devtools`](packages/flutter_leak_radar_devtools/) | DevTools extension — host-side heap capture list (diff any two), class histogram, retaining paths grouped by closest root, composable filters |
| [`radar_trace`](packages/radar_trace/) | Pure-Dart tracer core — spans, latency histograms, per-key stats (count / avg / p95 / total / inter-call interval) |
| [`leak_graph`](packages/leak_graph/) | Pure-Dart heap-snapshot analysis — object graph, retaining paths, snapshot diffing (no live VM required) |
| [`radar_ui`](packages/radar_ui/) | Shared design system — tokens, typography, and the dense dashboard widgets |

## Quick start

One dependency pulls in everything:

```yaml
dependencies:
  radarscope: ^0.1.0
```

```dart
import 'package:radarscope/radarscope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Radar.init(RadarConfig.standard()); // Memory + Performance + Stability
  runApp(
    Radar.overlay(
      child: MaterialApp(
        navigatorObservers: [Radar.navigatorObserver],
        home: const HomeScreen(),
      ),
    ),
  );
}
```

Tap the floating badge to open the **Inspector** (Leaks · Performance · Stability).
Long-press it for quick actions (force GC, scan now, jump to a tab).

**Want just one domain?** Depend on `flutter_leak_radar` (memory) or
`flutter_perf_radar` (performance + stability) directly — each ships its own
facade and dashboard.

## Documentation

See [`docs/`](docs/) for architecture notes, the design handoff, and platform
compatibility details.

## License

MIT — see [LICENSE](LICENSE).
