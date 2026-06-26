# flutter-leak-radar — Follow-ups & Roadmap

_Last refreshed: 2026-06-26._

## Where things stand

The **0.1.x milestone is shipped and published**:

- `leak_graph` **0.1.0** and `flutter_leak_radar_lint` **0.1.1** are live on pub.dev;
  `flutter_leak_radar` **0.1.1** is ready to publish (pub.dev still shows 0.0.1) via
  `./tool/publish.sh packages/flutter_leak_radar`.
- pana scores: `leak_graph` **160/160**, `flutter_leak_radar` **160/160**,
  `flutter_leak_radar_lint` **150/160** (the −10 is the custom_lint `analyzer ^8` cap — see below).
- Retaining-path detection (`leak_graph`), all **7 lint rules**, extensive on-device validation,
  the in-app dashboard/overlay, and publishing tooling (`tool/publish.sh`) are **done**. The
  June-23 list that used to live here is largely superseded.

## Next phase — research & plans (2026-06-26)

A critical review of five reference repos produced three planning docs:

- **`docs/research/2026-06-26-leak_detector-borrow-report.md`** — verdict: `leak_detector` does
  **not** fix our in-app VM-service connection (it hits the same DDS wall and ships no code fix) →
  this **endorses the host-side companion pivot**. Worth borrowing: retaining-path
  source-location enrichment (`file:line:col`), force-GC-before-judging, NavigatorObserver
  delay+serialize ergonomics, and typed VM-connection failure (stop failing silently).
- **`docs/specs/2026-06-26-companion-devtools-extension-design.md`** — a DevTools-extension
  companion for reliable host-side heap/leak analysis (histogram, retaining paths, allocation
  tracing, snapshot diffing). 9 open questions in §6.
- **`docs/plans/2026-06-26-performance-stability-tracer-plan.md`** — expand into an on-device
  observability kit (**Memory + Performance + Stability**) anchored on a lossless **Tracer**
  framework (`flutter_perf_radar` sibling package + `radar` umbrella). 10 open questions in §8.
  **PLAN ONLY** — no implementation yet, by request.

## Active tracks

1. **Companion (DevTools extension)** — design done; answer the §6 open questions, then build.
2. **Performance / tracer** — detailed plan done; **plan-only** for now (awaiting §8 scope decisions).
3. **Polish** — publish `flutter_leak_radar` 0.1.1; the small VM-connection hardening (typed
   `VmServiceStatus` + native-snapshot fallback) and source-location enrichment from the borrow
   report; review/adjust the live landing page.

## Small fast-follows (carried; re-verify validity post-0.1.x)

- **lint:** `flutter_lints` → `lints` (pure-Dart plugin); helper-method teardown false-positive;
  autofix indentation hardcoded to 4 spaces.
- **runtime:** clock injection (`LeakObjectRegistry` / `LeakAnalyzer` use real `DateTime.now()`);
  `SuspectSet.ruleFor` ignore-first precedence footgun; `_share()` re-export DRY.
- Calibrate `SuspectSet.defaults()` against a real app (e.g. katim-connect-matrix) once on-device
  validation is locked.

## Re-check later

- `flutter_leak_radar_lint` reaches **160/160** only when `custom_lint_builder` ships
  analyzer-9+ support (it currently pins `analyzer ^8.0.0`; the whole custom_lint ecosystem lags).
