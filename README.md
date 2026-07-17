# flutter-leak-radar

**Radar** — an on-device + DevTools **observability suite** for Flutter. While your
app runs in debug or profile mode it surfaces three domains; in release it is a
complete no-op (no overhead, no code stripping required):

- **Memory** — leak detection: objects retained after they should be freed, per-class heap growth, and retaining paths.
- **Performance** — execution traces, frame/jank timing, widget rebuild counts, and startup time.
- **Stability** — uncaught errors and main-thread stalls.

It ships an in-app **Inspector** (a draggable overlay badge that opens a
full-screen Leaks · Performance · Stability dashboard), a host-side **DevTools
companion** (capture → act → capture → diff heap analysis plus dense trace
tables), and — new — a standalone **Radar Desktop** app: offline heap-dump /
Perfetto-trace analysis, a live **connected mode** (attach to a running app's
Dart VM Service), and an **Android native-profiling** workflow (heapprofd
capture over `adb`, per-module still-live analysis, compare/diff, and native
symbolization).

## Packages

### Published to pub.dev

| Package | Role |
|---|---|
| [`radarscope`](packages/radarscope/) | **All-in-one umbrella** — one dependency, one import (`Radar.init(...)`) for Memory + Performance + Stability, the overlay badge, and the unified Inspector |
| [`flutter_leak_radar`](packages/flutter_leak_radar/) | Memory runtime — heap sampling, precise object tracking, retaining paths, the Leaks inspector |
| [`flutter_perf_radar`](packages/flutter_perf_radar/) | Performance + Stability runtime — tracing, frame/jank timing, rebuild counts, startup, error/stall capture |
| [`flutter_leak_radar_lint`](packages/flutter_leak_radar_lint/) | Static analysis — `custom_lint` rules that catch undisposed controllers, uncancelled subscriptions, and similar patterns at edit time |
| [`radar_trace`](packages/radar_trace/) | Pure-Dart tracer core — spans, latency histograms, per-key stats (count / avg / p95 / total / inter-call interval) |
| [`leak_graph`](packages/leak_graph/) | Pure-Dart heap-snapshot analysis — object graph, retaining paths, snapshot diffing (no live VM required) |
| [`radar_ui`](packages/radar_ui/) | Shared design system — tokens, typography, and the dense dashboard widgets |

### Internal packages & apps (not published)

| Package / app | Role |
|---|---|
| [`flutter_leak_radar_devtools`](packages/flutter_leak_radar_devtools/) | DevTools extension — host-side heap capture list (diff any two), class histogram, retaining paths grouped by closest root, composable filters |
| [`radar_workbench`](packages/radar_workbench/) | Shared portable analysis engine — snapshot models, memory/performance/stability views, and the controllers/interfaces both the DevTools extension and Radar Desktop build on |
| [`radar_native`](packages/radar_native/) | Pure-Dart native-heap model and analysis — a peer to `leak_graph` for the native (heapprofd/Perfetto) memory lane |
| [`radar_native_host`](packages/radar_native_host/) | Host-side tooling — Perfetto `trace_processor` parsing, `adb`/heapprofd capture control, and the native symbolization producer + `symbolize` CLI |
| [`radar_desktop`](packages/radar_desktop/) | **Radar Desktop** — the standalone macOS-first desktop analyzer app |

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

**Want deeper, host-side analysis?** Open the [DevTools
companion](packages/flutter_leak_radar_devtools/) alongside your running app,
or launch [Radar Desktop](packages/radar_desktop/) for offline heap-dump /
trace analysis, live connected-mode inspection, and Android native profiling.

## Radar in CI

[`radar_ci`](packages/radar_ci/) is the headless front door — no Flutter
dependency, runs anywhere the Dart VM does. It attaches to (or spawns) a real
profile-mode run of your app, samples memory into gap-aware series, and gates
the result.

```shell
# 1. Capture a run (spawn the app and attach automatically):
dart run radar_ci run --cmd "flutter run --profile -d <device>" -o run.json

# 2. Gate it — exit 3 fails the build on a real leak:
dart run radar_ci gate run.json

# 3. (optional) Render a report into a PR / step summary:
dart run radar_ci report run.json --format github
```

**Co-drive the Android native lane** in the same run — the two lanes merge on
one host-wall-clock timeline inside `run.json`:

```shell
# Sample dumpsys meminfo / /proc / fd / thread trends alongside the Dart lane:
dart run radar_ci run --cmd "flutter run --profile -d <device>" \
  --native-package com.example.app -o run.json

# Also fail on native growth (opt-in); report shows a per-column native table:
dart run radar_ci gate run.json --gate-native
```

**Exit-code contract:** `0` ok · `1` usage error · `2` tool failure
(spawn/attach, a partial run, or a gate that could not be evaluated) · `3`
**gate failed** — a tracked signal (`dart.heap.used` / `dart.external` /
`process.rss`) grew monotonically, or a NEW cluster anchored in your own code
appeared versus a `--baseline`. `insufficientData` / `noisy` / `plateau` never
fail.

**Cadence matters.** Growth is certified with radar_trace's field-proven
defaults — a 30 s settle plus a 2 min minimum assessed span over ≥ 12
post-settle samples — so give it a run longer than ~2.5 min (e.g. `--duration
5m --sample-interval 5s`). A shorter run reads `insufficientData` and certifies
nothing, honestly, rather than guessing.

This repo dogfoods its own gate: the **memory-selftest** CI job runs a hermetic
planted leak through the full pipeline on every push. Copy-and-adapt workflow
templates (main-branch baseline artifact, or two-run compare) live in
[`examples/ci/memory.yaml`](examples/ci/memory.yaml).

## Android native lane

[`radar_native_host`](packages/radar_native_host/) productizes the field-proven
Android workflow — `dumpsys meminfo` / `/proc` / fd / thread trends with
plateau-vs-monotonic verdicts — as standalone CLI verbs. Every sampler follows
the **parsed-or-unmeasured rule**: a format miss reads *not measured*, never a
fake `0`.

```shell
# 1. Sample a running app over adb (overnight-robust: gaps, reconnect, flush):
dart run radar_native_host:sample --package com.example.app \
  --interval 5s --duration 8h --out before/

# 2. Triage one session → a per-column leak-bucket verdict:
dart run radar_native_host:triage before/

# 3. Compare the before-fix and after-fix sessions, column by column:
dart run radar_native_host:triage before/ --compare after/
```

Import a session into **Radar Desktop**'s Device Monitor pane for the same
columns with charts, marks, and session-vs-session compare.

## Documentation

See [`docs/`](docs/) for architecture notes, the design handoff, and platform
compatibility details.

## License

MIT — see [LICENSE](LICENSE).
