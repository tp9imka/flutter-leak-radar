# Flutter Leak Radar → Performance + Stability: Tracer Framework Plan

> Status: **DRAFT BLUEPRINT — review before any implementation.**
> Author context: extends `flutter_leak_radar` (runtime + `leak_graph` + lint) into a
> performance & stability product, anchored on a scalable tracer framework.
> Scope of this doc: vision, tracer design, dashboard, what to borrow/avoid, architecture,
> phased roadmap, risks, open questions. **No code.**

---

## 0. TL;DR (read this first)

We turn Leak Radar from a *memory-leak detector* into an **on-device application
observability kit** for Flutter, with three pillars: **Memory** (exists today),
**Performance** (frame timing, startup, rebuilds, traced execution time), and
**Stability** (uncaught errors, jank-storms, slow-async, ANR-like main-thread stalls).

The new center of gravity is a **Tracer**: a first-class, low-overhead, **lossless-by-design**
span framework with the ergonomics of the user's prior `trace('label', () async {…})`
(proven at 207 call sites) but with a *real* data model underneath — monotonic
microsecond timing, **streaming percentile histograms** (not mean-only), **nestable
parent/child spans** with Zone-based async context propagation, time-windowed buckets,
and an export path that a **host-side companion / DevTools extension** can ingest.

It ships as a **new sibling package `flutter_perf_radar`** in the existing melos/pub
workspace, sharing the runtime's hard-won infrastructure: the `kEngineEnabled`
compile-out gate, the `runSafely` "never throw into the host" discipline, the
`VmHeapProbe` VM-service connection machinery and the `NativeRuntime` no-VM-service
snapshot path, the immutable config pattern, and the draggable-overlay + self-contained
inspector shell. A thin umbrella package `radar` re-exports both for one-import setup
and a **single shared dashboard**.

The **single most important design stance**, learned from all three prior attempts and
from `flutter_performance_optimizer`: **keep the ergonomic instrumentation surface,
throw away the flat/lossy/mean-only/async-only/wall-clock data model, and never fake
data** (no `(buildTime/16.6)*100` "CPU%"). Every number on the dashboard must be
truthfully computed or read as "not measured."

---

## 1. Vision & Scope

### 1.1 What "Performance + Stability" means here

We deliberately bound the product. It is an **in-app + host-companion** kit for
**debug/profile builds** (release = total no-op, same as today). It does **not** try to
be APM/RUM (no production telemetry pipeline, no backend) — it is a *developer-loop*
tool.

**Performance dimension** — four data sources, in priority order:

1. **Tracer (the anchor).** Developer-instrumented execution-time spans for functions,
   blocks, async operations, and cross-boundary work (DB, HTTP, parsing, BLoC handlers,
   navigation). This is the new flagship and the bulk of this plan.
2. **Frame timing (engine-grade, VM-service-free).** `SchedulerBinding.addTimingsCallback`
   → per-frame build vs raster vs total, jank counts, real FPS. This is the *one*
   genuinely reliable automatic signal `flutter_performance_optimizer` had, and it works
   on physical devices with zero connection problem. We adopt the pipeline and **fix the
   FPS math** (`1000/avgFrameTime`, not frame-count-per-second).
3. **Startup timing.** App-start phases via `dart:ui` `PlatformDispatcher` timings +
   `WidgetsBinding` first-frame + developer-marked startup spans (`firstFrame`,
   `firstMeaningfulPaint`-style markers the dev places). Cold/warm where detectable.
4. **Rebuild attribution.** Opt-in, scoped — a `TracedBuilder`/inspector wrapper that
   counts rebuilds *per subtree* without the package's "hand-call `trackRebuild('Name')`
   in every build()" anti-pattern. Auto-instrumentation explored later (Phase 4), never
   required.

**Stability dimension** — signals that correlate with the above:

1. **Uncaught error capture.** `FlutterError.onError` + `PlatformDispatcher.instance.onError`
   + zone error handler → bounded ring buffer of error records (type, message, truncated
   stack, timestamp, **active span context** at time of throw). This is the missing
   "what was running when it broke" that no prior attempt had.
2. **Main-thread stall / ANR-like detection.** A watchdog `Timer`/microtask heartbeat
   that flags when the event loop fails to tick within a budget (e.g. >250 ms / >700 ms /
   >5 s tiers) — a software approximation of jank-storms and ANRs, on-device, no platform
   channel required for the MVP.
3. **Slow-async & error-rate on spans.** Spans already carry success/failure + duration;
   stability surfaces "this operation has a 7% throw rate" and "p99 regressed 3×".
4. **(Later) Crash/native signals** via platform channels — explicitly out of MVP.

### 1.2 How it sits alongside the leak detector (one product)

Leak Radar's runtime is already structured exactly the way an observability kit needs:
a compile gate, a never-throw facade, a connection-resilient VM probe, an on-device
snapshot fallback, an immutable config, a reactive overlay, and a self-contained
inspector. We do **not** rebuild any of that — we **generalize the shell** and add a
performance/stability *core* beside the leak *core*.

The end-state is **one product, three pillars, one dashboard**:

```
                ┌─────────────────────────────────────────────┐
                │              Radar (umbrella)                │
                │   one init, one overlay, one inspector       │
                └───────────────┬─────────────────────────────┘
            ┌───────────────────┼────────────────────────────┐
            ▼                   ▼                            ▼
   flutter_leak_radar    flutter_perf_radar          radar_dashboard
   (Memory pillar,       (Performance + Stability,    (shared UI: overlay,
    exists today)         NEW)                         tabs, charts, export)
            │                   │                            │
            └─── shared infra ──┴───── radar_core ───────────┘
                 (kEngineEnabled gate, runSafely, VM-service
                  connection unit, NativeRuntime snapshot,
                  config base, host-export transport)
```

The overlay badge becomes **multi-pillar**: today it shows "N leaks"; it gains a perf
state ("p95 ↑", "jank", "stall") and a stability state ("1 error"). Tapping opens the
shared inspector with **Memory / Performance / Stability** tabs (Leak Radar's existing
`LeakRadarScreen` becomes the Memory tab).

---

## 2. The Tracer Framework Design

This is the heart of the work. The brief: *ergonomic API to measure execution time of
functions/blocks; rich statistics; scalable and detailed without losing data points;
far better than the two prior raw attempts.* Below is the opinionated design.

### 2.1 Developer API (the façade)

Keep the **proven one-call ergonomic** (katim's `trace(...)` scaled to 207 sites; x4's
`measure/measureAsync/start+stop` trio was adopted cleanly in `dao_base.dart`). Fix
their gaps: **sync + async + manual-span**, all with `try/finally` so a throw still
records duration *and* marks failure.

Primary surface (illustrative — names to be finalized in design phase):

```dart
// 1. Sync block — zero-cost when disabled (returns body() directly, no allocation).
final parsed = Trace.sync('parse.message', () => decode(bytes));

// 2. Async block — the workhorse. Records even if the future throws.
final rooms = await Trace.async('db.query.rooms', () async => db.query(...));

// 3. Manual span across boundaries (request start → response handler).
final span = Trace.start('http.sendMessage');
... ;
span.end();                 // or span.fail(error) on the error path

// 4. Child spans — automatic nesting via the active Zone (see 2.3).
await Trace.async('room.send', () async {
  await Trace.async('crypto.encrypt', () async => encrypt(...)); // child of room.send
  await Trace.async('http.put',      () async => put(...));      // sibling child
});

// 5. Attributes (typed, bounded, PII-aware — NOT raw arg strings, see 2.5).
final span = Trace.start('image.decode', attrs: {'bytes': len, 'fmt': 'webp'});

// 6. Counters / gauges alongside spans (for rates, queue depths).
Trace.count('cache.miss');
Trace.gauge('queue.depth', pending);

// 7. Widget-scoped wrapper (opt-in, replaces the "trackRebuild in build()" smell).
TracedBuilder(name: 'ChatList', child: ...); // counts rebuilds for THIS subtree
```

**Design rules for the façade:**

- **One name per concern, not a zoo.** `Trace.sync` / `Trace.async` / `Trace.start`.
  No 1:1 copy of katim's async-only `trace` (its biggest coverage gap) and no x4's
  unconditional `Log.d` side-effect on the hot path.
- **Names are structured, not free-typed strings.** Support a dotted hierarchy
  (`db.query.rooms`) so the dashboard can roll up by prefix, and offer an optional
  **typed key registry** (`const TraceKeys.dbQueryRooms`) to kill the "207 hand-typed
  strings, typo-prone, no autocomplete" problem both priors had. Free strings still
  work for quick instrumentation; the registry is the scalable path.
- **Release no-op + disabled fast-path.** `const kPerfEnabled = kDebugMode || kProfileMode`
  (mirror of `kEngineEnabled`). When disabled, `Trace.async` returns the raw future,
  `Trace.sync` returns `body()` — **no Stopwatch, no map lookup, no allocation**
  (katim's and x4's good instinct; keep it).
- **Sampling.** A configurable head-based sample rate per key-prefix for ultra-hot paths
  (default 1.0). Sampling decisions are recorded so percentiles can be **scaled/corrected**
  and the dashboard shows "sampled at X%" — never silently lossy.

### 2.2 Data model — spans, not flat keys

The redesign that separates this from both priors (which stored *one flat aggregate per
key* and discarded ordering/causality):

**`Span`** (the atomic record):
- `id`, `parentId` (nullable), `traceId` (root id) — enables a real tree / flame chart.
- `name` (structured), `category` (db/http/ui/compute/custom).
- `startMicros`, `endMicros` from a **monotonic `Stopwatch`** (NOT `DateTime.now()` —
  both priors used wall-clock; NTP/suspend skew can produce negative durations).
- `status` = ok | error | cancelled; `error` ref when failed.
- `attrs` (bounded, typed, scrubbed).
- `sampled` flag + sample weight.

**Two storage tiers** (the "lossless without unbounded memory" answer):

1. **Streaming aggregate per (name, window)** — the always-on, O(1)-per-event,
   bounded-memory tier. For each key we keep a **fixed-bucket latency histogram**
   (log-linear buckets, HdrHistogram-style, or a t-digest) giving **min / p50 / p90 /
   p95 / p99 / max / count / sum / error-count** with *no per-sample retention and no
   loss of distributional shape*. This directly fixes the "**mean-only, tail hidden**"
   flaw that contradicted the priors' own "rich statistics" goal. Plus the two
   *differentiated* metrics worth keeping from katim: **inter-call distance** (gap
   between calls of a key → finds chatty/N+1 hot paths) and **duplicate-signature
   count** (redundant identical work).

2. **Bounded full-fidelity span ring for outliers + recent trace trees** — the "don't
   lose the interesting data points" tier. We retain *complete* spans (with parent/child
   tree) for: (a) the last *N* slow outliers per key (threshold *and* relative-to-p95,
   so a chronic-just-under-threshold call is still caught — katim only had a fixed
   threshold), (b) the last *M* full traces for flame-chart drill-down, (c) every trace
   that contained an error. Everything else collapses into the histogram. This is how we
   are **lossless about what matters** while staying memory-bounded.

**Time-windowing** (neither prior had it): aggregates are kept per rolling time bucket
(e.g. 60 × 1 s, then 60 × 1 min) so the dashboard can answer **"when did p99 regress"**
and show **time-series**, not just one lifetime number. Old buckets fold down or evict.

### 2.3 Async context & nesting (the biggest conceptual gap in both priors)

Both prior tracers were **flat**: each trace an isolated key, no parent/child, no
correlation across `await` hops. A real tracer needs causal trees. Approach:

- **Zone-based active-span propagation.** `Trace.async`/`Trace.start` push the new span's
  id into a `Zone` value; child traces read the current zone's active span as their
  `parentId`. This survives `await` boundaries within the same logical flow and keeps
  *parallel* futures correctly attributed instead of katim's "concurrent calls blend
  into one bucket."
- **Explicit `Span` handles** for cases that cross zones (e.g. a request that starts in
  one handler and completes in a socket callback) — the manual `start()/end()` form
  carries the id explicitly.
- **Isolate-aware.** Both priors used global singletons with no isolate awareness. The
  tracer is **scoped to a `Tracer` instance** (with a default ambient one), so background
  isolates get their own collector; an optional merge-on-export combines them. This kills
  the "global mutable singleton, not isolate-safe, silent key collisions" smell.

### 2.4 Low-overhead & lossless — how we keep both

- **Monotonic microsecond timing** via `Stopwatch` (not `DateTime`): correct, sub-ms,
  skew-proof.
- **Allocation discipline on the hot path.** Preallocated buffers, integer micros, no
  per-event `DateTime`, no per-event logging (x4's per-call `Log.d` and katim's per-frame
  `DateTime.now()` were measurable debug overhead). Logging/printing is opt-in & sampled.
- **O(1) per event** aggregation into the histogram; outlier/tree retention is bounded
  ring buffers with O(1) eviction (not x4's `removeAt(0)` O(n) array shift).
- **Lossless where it counts:** histograms preserve the *distribution* (so no percentile
  is wrong), and full spans are retained for outliers/errors/recent-traces. We never
  claim full per-call retention (that's unbounded) — we claim **no loss of statistical
  fidelity and no loss of the diagnostically interesting calls**, which is the honest,
  achievable form of "without losing data points/observability."

### 2.5 Privacy / safety of attributes

Both priors stuffed raw `args` strings (URLs, user data) into memory and exports — a PII
footgun flagged in the findings. Rules:

- Attributes are **typed key/value with a bounded count and value length**.
- A **scrubber** redacts known-sensitive keys and long strings by default; opt-in raw
  capture only behind an explicit flag.
- Exports inherit the scrubbing. The host companion never receives unscrubbed values
  unless the dev opts in.

### 2.6 Integration with `dart:developer` Timeline / VM service / snapshot infra

This is where we connect to the existing engine-grade tooling instead of reinventing:

- **`dart:developer` Timeline mirroring (no VM-service connection needed).** Every span
  also emits a `TimelineTask` begin/end (gated, sampled). Benefit: the spans show up in
  **Flutter DevTools' Performance/Timeline view and `flutter run --profile` traces for
  free**, on physical devices, with **no in-app self-connection** — sidestepping the
  exact reliability problem the leak side fights. This is the single highest-leverage
  integration: our tracer becomes visible in first-party tooling at near-zero cost.
- **VM-service path (reuse, don't rebuild).** When a VM-service connection *is* available
  (desktop, emulator, or via the host companion in §3/§5), we enrich: pull
  `getVMTimeline` to correlate our app spans with engine/GC/raster events, and read CPU
  samples. We **reuse `VmHeapProbe`'s connection machinery** (URI discovery via
  `Service.getInfo`/`controlWebServer`, the 30 s reconnect back-off, the
  "log-once-on-failure, never throw" discipline, `VmConnectable.reconnect()`). We extract
  that connection logic into a shared `radar_core` `VmServiceConnection` so both Memory
  and Performance ride the same resilient, single-owner socket — and the in-app
  self-connection unreliability is handled identically (degrade gracefully, prefer the
  Timeline/host-companion paths).
- **Snapshot infra reuse.** Stability correlation can attach the `NativeRuntime`
  heap-snapshot path (already in `heap_snapshot_file.dart`) to an error/stall event for
  post-hoc memory inspection — "what did the heap look like when the stall happened" —
  again with **no VM-service connection required**.
- **Honest degradation.** If neither Timeline nor VM service is reachable, the tracer is
  *fully functional* on pure in-process timing (the property all three priors had and the
  reason they were reliable). VM/Timeline enrichment is strictly additive.

---

## 3. Dashboard & Observability

One dashboard, surfaced two ways: **in-app overlay/inspector** (works everywhere, the
reliable default) and a **host-side DevTools companion** (richer, when connected). Export
bridges them.

### 3.1 Statistics to show (per key & per category)

- **Latency distribution:** p50 / p90 / p95 / p99 / max / min, count, total time, **error
  rate** — NOT mean-only (the cardinal flaw to avoid). A sparkline of the histogram.
- **Time-series:** p95/p99 and call-rate over the rolling windows → "when did it regress."
- **Hot paths:** sorted slowest-first (keep x4/katim's good default) *and* by total time
  (a fast-but-frequent call can dominate), plus the **inter-call-distance** and
  **duplicate-count** columns (the differentiated katim metrics).
- **Flame chart / trace tree:** for retained full traces — the thing *no* prior attempt
  could render because they discarded causality. Tap an outlier → see its span tree with
  per-child durations.
- **Frames panel:** FPS (correctly computed), build vs raster split, jank timeline strip
  (adopt `flutter_performance_optimizer`'s `addTimingsCallback` pipeline + CustomPainter
  strip).
- **Startup panel:** phase breakdown + first-frame time.
- **Stability panel:** error list (with the active-span context at throw), stall/ANR
  events with durations, error-rate trends.
- **Headline score (borrow the *pattern*, not the weights):** a single explainable
  0–100 / letter grade from bucketed dimensions — good dashboard ergonomics and
  marketing — but **configurable** and **never derived from faked inputs**.

### 3.2 In-app surfaces

- **Overlay badge** (extend the existing draggable `LeakRadarOverlay` pill): live
  multi-pillar pill — e.g. `⣿ 60fps · p95 42ms · 1 err`. Reuse its `BackdropFilter`
  blur + pulse animation + self-contained `MaterialApp` inspector pattern verbatim.
- **Inspector** (extend the existing self-contained inspector): add **Performance** and
  **Stability** tabs beside the current Memory view. Reuse the theme tokens
  (`LeakRadarColors`, the JetBrainsMono/SpaceGrotesk fonts already bundled), the
  sortable/filterable table pattern from katim's dashboard, and CustomPainter charts.
- **No charts-on-1s-full-recompute.** Both priors (and the package) rebuilt every row
  each tick — O(keys) churn regardless of change. The dashboard subscribes to a
  **change-stream of dirty keys** and updates incrementally.

### 3.3 Host-side DevTools companion (goal (b))

- A **DevTools extension** (real Dart source, `DartVmServiceConnection`/`serviceManager`)
  — *not* a stubbed `config.yaml + prebuilt index.html` like the package shipped. It
  consumes (1) our exported trace JSON and (2) a live VM-service connection (reliable on
  the host side, unlike in-app) for `getVMTimeline`, CPU samples, and heap snapshots.
- **Transport:** in-app tracer emits a **machine-readable JSON stream/file** (schema
  versioned). The companion ingests file exports first (MVP), then a live socket later.
  This JSON contract is also the CI artifact (§3.4).
- Why host-side wins for Performance: the host *reliably* reaches the VM service and can
  render heavy flame charts / CPU profiles without burdening the device — the in-app
  view stays light and always-available.

### 3.4 Export & CI

- **JSON export** (versioned schema) of aggregates + retained traces + frames + stability
  events — the companion and CI both ingest it. (Both priors only had ad-hoc text/CSV
  via `share_plus`; we keep share for humans, add JSON for machines.)
- **CI regression gates** (borrow `flutter_performance_optimizer`'s strongest idea):
  `PerfTestHelper` with `assertP95('db.query', under: ms)`, `assertNoJankAbove(...)`,
  `assertErrorRate('http.*', below: ...)`, `assertScore(min: ...)`, and
  `generateReport(path)`. Turns the kit into automatable performance/stability gates — a
  genuinely differentiated, marketable feature.

---

## 4. What to Borrow / What to Avoid (cited)

### 4.1 From the user's prior **katim tracer** (`katim-connect-matrix/lib/features/tracer`)

**Borrow:**
- The **one-call wrapping ergonomic** `await trace('Label', () async {…})` — proven at
  **207 organic call sites**; it *is* the baseline DX. (findings: "single most ergonomic
  thing here", criticality high)
- **Zero-overhead disabled fast-path** (`if (!enabled) return func();`). (high)
- **Streaming bounded aggregation** backbone (rolling sum + capped queue, O(1)/event). —
  but upgrade to keep distribution, not mean. (high)
- The **inter-call distance** and **duplicate-signature** metrics — genuinely
  differentiated; keep as first-class columns. (medium)
- **Slow-call ring buffer** with per-call signature/timestamp. (medium)
- The **self-contained on-device loop** (live dashboard + periodic dump + share/export),
  no host tooling required. (medium)
- **Clean layering** (UI-free measurement core) — maps to our package split. (low)

**Avoid (its documented flaws):**
- **Async-only** `trace` (no sync variant) → we add `Trace.sync`.
- **Millisecond wall-clock** `DateTime.now()` → monotonic `Stopwatch` micros.
- **Mean-only aggregates** (no p50/p95/p99/min/max) → histograms.
- **Lossy at the bin** (non-slow samples discarded; only 300 slowest kept) → histogram +
  outlier/error/recent-trace retention.
- **No time-series / no spans / no parent-child / no async-context** → windowed buckets +
  Zone-propagated span tree.
- **Global mutable singletons, not isolate-safe, hand-typed string keys** → scoped
  `Tracer` + typed key registry.
- **Raw arg strings in memory & exports (PII)** → typed, scrubbed, bounded attrs.
- **Dashboard recomputes all rows every 1 s** → incremental dirty-key updates.
- **Threshold-only slow capture** (a chronic 480 ms under a 500 ms threshold is missed) →
  relative-to-p95 outlier capture too.
- **No error/success dimension** (throws never recorded) → `try/finally` + status.
- **No machine-readable export / no host path** → versioned JSON + companion.

### 4.2 From the user's prior **x4 profiler** (`x4/packages/profiler`)

**Borrow:**
- The **three call shapes** `measure / measureAsync / start+token.stop` **with
  `try/finally`** so duration records even on throw — a correctness win to keep. (high)
- **Per-tag map + slowest-first snapshot** as the zero-config default. (medium)
- **Bounded-memory sampling intent** — keep the bounding, redo the mechanism. (high)
- **Collection/presentation split** (Profiler vs ProfilerScreen) → same as our
  core/dashboard split. (medium)

**Avoid:**
- **Wall-clock `DateTime.microsecondsSinceEpoch`** → `Stopwatch`.
- **Aggregates-only, no timeline/causality** → span tree.
- **`_samples.removeAt(0)` O(n) shift + biased recent-only p95, no p50/p99/min/max** →
  histogram.
- **p95 recomputed by copy+sort on every read** → streaming quantiles.
- **No Zone/async context** (concurrent same-tag calls blend) → Zone propagation.
- **Unconditional per-call `Log.d`** coupling + hot-path cost → opt-in/sampled.
- **No enable/disable, no sampling, no release no-op** → compile-out gate + sampling.
- **No export/persistence** → JSON export + persisted settings.
- **Dead `initProfilerPackage()` placeholder** → no speculative API (YAGNI).

### 4.3 From the pub package **`flutter_performance_optimizer` v1.0.2**

**Borrow:**
- The **`SchedulerBinding.addTimingsCallback` frame pipeline** (build/raster/total, jank,
  ring buffer, bucketed history) — the one engine-grade, VM-service-free, on-device
  signal. **Fix the FPS calc** to `1000/avgFrameTime`. (high)
- The **singleton-tracker + central warning-bus + metrics-façade + composite-score**
  scaffolding as the *shape* for adding a perf dimension beside leaks. (high, but adapt)
- The **dashboard UX kit**: draggable/collapsible glass overlay → live pill, tabbed
  panels, CustomPainter charts (gauge/timeline/line). (medium — we already have most of
  this in `LeakRadarOverlay`; cherry-pick the chart painters)
- The **CI assertion helpers + JSON report export** pattern. (medium)
- The **bucketed weighted 0–100 + letter-grade** pattern — borrow the pattern, redesign
  weights, make configurable. (low)

**Avoid (cautionary — what NOT to do):**
- **Fake profiling:** `(buildTime/16.6)*100` as "CPU%", `Service.controlWebServer(enable:true)`
  called but never connected, README claiming "VM profiling" that doesn't exist. **Never
  fake a number** — honest-degradation rule: truthfully computed or "not measured."
- **Mostly-manual string-keyed instrumentation** dressed as "automatic" → our auto signals
  are genuinely automatic (frames, errors, stalls); manual spans are honestly manual.
- **RSS-trend 7-of-9 heuristic leak detection** — strictly weaker than our existing
  precise/heap-growth/retaining-path; **borrow nothing for the leak side.**
- **Stub DevTools extension** (config.yaml + prebuilt html, no source) → we build a real
  extension with `serviceManager`.
- **Hard `google_generative_ai` dependency** sending metrics to Gemini in a
  "works-locally" package → no mandatory network/LLM dep; any AI suggestions are optional
  & offline-first.
- **`Element.visitChildren` full-tree recursion every 3 s from root** (O(N) on platform
  thread) → scoped, opt-in subtree instrumentation only.
- **Process-local singletons, nothing streams off-device** → host transport from day one.

### 4.4 From the existing **`flutter_leak_radar` runtime** (reuse, don't re-derive)

- `kEngineEnabled` compile gate (`util/build_mode.dart`) → `radar_core`.
- `runSafely`/`runSafelyAsync` "never throw into the host" discipline (`util/safe.dart`)
  wrapping every public tracer call.
- `VmHeapProbe`'s connection lifecycle (URI discovery, 30 s back-off, log-once,
  `VmConnectable`) → extracted shared `VmServiceConnection`.
- `writeHeapSnapshotFile` (`NativeRuntime`, no VM service) → stability/heap correlation.
- Immutable `@immutable final class …Config` + `copyWith` + value equality pattern.
- The static-facade + reactive `ValueNotifier<Config>` config-listenable pattern.
- `LeakRadarOverlay` (draggable pill, `BackdropFilter`, self-contained `MaterialApp`
  inspector) + theme tokens + bundled fonts.
- Melos scripts + pub `workspace:` resolution + the docs/specs/plans convention.

---

## 5. Architecture

### 5.1 Package layout — sibling package, shared core (NOT a module, NOT a fork)

Add to the existing workspace (root `pubspec.yaml` `workspace:` + `melos.yaml`
`packages/**`):

```
packages/
  radar_core/                ← NEW. Pure-Dart, UI-free shared infra.
    build_mode (kEngineEnabled), runSafely, VmServiceConnection
    (extracted from VmHeapProbe), config base, host-export transport + JSON schema,
    streaming histogram / t-digest, ring buffers.
  flutter_leak_radar/        ← EXISTS. Depends on radar_core (migrate its util/probe).
  leak_graph/                ← EXISTS, unchanged (pure-Dart snapshot analyzer).
  flutter_perf_radar/        ← NEW. The tracer + frame/startup/rebuild + stability core,
                                + perf/stability config. Depends on radar_core.
  radar_dashboard/           ← NEW. Shared overlay + inspector + charts; consumes both
                                leak & perf cores. (Or: fold into a thin `radar` umbrella.)
  flutter_leak_radar_lint/   ← EXISTS. Later: add perf/stability lint rules
                                (e.g. "missing Trace on known-slow call", "uncancelled").
  radar/                     ← NEW umbrella. Re-exports leak + perf + dashboard; one
                                import, one init, one overlay.
```

**Why sibling-package, not a module inside `flutter_leak_radar`:**
- The tracer is **pure-Dart-able** (timing, histograms, spans) — keeping it UI-free in
  `flutter_perf_radar`/`radar_core` mirrors the existing `leak_graph` separation and lets
  the measurement core be tested without Flutter.
- Independent **versioning & adoption**: a team can take perf without leaks or vice versa.
- Clean dependency arrows (no cycles): `dashboard → {leak, perf} → radar_core`.

**Why a shared `radar_core`, not duplicated infra:** the VM-service connection, the
never-throw discipline, the compile gate, and the JSON transport are identical needs for
both pillars. Duplicating them invites drift. We **extract** them from the leak runtime
(a mechanical, well-tested refactor) so both ride one resilient socket and one gate.

### 5.2 Reuse of existing infra (concrete)

| Existing (in `flutter_leak_radar`)                | Becomes / reused as                              |
|---------------------------------------------------|--------------------------------------------------|
| `util/build_mode.dart` `kEngineEnabled`           | `radar_core` `kEngineEnabled` (perf reads it)    |
| `util/safe.dart` `runSafely*`                     | `radar_core`, wraps all tracer public calls      |
| `VmHeapProbe` connect/back-off/`VmConnectable`    | `radar_core` `VmServiceConnection` (single owner)|
| `heap_snapshot_file.dart` `NativeRuntime` writer  | reused for stability heap correlation            |
| `LeakRadarConfig` immutable+copyWith pattern      | `PerfRadarConfig`, `StabilityConfig` same shape  |
| `LeakRadar` static facade + `configListenable`    | `PerfRadar` facade + shared `Radar.init`         |
| `LeakRadarOverlay` pill + inspector shell         | shared multi-pillar overlay + tabbed inspector   |
| theme tokens + bundled fonts                      | shared dashboard theme                           |
| melos/pub workspace + docs convention             | unchanged; new packages slot in                  |

### 5.3 Release / versioning impact

- **No release-build impact:** everything behind `kEngineEnabled` tree-shakes out exactly
  like today; `Trace.*` const-folds to no-ops in release. Verify with the existing
  release-size check.
- **`flutter_leak_radar` is pre-1.0 (0.1.1):** extracting infra into `radar_core` is a
  breaking-ish internal refactor but its *public* API (the `LeakRadar` facade) stays
  source-compatible — we keep the existing exports. Bump to `0.2.0`, add a dep on
  `radar_core ^0.1.0`.
- **New packages** start at `0.1.0`, publish-gated behind the same melos `ci` script
  (`format-check && analyze && test && custom_lint`). Pub topics extend with
  `tracing`, `profiling`, `observability`.
- **Docs:** new `docs/specs/2026-…-perf-radar-tracer-design.md` (the detailed design that
  follows this plan) and per-phase plans under `docs/plans/`, matching the existing
  naming.

---

## 6. Phased Roadmap

Each phase is independently shippable and dogfoodable (port the katim 207-site app and
the x4 DB layer as the live test bed).

### Phase 0 — Spec & infra extraction (foundation)
- Write the detailed tracer **design doc** (data model, façade signatures, histogram
  choice: HdrHistogram-style fixed buckets vs t-digest — decide with a benchmark).
- Extract `radar_core` from `flutter_leak_radar` (`build_mode`, `safe`,
  `VmServiceConnection`, snapshot writer). Keep leak runtime green (its full test suite +
  melos `ci`).
- **Exit:** leak runtime passes unchanged on top of `radar_core`; empty `flutter_perf_radar`
  + `radar` skeleton wired into the workspace.

### Phase 1 — Tracer MVP (the anchor)
- `Trace.sync` / `Trace.async` / `Trace.start+end/fail` with `try/finally`, monotonic
  micros, release no-op + disabled fast-path.
- Per-key **streaming histogram** (min/p50/p90/p95/p99/max/count/sum/errors) + inter-call
  distance + duplicate count. Bounded outlier ring (threshold *and* relative-to-p95).
- Zone-based parent/child span propagation; scoped `Tracer` instance (no global
  singletons).
- Minimal in-app table (sortable, incremental updates) in the existing inspector as a new
  **Performance** tab. Persisted settings (mirror leak config pattern).
- **Exit:** port ≥50 katim/x4 call sites; p50/p95/p99 + a flat span tree visible on
  device; overhead measured (<X µs/span when enabled, 0 when disabled).

### Phase 2 — Frames, startup, stability signals
- `addTimingsCallback` frame pipeline (correct FPS) → Frames panel.
- Startup phase timing → Startup panel.
- Uncaught-error capture (`FlutterError.onError` + `PlatformDispatcher.onError` + zone)
  with active-span context → Stability panel.
- Main-thread stall/ANR-like watchdog (tiered) → stability events.
- Multi-pillar overlay badge (`60fps · p95 42ms · 1 err`).
- **Exit:** all three pillars visible in one inspector; errors carry the span context that
  was active at throw.

### Phase 3 — Export, CI gates, time-series
- Versioned **JSON export** (aggregates + retained traces + frames + stability).
- Windowed time-series (rolling buckets) → p95/p99 + rate over time.
- `PerfTestHelper` CI assertions (`assertP95`, `assertNoJankAbove`, `assertErrorRate`,
  `assertScore`, `generateReport`).
- Flame-chart / trace-tree drill-down for retained traces (the thing priors couldn't do).
- **Exit:** a CI job can fail a PR on a perf/stability regression; flame chart renders a
  real nested trace.

### Phase 4 — Host companion & DevTools extension (goal (b))
- Real **DevTools extension** (Dart source, `serviceManager`/`DartVmServiceConnection`):
  ingest exported JSON + live VM service for `getVMTimeline`, CPU samples, heap snapshots.
- `dart:developer` **Timeline mirroring** of spans (gated/sampled) → spans appear in
  DevTools Performance + `flutter run --profile` traces for free.
- Live socket transport (device → companion) on top of the file/JSON contract.
- **Exit:** host companion shows our spans correlated with engine/GC/raster timeline; works
  reliably on a physical device via the host-side connection (sidestepping in-app
  self-connection).

### Phase 5 — Richer & optional
- Auto-instrumentation experiments (navigation, route build, BLoC/Stream handler wrapping)
  — opt-in, never required.
- Perf/stability **lint rules** in `flutter_leak_radar_lint` (e.g. "known-slow call
  without a `Trace`", "uncancelled timer", "rebuild storm").
- Configurable composite **score**; optional **offline** suggestions (no mandatory
  network/LLM).
- Sampling-rate auto-tuning for ultra-hot paths.

---

## 7. Risks

- **Overhead vs fidelity tension.** Spans + histograms + Zone propagation cost more than
  katim's flat map. Mitigation: benchmark per-span cost early (Phase 1 exit gate),
  aggressive disabled fast-path, sampling on hot prefixes, integer-micros + preallocated
  buffers.
- **Zone-based context correctness.** Async context propagation is subtle (parallel
  futures, error zones, isolate boundaries). Mitigation: explicit handle form as the
  escape hatch; extensive concurrency tests; treat mis-parented spans as orphans, never
  crash.
- **Histogram choice.** Fixed-bucket HdrHistogram is simple & bounded but coarse at the
  tail; t-digest is accurate but more complex. Mitigation: benchmark both in Phase 0,
  pick one, hide behind an interface so it's swappable.
- **`radar_core` extraction destabilizing the shipped leak runtime.** Mitigation: purely
  mechanical move, full leak test suite + melos `ci` must stay green as the gate; keep
  `LeakRadar` public exports byte-identical.
- **In-app VM-service unreliability (the known pain point).** Performance does NOT depend
  on it: pure in-process timing + Timeline mirroring + host companion are the primary
  paths; VM-service enrichment is additive. This is a deliberate design hedge, not a
  hope.
- **Scope creep toward APM.** Mitigation: hard boundary — debug/profile developer-loop
  tool, no production telemetry/backend in scope.
- **DevTools-extension effort.** It's a real sub-project. Mitigation: file-based JSON
  ingestion first (no live socket), defer the extension to Phase 4, ship value in-app
  before then.
- **Dashboard performance at high key cardinality.** Mitigation: incremental dirty-key
  updates (not full recompute), virtualized lists, prefix roll-up.

---

## 8. Open Questions (for the user)

1. **Naming / brand.** Keep "Radar" family (`flutter_perf_radar`, umbrella `radar`)? Or a
   distinct tracer brand? Does the umbrella `radar` package make sense as the primary
   install, with leak/perf as opt-in deps?
2. **Histogram engine.** Preference between HdrHistogram-style fixed buckets (simpler,
   bounded, coarse tail) vs t-digest (accurate tail, heavier)? Or benchmark-and-decide in
   Phase 0?
3. **Typed key registry vs free strings.** How strongly do we push the typed
   `TraceKeys.*` registry over free strings? (Your 207 sites were free strings; the
   registry fixes typos/grouping but adds ceremony.)
4. **Sampling defaults.** Default sample rate 1.0 everywhere, or auto-sample prefixes that
   exceed a call-rate budget? Acceptable to scale percentiles by sample weight?
5. **Stability depth in MVP.** Is the software stall/ANR-like watchdog + error capture
   enough for v1, or do you want native crash/ANR via platform channels sooner (bigger
   scope, per-platform)?
6. **Host companion priority.** Is the DevTools extension a near-term must (pull Phase 4
   forward) or a later differentiator? It's the largest single sub-project.
7. **`radar_core` extraction appetite.** OK to refactor the shipped leak runtime onto a
   shared core now (cleanest), or keep perf fully separate first and converge later
   (less risk to the shipped package, some duplication)?
8. **Attribute/PII policy.** Default to aggressive scrubbing with opt-in raw capture
   (recommended), or trust the dev? (Your priors leaked raw URLs/args into exports.)
9. **Test bed.** Use the katim app (207 sites) and x4 DB layer as the dogfood targets, or
   build a synthetic high-throughput harness for the overhead/lossless claims?
10. **Score.** Do you want the single headline 0–100/letter-grade (good for
    marketing/dashboards), accepting it's a heuristic — given your stated allergy to
    plausible-but-not-truly-measured numbers?
```
