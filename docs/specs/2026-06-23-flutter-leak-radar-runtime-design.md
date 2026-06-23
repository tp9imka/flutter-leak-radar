# flutter_leak_radar — Runtime Package Design Spec

> On-device, zero-config memory-leak detector for Flutter. Connects to the app's own VM service in debug/profile to track per-class heap growth, offers a precise `track()`/`markDisposed()` opt-in built on `WeakReference`/`Finalizer`, and surfaces findings through an in-app overlay and results screen. A complete, guaranteed no-op in release.

---

## 1. Goals / Non-goals

### Goals

- **Zero-config heap detection.** A single `LeakRadar.init(...)` call wires up a VM-service heap engine that detects classes whose live instance counts grow across captures, with no per-object instrumentation required.
- **Precise opt-in.** Function-call API (`track(obj, tag:)` / `markDisposed(obj)`) for exact "this object should be dead but isn't" detection — no mixins, no base classes, no interfaces to implement on host types.
- **On-device surface.** Draggable overlay badge + results screen with growth sparklines, lazily-fetched retaining paths, and Export/Share — usable on a physical device, not just DevTools.
- **Debug + profile support.** Full functionality wherever the VM service is reachable. The precise opt-in additionally works in profile-without-service (it needs only `dart:core` + `reachabilityBarrier`).
- **Absolute host safety.** Never throws into, crashes, or measurably slows the host app. Internal failures degrade to a no-op plus a single rate-limited debug log.
- **Complete release no-op.** All instrumentation is guarded so the tree-shaker eliminates the machinery in release builds.

### Non-goals

- Not a production telemetry / crash-reporting tool. No network egress, no background uploads.
- Not a replacement for `package:leak_tracker` or DevTools — it complements them with a device-friendly heap layer and UI. (See §3.9 for the leak_tracker decision.)
- Not a profiler. It measures instance-count growth and retention, not CPU, frame timing, or allocation rates.
- No custom GC algorithm and no native plugin code — pure Dart on top of `package:vm_service`.
- The lint package (`leak_radar_lint`) and the shared demo app are **out of scope for this spec**; this document covers the runtime package `packages/flutter_leak_radar` only.

---

## 2. Architecture

The runtime is a layered system. Only one unit (`VmHeapProbe`) imports `package:vm_service`; only the UI layer imports `share_plus`. The analysis core is pure (no I/O, no VM service, deterministic). The facade is the sole public entry point.

```text
                          ┌─────────────────────────────────────────┐
   host app  ───init()──► │            LeakRadar (facade)            │  ◄── public API
                          │  init/scan/track/markDisposed/reports/   │
                          │  status/overlay/navigatorObserver        │
                          └───────┬───────────────┬─────────────┬────┘
                                  │               │             │
                 ┌────────────────▼───┐   ┌───────▼──────┐  ┌───▼───────────────┐
                 │   _LeakEngine      │   │ LeakObject   │  │ LeakRadar         │
                 │   (orchestrator)   │   │ Registry     │  │ NavigatorObserver │
                 └───┬────────────┬───┘   │ (precise)    │  └───────────────────┘
                     │            │        └──────┬───────┘
          ┌──────────▼───┐  ┌─────▼────────┐      │ precise leaks
          │ VmHeapProbe  │  │ LeakAnalyzer │◄─────┘ folded in
          │ (vm_service) │  │ (pure)       │
          └──────────────┘  └──────┬───────┘
                                   │ uses
                          ┌────────▼─────────┐
                          │ SuspectSet +     │
                          │ LeakRule         │
                          └──────────────────┘
                                   │ produces
                          ┌────────▼─────────┐      ┌─────────────────────────┐
                          │ LeakReport /     │─────►│ LeakRadarOverlay /      │
                          │ LeakFinding      │      │ LeakRadarScreen (UI)    │
                          └──────────────────┘      └─────────────────────────┘
```

### File layout (each file < 800 lines, organized by domain)

```text
packages/flutter_leak_radar/
├── lib/
│   ├── flutter_leak_radar.dart        # SOLE public entrypoint — exports facade + public models
│   └── src/
│       ├── leak_radar.dart            # LeakRadar facade (static)
│       ├── config/
│       │   ├── leak_radar_config.dart # LeakRadarConfig, AutoScan
│       │   ├── leak_rule.dart         # LeakRule + factories
│       │   └── suspect_set.dart       # SuspectSet (+ defaults)
│       ├── engine/
│       │   ├── leak_engine.dart       # _LeakEngine orchestrator (internal)
│       │   ├── vm_heap_probe.dart     # VmHeapProbe (ONLY vm_service importer)
│       │   ├── heap_probe.dart        # HeapProbe interface + NoopHeapProbe
│       │   └── class_sample.dart      # ClassSample, HeapSnapshot (internal data)
│       ├── analysis/
│       │   ├── leak_analyzer.dart     # LeakAnalyzer (pure)
│       │   ├── sample_history.dart    # ring-buffer history of per-class samples
│       │   └── severity.dart          # severity computation
│       ├── precise/
│       │   ├── leak_object_registry.dart  # track()/markDisposed()
│       │   └── gc_support.dart            # reachabilityBarrier + pressure-GC helper
│       ├── model/
│       │   ├── leak_report.dart       # LeakReport (+ toJson/toMarkdown)
│       │   ├── leak_finding.dart      # LeakFinding
│       │   ├── retaining_path.dart    # RetainingPathView (UI-facing copy)
│       │   └── leak_kind.dart         # LeakKind enum (mirrors leak_tracker taxonomy)
│       ├── triggers/
│       │   ├── navigator_observer.dart    # LeakRadarNavigatorObserver
│       │   └── scan_scheduler.dart        # periodic timer driver
│       ├── ui/
│       │   ├── leak_radar_overlay.dart    # draggable badge
│       │   ├── leak_radar_screen.dart     # results screen
│       │   ├── growth_sparkline.dart      # CustomPainter sparkline
│       │   └── retaining_path_tile.dart   # lazy expand tile
│       └── util/
│           ├── safe.dart              # runSafely / runSafelyAsync guards
│           ├── rate_limited_logger.dart
│           └── build_mode.dart        # kEngineEnabled, service availability
├── example/                           # minimal runnable example (pub points)
└── test/
```

### 2.1 `LeakRadar` — facade

- **Responsibility.** The single public surface. Holds the singleton engine, validates and stores config, fans calls out to internals, exposes the reports stream and status. Every method is wrapped so it can never throw into the host. In release (or when disabled) every method is a cheap no-op.
- **Public surface.** `init`, `scan`, `track`, `markDisposed`, `reports` (stream), `latest` (last report), `status`, `overlay(child:)`, `navigatorObserver`, `dispose`. Full signatures in §4.
- **Dependencies.** `_LeakEngine`, `LeakObjectRegistry`, `LeakRadarNavigatorObserver`, `LeakRadarConfig`. No `vm_service`, no `share_plus`.

### 2.2 `_LeakEngine` — orchestrator (internal)

- **Responsibility.** Owns the lifecycle: chooses `VmHeapProbe` vs `NoopHeapProbe` at init based on build mode + service availability; drives capture→analyze→report cycles; merges precise-leak findings from the registry into each report; manages the `scan_scheduler` timer and debounced navigation scans; broadcasts reports.
- **Public surface (library-private).** `Future<void> start(LeakRadarConfig)`, `Future<LeakReport> scan({String? trigger})`, `Stream<LeakReport> get reports`, `LeakRadarStatus get status`, `Future<void> stop()`.
- **Dependencies.** `HeapProbe`, `LeakAnalyzer`, `SampleHistory`, `LeakObjectRegistry`, `ScanScheduler`.

### 2.3 `VmHeapProbe` — the only `vm_service` unit

- **Responsibility.** The sole place that imports `package:vm_service` / `vm_service_io` / `dart:developer`. Discovers and connects to the app's own VM service, captures per-class live-instance snapshots, resolves class names to `ClassRef`, drills to instances, and lazily fetches retaining paths. Reports `unavailable` gracefully instead of throwing.
- **Public surface (behind `HeapProbe` interface).**

```dart
abstract interface class HeapProbe {
  Future<bool> get isAvailable;
  Future<HeapSnapshot> capture({required bool forceGc});
  Future<RetainingPathView?> retainingPath(String className, {int maxInstances});
  Future<void> dispose();
}
```

- **Connection sequence (verified against leak_tracker).** Use `serverWebSocketUri` directly — **never** hand-rewrite the scheme; fall back to `Service.controlWebServer(enable: true)` (covers `flutter test` / lazy-start profile); treat a null URI after both as genuinely unavailable.

```dart
Future<Uri?> _serviceUri() async {
  var uri = (await Service.getInfo()).serverWebSocketUri; // ws:// already
  if (uri != null) return uri;
  uri = (await Service.controlWebServer(enable: true)).serverWebSocketUri;
  return uri; // null => no service (release / disabled)
}

Future<VmService?> _connect() async {
  final uri = await _serviceUri();
  if (uri == null) return null;
  final service = await vmServiceConnectUri(uri.toString());
  await service.getVersion(); // warm up + validate socket
  return service;
}
```

- **Isolate id.** Use the cheap, RPC-free `Service.getIsolateId(Isolate.current)` for the running app's main isolate. Only fall back to `getVM().isolates.first.id` if that returns null. Object ids are isolate-scoped — never reuse across isolates.
- **Capture (the aggregate signal).** `getAllocationProfile(isolateId, gc: forceGc)`. With `gc: true` a full GC runs first, so `ClassHeapStats.instancesCurrent` reflects **live/reachable** objects — exactly the "is this class leaking" signal. Build a name→`ClassRef` map from `AllocationProfile.members` (already loaded; preferred over `getClassList`). Each snapshot row → `ClassSample(className, library, instancesCurrent, bytesCurrent, timestamp)`.
- **Retaining path (lazy, expensive).** On UI expand only: `getInstances(isolateId, classRef.id, limit)` with a small `limit` (default 10) — `totalCount` gives the real count, `instances` is what you pay to materialize. Then `getRetainingPath(isolateId, targetId, 100000)` per leak_tracker (the `limit` bounds path *length*, not heap-walk cost; cost is controlled by how *few* objects you request paths for). Map `RetainingObject.parentField` defensively (typed `dynamic`, historically `String?` — handle both), `parentMapKey`, `parentListIndex`.
- **Cost discipline.** Cap retaining-path requests per cycle (`maxRetainingPathRequests`, default 5), mirroring leak_tracker's `processIfNeeded` slicing. Never fetch paths during a normal scan — only on explicit expand.
- **Error handling.** Wrap every RPC. Catch `RPCError`, `SentinelException` (object GCed between selection and the path RPC), and socket errors. A `null`/empty path is "unknown", not "not leaking". Any unrecoverable error flips the probe to `unavailable` and the engine falls back to precise-only mode.
- **Dependencies.** `package:vm_service`, `package:vm_service/vm_service_io.dart`, `dart:developer`, `dart:isolate`.

### 2.4 `SuspectSet` + `LeakRule`

- **Responsibility.** Declarative configuration of which classes are leak-prone and what thresholds apply. `SuspectSet` is a collection of `LeakRule`s with name-pattern matching (glob-style `*` prefix/suffix/contains). `LeakRule` carries the match pattern, detection mode (growth vs maxLive), threshold, and severity hint.
- **Defaults (`SuspectSet.defaults()`).** Patterns matching Flutter/Dart leak-prone types:
  - `State` / `*Screen` (widget state and screen objects)
  - `*Bloc` / `*Cubit` / `BlocBase`
  - `*Controller` / `ChangeNotifier`
  - `StreamSubscription` / `StreamController`
  - `Timer`
- **Host customization.** Hosts can `add`, `override` (replace a default rule for the same pattern), or `ignore` (suppress a class even if it matches a default). Resolution order: explicit ignore > host override > host add > defaults.
- **Public surface.** See §4.3.
- **Dependencies.** None (pure config).

### 2.5 `LeakAnalyzer` — pure analysis core

- **Responsibility.** Pure, deterministic, no-I/O. Consumes the running `SampleHistory` plus the resolved `SuspectSet` and produces a `LeakReport`. Two signals: (1) **growth** across captures (default) and (2) optional per-rule **maxLive** threshold. Computes `growth` (delta and slope across the window), classifies severity, and emits one `LeakFinding` per suspect class that trips a rule.
- **Public surface.**

```dart
class LeakAnalyzer {
  const LeakAnalyzer(this.suspects);
  final SuspectSet suspects;

  LeakReport analyze(SampleHistory history, {
    required String trigger,
    List<LeakFinding> preciseFindings = const [],
  });
}
```

- **Dependencies.** `SuspectSet`, `LeakRule`, `SampleHistory`, `LeakReport`, `LeakFinding`, `severity.dart`. No `vm_service`, no `dart:io`.

### 2.6 `SampleHistory`

- **Responsibility.** Bounded ring buffer of recent `HeapSnapshot`s (default `maxSnapshots: 20`), indexed by class name for fast per-class series extraction. Provides per-class `List<ClassSample>` sequences to the analyzer and to the sparkline. Immutable snapshots in, derived views out.
- **Dependencies.** `class_sample.dart`. Pure.

### 2.7 `LeakObjectRegistry` — precise opt-in

- **Responsibility.** Implements `track(obj, tag:)` and `markDisposed(obj)` using `WeakReference` + `Finalizer` + `reachabilityBarrier`. An object that is still alive N full GC cycles after `markDisposed` is a **precise leak** (`LeakKind.notGced`). An object finalized while never marked disposed is `LeakKind.notDisposed`. Works with no VM service (debug + profile-without-service).
- **Design (verified against leak_tracker primitives).**
  - One `Finalizer<_Entry>` shared across all tracked objects; `attach(obj, entry, detach: obj)` so tracking can be cancelled and the finalizer records `gcAtFinalize = reachabilityBarrier` on collection.
  - Each `_Entry` holds only a `WeakReference<Object>` — **never** a strong reference (must not extend object lifetime), the `tag`, `disposedGc`, `disposedAt`, `gcAtFinalize`.
  - `markDisposed` records `disposedGc = reachabilityBarrier` and `disposedAt = DateTime.now()`.
  - Leak decision mirrors leak_tracker's `shouldObjectBeGced`: `currentGc - disposedGc >= numberOfGcCycles && now - disposedAt >= disposalTime` **and** `ref.target != null` (still alive).
  - Entries whose target is gone and which were properly disposed are pruned.
- **Public surface (library-private; host calls via facade).**

```dart
class LeakObjectRegistry {
  void track(Object obj, {required String tag});
  void markDisposed(Object obj);
  Future<List<LeakFinding>> collectPreciseLeaks({int gcCycles = 3});
  int get trackedCount;
  void clear();
}
```

- **GC support (`gc_support.dart`).** Exposes `reachabilityBarrier` (from `dart:developer`) as `currentGcCount`, and a portable pressure-induced GC helper (allocate-and-drop loop awaiting `reachabilityBarrier` ticks) for the no-service path. When a VM service is present the engine prefers `getAllocationProfile(gc: true)` for a real forced GC.
- **Dependencies.** `dart:developer` (`reachabilityBarrier`), `dart:core` (`WeakReference`, `Finalizer`). No `vm_service` required.

### 2.8 `LeakRadarNavigatorObserver`

- **Responsibility.** A `NavigatorObserver` that triggers a **debounced** scan on `didPop` (default debounce 500ms; coalesces rapid back-navigation). Optional, enabled via `AutoScan(onNavigation: true)`. Forwards to `_LeakEngine.scan(trigger: 'navigation')`.
- **Public surface.** Construct via `LeakRadar.navigatorObserver` (returns a shared instance bound to the engine). It is a normal `NavigatorObserver` added to `MaterialApp.navigatorObservers`.
- **Dependencies.** `flutter/widgets.dart`, `_LeakEngine`, a debounce timer.

### 2.9 UI: `LeakRadarOverlay` + `LeakRadarScreen`

- **`LeakRadarOverlay`** — wraps the host `child` and floats a **draggable badge** showing the current worst severity / finding count. Tapping opens `LeakRadarScreen`. Hidden entirely when disabled/release. Uses an `Overlay`/`Stack` so it never participates in host layout. Badge color encodes severity (info/warning/critical).
- **`LeakRadarScreen`** — lists `LeakFinding`s sorted by severity, each row: class name, live count, growth delta, severity chip, and a **growth sparkline** (`GrowthSparkline` `CustomPainter` over the per-class series from `SampleHistory`). Expanding a row **lazily** fetches and renders the retaining path (`RetainingPathTile` → `HeapProbe.retainingPath`). Top bar has **Export** (writes file, shows path) and **Share** (via `share_plus`).
- **Dependencies.** `flutter/material.dart`; `LeakRadarScreen`/export uses `share_plus` (UI-layer dependency, isolated here so the core stays dependency-light). Reads `LeakReport`/`LeakFinding` and calls back into the facade for retaining paths and export.

---

## 3. Data flow

**Capture → analyze → report (heap engine):**

1. A trigger (manual `scan()`, periodic timer, or debounced navigation) calls `_LeakEngine.scan(trigger:)`.
2. Engine asks `HeapProbe.capture(forceGc: true)`. `VmHeapProbe` calls `getAllocationProfile(gc: true)`, maps `members` → `HeapSnapshot { List<ClassSample> }`.
3. Snapshot is pushed into `SampleHistory` (ring buffer).
4. `LeakObjectRegistry.collectPreciseLeaks()` runs (forces/observes GC, returns `notDisposed`/`notGced` findings).
5. `LeakAnalyzer.analyze(history, trigger:, preciseFindings:)` runs the `SuspectSet` rules over the history: per suspect class it computes growth across the window and checks maxLive; precise findings are folded in. Output: `LeakReport { findings, capturedAt, trigger, heapBytes }`.
6. Engine sets `latest` and broadcasts on `reports`.
7. UI (`LeakRadarOverlay` badge, `LeakRadarScreen`) listens to `reports` and rebuilds.

**Lazy retaining path (on expand only):**

`LeakRadarScreen` expand → facade → `_LeakEngine` → `VmHeapProbe.retainingPath(className)` → `getInstances(limit)` → `getRetainingPath(target, 100000)` → `RetainingPathView` → `RetainingPathTile`. Capped per cycle; bypassed in normal scans.

**Precise opt-in (independent of heap engine):**

Host calls `LeakRadar.track(obj, tag:)` at creation and `LeakRadar.markDisposed(obj)` at disposal → `LeakObjectRegistry`. On each scan, registry contributes findings even if the VM-service probe is `unavailable`.

---

## 4. Public API

All public types are exported from `lib/flutter_leak_radar.dart`. Everything under `src/` is internal. The facade is static and never throws into the host.

### 4.1 `LeakRadar` facade

```dart
/// On-device leak detector. All methods are no-ops in release or when disabled,
/// and never throw into the host app.
abstract final class LeakRadar {
  /// Initialize and (if enabled) start the engine. Idempotent: a second call
  /// with a new config restarts the engine; safe to call from main().
  /// Returns once the engine has chosen a probe and (optionally) started timers.
  static Future<void> init(LeakRadarConfig config) { /* ... */ }

  /// Run a single capture→analyze→report cycle. Returns the produced report,
  /// or a degraded report (status != active) if the service is unavailable.
  static Future<LeakReport> scan({String trigger = 'manual'}) { /* ... */ }

  /// Track [object] for precise leak detection. Holds only a WeakReference.
  /// No-op if disabled. [tag] should identify the call site (e.g. 'HomeBloc').
  static void track(Object object, {required String tag}) { /* ... */ }

  /// Mark [object] as disposed: it should now be collectible. If it survives
  /// the configured number of GC cycles it is reported as a precise leak.
  static void markDisposed(Object object) { /* ... */ }

  /// Broadcast stream of reports emitted by every scan. Never errors.
  static Stream<LeakReport> get reports { /* ... */ }

  /// The most recent report, or null if none yet.
  static LeakReport? get latest { /* ... */ }

  /// Current runtime status (see [LeakRadarStatus]).
  static LeakRadarStatus get status { /* ... */ }

  /// Wrap the app to show the draggable overlay badge. Returns [child]
  /// unchanged when disabled/release.
  static Widget overlay({required Widget child}) { /* ... */ }

  /// The shared navigator observer; add to MaterialApp.navigatorObservers.
  /// Returns an inert observer when disabled.
  static NavigatorObserver get navigatorObserver { /* ... */ }

  /// Export the latest report to a file; returns the absolute path, or null
  /// on failure / when disabled. [format] selects json or markdown.
  static Future<String?> exportToFile({LeakExportFormat format = LeakExportFormat.markdown}) { /* ... */ }

  /// Stop timers, close the VM-service connection, and release resources.
  static Future<void> dispose() { /* ... */ }
}

enum LeakRadarStatus {
  /// Not initialized, or release build / disabled by config.
  disabled,
  /// Initialized; precise opt-in active but no VM-service heap probe.
  preciseOnly,
  /// Fully active: VM-service heap probe + precise opt-in.
  active,
  /// Tried to attach a probe but the service became unavailable.
  serviceUnavailable,
}

enum LeakExportFormat { json, markdown }
```

### 4.2 `LeakRadarConfig` + `AutoScan`

```dart
/// Immutable configuration. Hand-rolled value type (==, hashCode, copyWith);
/// no freezed.
final class LeakRadarConfig {
  const LeakRadarConfig({
    this.enabled = true,
    this.autoScan = const AutoScan(),
    this.rules = const <LeakRule>[],
    this.suspects = const SuspectSet.empty(),
    this.maxSnapshots = 20,
    this.gcCyclesForPreciseLeak = 3,
    this.disposalGrace = const Duration(seconds: 2),
    this.maxRetainingPathRequests = 5,
    this.showOverlay = true,
    this.logLevel = LeakLogLevel.warning,
  });

  /// Typical wiring: enable only in debug/profile.
  factory LeakRadarConfig.standard({
    AutoScan autoScan = const AutoScan(),
    List<LeakRule> rules = const <LeakRule>[],
    SuspectSet? suspects,
  }) => LeakRadarConfig(
        enabled: kDebugMode || kProfileMode,
        autoScan: autoScan,
        rules: rules,
        suspects: suspects ?? SuspectSet.defaults(),
      );

  final bool enabled;
  final AutoScan autoScan;
  /// Host-supplied rules layered on top of [suspects] (add/override/ignore).
  final List<LeakRule> rules;
  final SuspectSet suspects;
  final int maxSnapshots;
  final int gcCyclesForPreciseLeak;
  final Duration disposalGrace;
  final int maxRetainingPathRequests;
  final bool showOverlay;
  final LeakLogLevel logLevel;

  LeakRadarConfig copyWith({ /* every field nullable */ }) { /* ... */ }
  @override bool operator ==(Object other) { /* ... */ }
  @override int get hashCode { /* ... */ }
}

/// When to scan automatically. All triggers are additive.
final class AutoScan {
  const AutoScan({
    this.onNavigation = false,
    this.period,                       // null => no periodic scan
    this.navigationDebounce = const Duration(milliseconds: 500),
  });

  final bool onNavigation;
  final Duration? period;
  final Duration navigationDebounce;

  bool get hasPeriodic => period != null;

  AutoScan copyWith({ /* ... */ }) { /* ... */ }
  @override bool operator ==(Object other) { /* ... */ }
  @override int get hashCode { /* ... */ }
}

enum LeakLogLevel { none, error, warning, verbose }
```

### 4.3 `LeakRule` + `SuspectSet`

```dart
/// How a suspect class is evaluated.
enum LeakDetectionMode {
  /// Flag when live instance count grows across the snapshot window.
  growth,
  /// Flag when live instance count exceeds [LeakRule.maxLive].
  maxLive,
  /// Never flag this class (explicit suppression).
  ignore,
}

/// A single matching rule. Immutable, hand-rolled.
final class LeakRule {
  const LeakRule._({
    required this.pattern,
    required this.mode,
    this.maxLive,
    this.minGrowth = 1,
    this.severityHint,
  });

  /// Growth-based rule (the default mode). Flags monotonic growth >= [minGrowth].
  const factory LeakRule.growth(String pattern, {int minGrowth, LeakSeverity? severityHint}) = _growth;

  /// Threshold rule: flag when live instances exceed [max].
  const factory LeakRule.maxLive(String pattern, int max, {LeakSeverity? severityHint}) = _maxLive;

  /// Suppress a class entirely (highest precedence).
  const factory LeakRule.ignore(String pattern) = _ignore;

  /// Glob-ish pattern: 'State', '*Screen', '*Bloc', '*Controller',
  /// '*Notifier', or exact name. Matched against the simple class name.
  final String pattern;
  final LeakDetectionMode mode;
  final int? maxLive;
  final int minGrowth;
  final LeakSeverity? severityHint;

  bool matches(String className);  // glob prefix/suffix/contains/exact

  @override bool operator ==(Object other) { /* ... */ }
  @override int get hashCode { /* ... */ }
}

/// An ordered, immutable collection of [LeakRule]s.
final class SuspectSet {
  const SuspectSet(this.rules);
  const SuspectSet.empty() : rules = const <LeakRule>[];

  /// Curated defaults for common Flutter/Dart leak-prone types.
  factory SuspectSet.defaults() => const SuspectSet(<LeakRule>[
        LeakRule.growth('State'),
        LeakRule.growth('*Screen'),
        LeakRule.growth('*Bloc'),
        LeakRule.growth('*Cubit'),
        LeakRule.growth('BlocBase'),
        LeakRule.growth('*Controller'),
        LeakRule.growth('ChangeNotifier'),
        LeakRule.growth('StreamSubscription'),
        LeakRule.growth('StreamController'),
        LeakRule.growth('Timer'),
      ]);

  final List<LeakRule> rules;

  /// Returns a new set with [extra] layered on top (host add/override/ignore).
  /// Precedence: ignore > later override > defaults.
  SuspectSet merge(List<LeakRule> extra);

  /// The effective rule for [className], or null if no rule applies.
  LeakRule? ruleFor(String className);

  @override bool operator ==(Object other) { /* ... */ }
  @override int get hashCode { /* ... */ }
}
```

### 4.4 Models — `LeakReport`, `LeakFinding`, `RetainingPathView`

```dart
final class LeakReport {
  const LeakReport({
    required this.findings,
    required this.capturedAt,
    required this.trigger,
    required this.status,
    this.heapBytes,
  });

  final List<LeakFinding> findings;
  final DateTime capturedAt;
  final String trigger;            // 'manual' | 'periodic' | 'navigation'
  final LeakRadarStatus status;
  final int? heapBytes;

  bool get hasLeaks => findings.isNotEmpty;
  LeakSeverity get worstSeverity;  // max over findings, or info if none

  Map<String, Object?> toJson();
  String toMarkdown();

  @override bool operator ==(Object other) { /* ... */ }
  @override int get hashCode { /* ... */ }
}

final class LeakFinding {
  const LeakFinding({
    required this.className,
    required this.kind,
    required this.severity,
    required this.liveCount,
    required this.growth,
    this.library,
    this.tag,                 // set for precise findings
    this.series = const <int>[],   // per-class live counts over the window (sparkline)
    this.retainingPath,            // null until lazily fetched
  });

  final String className;
  final LeakKind kind;            // mirrors leak_tracker taxonomy
  final LeakSeverity severity;
  final int liveCount;
  final int growth;               // delta over the window
  final String? library;
  final String? tag;
  final List<int> series;
  final RetainingPathView? retainingPath;

  LeakFinding withRetainingPath(RetainingPathView path);

  Map<String, Object?> toJson();
  @override bool operator ==(Object other) { /* ... */ }
  @override int get hashCode { /* ... */ }
}

/// UI-facing copy of a heap retaining path (decoupled from vm_service types).
final class RetainingPathView {
  const RetainingPathView({required this.gcRootType, required this.elements});
  final String? gcRootType;
  final List<RetainingHop> elements;
  Map<String, Object?> toJson();
}

final class RetainingHop {
  const RetainingHop({required this.objectType, this.field, this.index, this.mapKey});
  final String objectType;
  final String? field;     // parentField (handle dynamic/String?)
  final int? index;        // parentListIndex
  final String? mapKey;    // parentMapKey rendered
}

/// Mirrors package:leak_tracker's taxonomy for report consistency.
enum LeakKind { notDisposed, notGced, gcedLate, growth }

enum LeakSeverity { info, warning, critical }
```

### 4.5 Wiring example (host app)

```dart
void main() async {
  await LeakRadar.init(LeakRadarConfig.standard(
    autoScan: const AutoScan(onNavigation: true, period: Duration(seconds: 30)),
    rules: const [
      LeakRule.maxLive('HomeBloc', 1),
      LeakRule.ignore('TickerProviderStateMixin'),
    ],
    suspects: SuspectSet.defaults(),
  ));

  runApp(LeakRadar.overlay(child: const MyApp()));
}

// In MaterialApp:
//   navigatorObservers: [LeakRadar.navigatorObserver],

// Precise opt-in at the call site:
//   final bloc = HomeBloc(); LeakRadar.track(bloc, tag: 'HomeBloc');
//   @override void close() { LeakRadar.markDisposed(this); super.close(); }
```

---

## 5. Detection model

### 5.1 Signals

1. **Growth (default).** For each suspect class, extract its per-snapshot `instancesCurrent` series from `SampleHistory`. A class leaks when the live count grows across the window — i.e., the count after a forced GC is monotonically (or near-monotonically) above the post-warm-up baseline and does not return to baseline. The reported `growth` is `latest - windowBaseline`; the rule trips when `growth >= rule.minGrowth`. This is an **aggregate/statistical** signal (cheap, no per-object work) and is the zero-config default.

2. **maxLive (optional, per rule).** A class leaks when `liveCount > rule.maxLive`. Useful for singletons / bounded caches (e.g. `LeakRule.maxLive('HomeBloc', 1)`).

3. **Precise (opt-in).** From `LeakObjectRegistry`: `notGced` (disposed but alive after N GC cycles + grace) and `notDisposed` (finalized without `markDisposed`). These are exact, not statistical, and are folded into the same report.

> Forced GC matters: growth/maxLive are only meaningful after a real GC. With a VM service, `getAllocationProfile(gc: true)` provides it; without one (precise path only), the registry uses the pressure-induced GC helper.

### 5.2 Severity

Severity is computed per finding (host can bias via `LeakRule.severityHint`, which raises but never lowers the computed floor):

| Condition | Severity |
|---|---|
| Precise `notGced` (disposed, still alive after N GCs) | **critical** |
| Precise `notDisposed` (GCed without disposal) | **warning** |
| `maxLive` exceeded by > 2× threshold, or strict monotonic growth over the full window | **critical** |
| `maxLive` exceeded, or growth `>= minGrowth` with a clear upward slope | **warning** |
| Growth detected but noisy / within one capture of baseline | **info** |

The overlay badge color and screen sort order both key off `LeakReport.worstSeverity` and per-finding `severity`.

### 5.3 Retaining paths

Retaining paths are **never** part of the detection signal and are **never** fetched during a scan. They are explanatory, fetched lazily on UI expand, capped at `maxRetainingPathRequests` per cycle. A null/empty path renders as "retaining path unavailable" — treated as unknown, not as "not leaking". Path calls are wrapped in `try/on SentinelException` because the object may be GCed between selection and the RPC.

---

## 6. Triggers

| Trigger | Mechanism | Default | Notes |
|---|---|---|---|
| **Manual** | `LeakRadar.scan()` | always available | Returns the report; used by tests and the overlay's "scan now". |
| **Periodic** | `ScanScheduler` `Timer.periodic(AutoScan.period)` | off (`period: null`) | Each fire calls `scan(trigger: 'periodic')`. Timer is torn down in `dispose()` and never created in release. |
| **Navigation** | `LeakRadarNavigatorObserver.didPop` → debounced | off (`onNavigation: false`) | Debounced by `AutoScan.navigationDebounce` (default 500ms) to coalesce rapid back-navigation. Scans with `trigger: 'navigation'`. |

All triggers funnel through `_LeakEngine.scan` and are serialized: a scan in flight suppresses overlapping triggers (the new trigger is dropped, not queued) to avoid piling up forced GCs.

---

## 7. UI

### 7.1 `LeakRadarOverlay` (badge)

- Wraps `child`; injects a draggable badge via `Overlay`/`Stack` so it never affects host layout or hit-testing outside its own bounds.
- Badge shows worst-severity color + finding count from the latest report (listens to `LeakRadar.reports`).
- Draggable, snaps to nearest edge, position persisted in-memory for the session.
- Tap → push `LeakRadarScreen`. Long-press → "scan now".
- Returns `child` unchanged when `showOverlay == false` or status is `disabled`.

### 7.2 `LeakRadarScreen` (results)

- App bar: title, **Scan now**, **Export**, **Share**.
- Body: findings list sorted by severity then growth. Each tile:
  - Class name + library, severity chip, live count, growth delta.
  - `GrowthSparkline` (`CustomPainter`) over `LeakFinding.series`.
  - `tag` shown for precise findings; `LeakKind` chip.
  - Expansion → `RetainingPathTile`: shows a spinner, calls back into the facade for the lazy retaining path, renders `gcRootType → field → … → object`, or "unavailable".
- Empty state: "No leaks detected" + status line (active / preciseOnly / serviceUnavailable).

### 7.3 Export / Share

- `LeakReport.toJson()` → machine-readable; `LeakReport.toMarkdown()` → human-readable (table of findings + per-finding retaining path if loaded).
- `LeakRadar.exportToFile(format:)` writes to the app's temp/documents dir and returns the absolute path.
- **Share** button (screen only) uses `share_plus` to share the exported file. `share_plus` is confined to the UI layer so the core stays dependency-light.

---

## 8. Build-mode safety + "service unavailable"

### 8.1 Release = complete no-op

- A single compile-time gate: `const bool kEngineEnabled = kDebugMode || kProfileMode;` (with `kProfileMode`/`kDebugMode` from `foundation`). The active engine, `VmHeapProbe`, the registry, timers, and the overlay are all constructed only when `kEngineEnabled && config.enabled`.
- The facade short-circuits **before** touching any `vm_service`/`dart:developer` code path in release. `LeakRadar.overlay` returns `child` unchanged; `navigatorObserver` returns an inert observer; `scan` returns a `disabled` report; `track`/`markDisposed` return immediately.
- Following leak_tracker's pattern, the active machinery sits behind `kEngineEnabled` guards (and, for the heaviest paths, `assert` blocks) so the tree-shaker eliminates `package:vm_service` from release binaries. `package:vm_service` is a regular `dependencies` entry but is only ever imported from `VmHeapProbe`, which is never instantiated in release.

### 8.2 Service availability detection

`VmHeapProbe.isAvailable` is the gate for everything heap-related:

```dart
Future<bool> get isAvailable async {
  try {
    final info = await Service.getInfo();
    if (info.serverWebSocketUri != null) return true;
    final started = await Service.controlWebServer(enable: true);
    return started.serverWebSocketUri != null;
  } catch (_) {
    return false; // release no-ops can throw or return null
  }
}
```

Resulting status:

| Build / state | `status` | Heap engine | Precise opt-in |
|---|---|---|---|
| release / `enabled: false` | `disabled` | no-op | no-op |
| profile/debug, service reachable | `active` | on | on |
| profile without service | `preciseOnly` | NoopHeapProbe | on |
| service drops mid-session | `serviceUnavailable` | falls back to NoopHeapProbe | on |

When the probe is `NoopHeapProbe` (no service), the engine still runs precise detection and the report carries `status: preciseOnly`, so the UI explains why heap-level findings are absent.

---

## 9. Error handling

- **`runSafely` / `runSafelyAsync` (`util/safe.dart`).** Every public facade method and every engine callback (timer ticks, navigation, stream listeners) is wrapped. On error: degrade to a no-op, return a safe default (e.g. a `disabled`/`serviceUnavailable` report, or `null`), and emit one **rate-limited** debug log via `RateLimitedLogger`. Errors **never** propagate to the host.
- **VM-service RPCs.** Catch `RPCError`, `SentinelException` (object GCed mid-path), and socket/disconnect errors. Connection loss flips the probe to `unavailable`, status to `serviceUnavailable`, and the engine continues in precise-only mode. Reconnection is attempted lazily on the next scan.
- **Registry.** `markDisposed` for an untracked object is a silent no-op (logged at verbose). The shared `Finalizer` callback is wrapped so a throwing entry can't break collection bookkeeping.
- **Config validation.** `init` validates config (e.g. `maxSnapshots >= 2`, non-negative durations) and clamps invalid values to safe defaults with a single warning rather than throwing.
- **Logging.** `RateLimitedLogger` honors `LeakLogLevel`, dedupes identical messages, and caps frequency so a recurring failure can't spam the console or slow the host.

---

## 10. Testing strategy

Target ≥ 80% coverage. The pure layers carry most assertions; the VM-service and UI layers are tested behind interfaces/fakes.

- **Unit — `LeakAnalyzer` (pure, highest value).** Feed synthetic `SampleHistory` sequences and assert findings/severity: flat series → no finding; monotonic growth → growth finding; `maxLive` boundary (==, +1); `ignore` precedence; host override beats default; noisy-but-flat → info or none. AAA structure, deterministic, no fakes needed.
- **Unit — `SuspectSet`/`LeakRule`.** Glob matching (`State`, `*Screen`, `*Bloc`, exact, contains); `merge` precedence (ignore > override > add > default); equality/hashCode.
- **Unit — `LeakObjectRegistry`.** Using a fake GC-counter and controllable `reachabilityBarrier`, assert: disposed + N cycles + still alive → `notGced`; finalized without dispose → `notDisposed`; weak reference never extends lifetime (target nulls after GC); `markDisposed` on untracked is a no-op. Real-finalizer behavior validated in a focused integration test that forces GC.
- **Unit — models.** `toJson`/`toMarkdown` round-trips; `worstSeverity`; `copyWith`/equality for config types.
- **Engine — `_LeakEngine` with a `FakeHeapProbe`.** Inject scripted snapshots; assert capture→analyze→report pipeline, history bounding, precise-finding folding, scan serialization (overlapping triggers dropped), and graceful degradation when the fake reports `unavailable`.
- **`VmHeapProbe`.** Thin integration test under `flutter test` (VM service present): connect via `serverWebSocketUri`, `getAllocationProfile(gc: true)` returns members, name→`ClassRef` resolution, `getInstances` + `getRetainingPath` on a deliberately-retained object. Asserts the `controlWebServer` fallback path. Mock-based tests for `RPCError`/`SentinelException` handling.
- **Build-mode safety (invariant tests).** Assert: in release config the facade methods are no-ops (`status == disabled`, `overlay` returns the same child instance, `scan` returns a disabled report, `track`/`markDisposed` do nothing). A test that forces a thrown error inside an engine callback asserts nothing escapes the facade.
- **UI — widget/visual.** Widget tests for `LeakRadarScreen` rendering findings, empty state, lazy retaining-path expansion (spinner → content/unavailable) using a `FakeHeapProbe`. `GrowthSparkline` golden test. Overlay drag/tap interaction test.
- **Never-throw fuzz.** Property-style tests feeding malformed/partial snapshots and null path elements to assert no exception escapes and outputs stay well-formed.

---

## 11. Open questions

1. **Growth window shape.** Is a simple `latest - baseline` delta sufficient, or do we need a slope/regression over the window to suppress sawtooth noise from legitimate caches? (Lean: start with delta + monotonicity flag; add slope if false positives appear.)
2. **Forced GC cadence.** `getAllocationProfile(gc: true)` on every scan is reliable but heavy. Should periodic scans use `gc: false` for trend sampling and only force GC on manual/navigation scans? (Affects severity stability.)
3. **leak_tracker as a dependency vs. reference.** The engine research recommends *reusing* `package:leak_tracker` for the disposal lifecycle (Flutter auto-instrumentation for free) rather than re-implementing Finalizer/`reachabilityBarrier`. This spec implements the precise registry independently to keep the dependency surface minimal and the API mixin-free. Decision to confirm: depend on `leak_tracker` (gain auto-instrumentation of framework `ChangeNotifier`/`Element`/`RenderObject`) or stay self-contained (current design)? At minimum we mirror its `LeakKind` taxonomy for report consistency.
4. **Class-name collisions.** `getAllocationProfile` rows are per `ClassRef`; two libraries can expose same-named classes. Do we disambiguate suspects by `library` in `LeakRule` patterns, or accept simple-name matching with an optional `library:` qualifier? (Lean: simple name by default, optional qualifier later.)
5. **Overlay position persistence.** Session-only (current) vs. persisted across launches (would add a storage dependency). Likely keep session-only to stay dependency-light.
6. **Multi-isolate apps.** v1 inspects only `Isolate.current` (main). Do we expose per-isolate probing later, given object ids are isolate-scoped?

---

## 12. Milestones

- **M1 — Engine core + analysis (foundation).**
  - `HeapProbe` interface, `VmHeapProbe` (connect via `serverWebSocketUri`, `controlWebServer` fallback, `getAllocationProfile(gc:true)`, name→`ClassRef`, `getInstances`, `getRetainingPath`), `NoopHeapProbe`.
  - `SampleHistory`, `ClassSample`/`HeapSnapshot`, `SuspectSet` + `LeakRule` (defaults + merge), `LeakAnalyzer` (growth + maxLive + severity), models (`LeakReport`/`LeakFinding`).
  - `LeakObjectRegistry` (track/markDisposed, Finalizer/WeakReference, `gc_support`).
  - Build-mode gating (`kEngineEnabled`, `build_mode.dart`), `runSafely`, `RateLimitedLogger`.
  - Tests: analyzer, suspect-set, registry, models, fake-probe engine, build-mode no-op invariants.

- **M2 — Triggers + public API.**
  - `LeakRadar` facade (init/scan/track/markDisposed/reports/status/dispose), `LeakRadarConfig`/`AutoScan`, `_LeakEngine` orchestration + scan serialization.
  - `ScanScheduler` (periodic) and `LeakRadarNavigatorObserver` (debounced on-navigation).
  - Tests: engine pipeline, trigger wiring, config validation/clamping, degradation paths.

- **M3 — UI + export.**
  - `LeakRadarOverlay` (draggable badge), `LeakRadarScreen` (findings, severity, sparkline), `GrowthSparkline`, `RetainingPathTile` (lazy expand).
  - `LeakReport.toJson()`/`toMarkdown()`, `exportToFile()`, Share via `share_plus`.
  - Tests: widget tests, sparkline golden, lazy-path expansion, overlay interaction.

- **M4 — Polish + docs.**
  - `example/` (minimal runnable, pub points) + integration with the shared demo app, README, dartdoc on all public API, CHANGELOG, `topics`/`description` for pub score.
  - Real-device pass (debug + `--profile`), false-positive tuning of `SuspectSet.defaults()`, resolve open questions §11 (1–4).
  - Coverage ≥ 80%, `dart analyze --fatal-infos` clean, `pana` clean.
