# flutter_leak_radar — Runtime Follow-up Implementation Plan
> Plan date: 2026-06-23
> Builds on: merged runtime MVP (branch `feat/runtime-mvp`, 54 tests passing, `flutter analyze` clean)
> Output: deferred triggers, overlay, sparkline, retaining-path wiring, export/share

---

## Goal

Deliver the five deferred feature areas from the MVP build: (1) fix `VmHeapProbe.retainingPath` so it is production-ready before the UI exposes it, (2) add `AutoScan` config + `ScanScheduler` for periodic scans, (3) add `LeakRadarNavigatorObserver` for debounced navigation-triggered scans, (4) add the draggable `LeakRadarOverlay` badge and wire `LeakRadar.overlay()`/`navigatorObserver`, and (5) upgrade `LeakRadarScreen` with a `GrowthSparkline` CustomPainter, lazy retaining-path expansion tiles, and export/share via `share_plus`. The result is a fully-spec-compliant on-device tool with no unguarded VM-service code paths and zero net-new risk to the host app.

---

## Architecture

The follow-up adds three new source directories — `triggers/`, `ui/growth_sparkline.dart`, `ui/retaining_path_tile.dart`, `ui/leak_radar_overlay.dart` — and extends five existing files:

- **`config/leak_radar_config.dart`** gains the `AutoScan` value class and two new fields (`autoScan`, `maxRetainingPathRequests`). The current config has no `autoScan` or `maxRetainingPathRequests` field.
- **`engine/vm_heap_probe.dart`** gains a `Map<String, ClassRef> _classRefCache` (populated during `capture`) so `retainingPath` does not re-run `getAllocationProfile` per call; fixes the `parentMapKey` cast from `(el.parentMapKey as InstanceRef?)` to `el.parentMapKey is InstanceRef ? …`; enforces the `maxRetainingPathRequests` throttle; replaces the one-way `_connectFailed` latch with a recoverable reconnect state.
- **`engine/leak_engine.dart`** gains `ScanScheduler` + `LeakRadarNavigatorObserver` lifecycle hooks, started in `start()` and torn down in `stop()`.
- **`leak_radar.dart`** (facade) gains `overlay()`, `navigatorObserver`, and `exportToFile()`.
- **`model/leak_report.dart`** — `toJson()` and `toMarkdown()` already exist; no changes needed.
- **New `triggers/scan_scheduler.dart`** — `ScanScheduler` owns one `Timer.periodic` driven by `AutoScan.period`.
- **New `triggers/navigator_observer.dart`** — `LeakRadarNavigatorObserver extends NavigatorObserver`, debounces `didPop` via a `Timer`.
- **New `ui/leak_radar_overlay.dart`** — `LeakRadarOverlay` widget, `Overlay`/`Stack` + `Positioned` + `GestureDetector`; listens to `LeakRadar.reports`.
- **New `ui/growth_sparkline.dart`** — `GrowthSparkline` widget wrapping a `CustomPainter`.
- **New `ui/retaining_path_tile.dart`** — `RetainingPathTile` `ExpansionTile` with lazy fetch.
- **Upgraded `ui/leak_radar_screen.dart`** — adds Export/Share app-bar actions, replaces `_FindingTile` with a version that embeds `GrowthSparkline` + `RetainingPathTile`.

Data flow stays unchanged: all scan triggers funnel to `LeakEngine.scan(trigger:)`, which broadcasts on `_reports`. The overlay and screen are passive listeners.

---

## Tech Stack

Existing dependencies (unchanged):
- `flutter` SDK
- `package:vm_service ^15.0.0`
- `package:meta ^1.15.0`

New dependency (UI layer only):
- `share_plus: ^10.0.0` — added to `dependencies` in `packages/flutter_leak_radar/pubspec.yaml`. Imported **exclusively** from `lib/src/ui/`. No other layer may import it.

New dev dependencies:
- None (existing `flutter_test` + `flutter_lints` are sufficient; golden tests use the built-in `matchesGoldenFile` matcher).

---

## Global Constraints

- Never throw into the host app — wrap every public API call in `runSafely`/`runSafelyAsync`; surface errors via `RateLimitedLogger` only.
- Release no-op: every public API is guarded by `kEngineEnabled` (const bool compiled false in release); all engine and VM service code is dead-stripped in production builds.
- Hand-rolled immutable models — no freezed, no json_annotation code-gen. Manual `==`, `hashCode`, `copyWith` on every value type.
- Files ≤ 800 lines. Split if you approach the limit.
- Only `VmHeapProbe` may import `package:vm_service`. No other file in the package touches vm_service.
- `share_plus` is a UI-layer dependency only — import it exclusively inside `lib/src/ui/`. The engine and config layers must not import it.
- No `print()` anywhere in the package — use `debugPrint` only inside `kDebugMode` guards, or route through `RateLimitedLogger`.

---

## Milestone 1 — VmHeapProbe retaining-path fixes (prerequisite)

All four tasks touch only `lib/src/engine/vm_heap_probe.dart` and its test. Complete this milestone before writing any UI that calls `retainingPath`.

### Task 1.1 — Cache name→ClassRef from capture

**Files to touch:**
- `lib/src/engine/vm_heap_probe.dart`
- `test/engine/vm_heap_probe_test.dart` (new file or add group to existing)

**Interface / signature changes:**
Add `final Map<String, ClassRef> _classRefCache = {};` field.  
In `capture()`, after building `samples`, populate the cache: `_classRefCache[name] = m.classRef!;`.  
In `retainingPath()`, replace the full re-`getAllocationProfile` call with a cache lookup.

**Failing test (write first):**

```dart
// test/engine/vm_heap_probe_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';

// Fake VmService that counts getAllocationProfile calls.
class _CountingFakeService extends Fake implements VmService {
  int allocationProfileCalls = 0;
  // ...return minimal AllocationProfile with one member 'HomeBloc'
}

void main() {
  group('VmHeapProbe class-ref cache', () {
    test('retainingPath does not call getAllocationProfile when cache is warm', () async {
      final probe = VmHeapProbe();
      // Arrange: inject a fake service with a pre-populated cache entry.
      probe.debugInjectServiceAndCache(
        fakeService,
        isolateId: 'isolates/1',
        classRefCache: {'HomeBloc': fakeClassRef},
      );

      // Act: call retainingPath — should NOT call getAllocationProfile again.
      await probe.retainingPath('HomeBloc');

      // Assert: the fake's counter stays at 0.
      expect(fakeService.allocationProfileCalls, 0);
    });

    test('retainingPath falls back to getAllocationProfile when cache is cold', () async {
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(fakeService, isolateId: 'isolates/1');

      await probe.retainingPath('UnknownClass');

      expect(fakeService.allocationProfileCalls, 1);
    });
  });
}
```

**Implementation notes:**

```dart
// lib/src/engine/vm_heap_probe.dart  — additions

// New field:
final Map<String, ClassRef> _classRefCache = <String, ClassRef>{};

// In capture(), after: if (name == null || name.isEmpty) continue;
_classRefCache[name] = m.classRef!;   // warm the cache while iterating members

// In retainingPath(), replace the old getAllocationProfile block:
Future<RetainingPathView?> retainingPath(
  String className, {
  int maxInstances = 10,
}) async {
  final service = await _ensureConnected();
  final isolateId = _isolateId;
  if (service == null || isolateId == null) return null;
  try {
    // Cache lookup first — avoids a full getAllocationProfile per expand.
    String? classId = _classRefCache[className]?.id;
    if (classId == null) {
      // Cold: fall back to a fresh profile (first retainingPath before any capture).
      final profile = await service.getAllocationProfile(isolateId);
      for (final m in profile.members ?? const <ClassHeapStats>[]) {
        final name = m.classRef?.name;
        if (name != null && m.classRef != null) {
          _classRefCache[name] = m.classRef!;
        }
      }
      classId = _classRefCache[className]?.id;
    }
    if (classId == null) return null;
    // ... rest of getInstances + getRetainingPath unchanged
  } on SentinelException {
    return null;
  } catch (e) {
    _logger.log('retainingPath failed: $e', level: LeakLogLevel.error);
    return null;
  }
}

// Test seam (annotated @visibleForTesting):
@visibleForTesting
void debugInjectServiceAndCache(
  VmService service, {
  required String isolateId,
  Map<String, ClassRef>? classRefCache,
}) {
  _service = service;
  _isolateId = isolateId;
  if (classRefCache != null) _classRefCache.addAll(classRefCache);
}
```

**Commit message:** `fix(detector): cache name→ClassRef from capture in VmHeapProbe`

---

### Task 1.2 — Fix parentMapKey cast (is InstanceRef ?)

**Files to touch:**
- `lib/src/engine/vm_heap_probe.dart`

**Interface / signature changes:** none — internal implementation fix.

**Failing test (write first):**

```dart
// test/engine/vm_heap_probe_test.dart — add to existing group or new group
test('retainingPath handles non-InstanceRef parentMapKey without throwing', () async {
  // Arrange: fake getRetainingPath returns an element where parentMapKey
  // is a plain String (historical vm_service behavior), not an InstanceRef.
  final fakeService = _FakeVmServiceWithStringMapKey();
  final probe = VmHeapProbe();
  probe.debugInjectServiceAndCache(
    fakeService,
    isolateId: 'isolates/1',
    classRefCache: {'MyMap': fakeClassRef},
  );

  // Act: should not throw a CastError.
  final result = await probe.retainingPath('MyMap');

  // Assert: a RetainingPathView is returned (not null from an exception).
  expect(result, isNotNull);
  // The mapKey field is null when the cast fails gracefully.
  expect(result!.elements.first.mapKey, isNull);
});

test('retainingPath extracts mapKey when parentMapKey is InstanceRef', () async {
  final fakeService = _FakeVmServiceWithInstanceRefMapKey(valueAsString: 'myKey');
  final probe = VmHeapProbe();
  probe.debugInjectServiceAndCache(fakeService, isolateId: 'isolates/1',
      classRefCache: {'MyMap': fakeClassRef});

  final result = await probe.retainingPath('MyMap');

  expect(result!.elements.first.mapKey, 'myKey');
});
```

**Implementation notes:**

Replace the unsafe cast at line 167 of the current `vm_heap_probe.dart`:

```dart
// BEFORE (line ~167):
mapKey: (el.parentMapKey as InstanceRef?)?.valueAsString,

// AFTER:
mapKey: el.parentMapKey is InstanceRef
    ? (el.parentMapKey as InstanceRef).valueAsString
    : null,
```

This is a one-line surgical fix. The `is` check is safe even when `parentMapKey` is `String`, `null`, or any other type the VM service returns.

**Commit message:** `fix(detector): safe parentMapKey cast with is-check in VmHeapProbe`

---

### Task 1.3 — Wire maxRetainingPathRequests throttle

**Files to touch:**
- `lib/src/engine/vm_heap_probe.dart`
- `lib/src/config/leak_radar_config.dart` (expose field — added in Milestone 2, but wire the throttle here)

**Interface / signature changes:**
`VmHeapProbe` already accepts `maxRetainingPathRequests` in its constructor but ignores it in `retainingPath`. Add a per-cycle request counter that resets on `capture()`.

**Failing test (write first):**

```dart
test('retainingPath returns null after maxRetainingPathRequests per cycle', () async {
  final probe = VmHeapProbe(maxRetainingPathRequests: 2);
  probe.debugInjectServiceAndCache(
    fakeService,
    isolateId: 'isolates/1',
    classRefCache: {'A': fakeClassRef, 'B': fakeClassRef, 'C': fakeClassRef},
  );

  // Act: request 3 paths; limit is 2.
  final p1 = await probe.retainingPath('A');
  final p2 = await probe.retainingPath('B');
  final p3 = await probe.retainingPath('C'); // should be throttled → null

  expect(p1, isNotNull);
  expect(p2, isNotNull);
  expect(p3, isNull);  // throttled
});

test('retainingPath counter resets after capture', () async {
  final probe = VmHeapProbe(maxRetainingPathRequests: 1);
  probe.debugInjectServiceAndCache(
    fakeService,
    isolateId: 'isolates/1',
    classRefCache: {'A': fakeClassRef},
  );

  final p1 = await probe.retainingPath('A'); // allowed
  final p2 = await probe.retainingPath('A'); // throttled
  // Simulate a new capture cycle.
  await probe.capture(forceGc: false);       // resets counter
  final p3 = await probe.retainingPath('A'); // allowed again

  expect(p1, isNotNull);
  expect(p2, isNull);
  expect(p3, isNotNull);
});
```

**Implementation notes:**

```dart
// lib/src/engine/vm_heap_probe.dart — new field + reset
int _pathRequestsThisCycle = 0;

// At the top of capture() — reset counter each capture:
@override
Future<HeapSnapshot> capture({required bool forceGc}) async {
  _pathRequestsThisCycle = 0;  // <-- reset throttle budget
  final service = await _ensureConnected();
  // ... rest unchanged

// At the top of retainingPath() — gate before RPC:
@override
Future<RetainingPathView?> retainingPath(
  String className, {
  int maxInstances = 10,
}) async {
  if (_pathRequestsThisCycle >= maxRetainingPathRequests) {
    _logger.log(
      'retainingPath throttled: $maxRetainingPathRequests per-cycle limit reached',
      level: LeakLogLevel.verbose,
    );
    return null;
  }
  _pathRequestsThisCycle++;
  // ... rest of existing implementation
```

**Commit message:** `fix(detector): enforce maxRetainingPathRequests throttle in VmHeapProbe`

---

### Task 1.4 — Reconnect-latch recovery

**Files to touch:**
- `lib/src/engine/vm_heap_probe.dart`

**Problem:** `_connectFailed = true` is permanent. A transient socket drop + failed reconnect permanently bricks the probe. The spec (§9) promises lazy reconnection on the next scan.

**Failing test (write first):**

```dart
test('probe recovers after transient socket failure on next capture', () async {
  var callCount = 0;
  final probe = VmHeapProbe();
  // First connection attempt: fail.
  probe.debugInjectConnectionFactory(() async {
    callCount++;
    if (callCount == 1) throw const SocketException('transient');
    return fakeService;
  });

  // First capture: fails, status degrades gracefully.
  final snap1 = await probe.capture(forceGc: false);
  expect(snap1.samples, isEmpty);

  // Second capture: connection succeeds.
  final snap2 = await probe.capture(forceGc: false);
  // The fake service returns one sample.
  expect(snap2.samples, isNotEmpty);
});
```

**Implementation notes:**

Replace the permanent `_connectFailed` bool with a nullable `DateTime? _nextRetryAllowedAt` so a failed connection is retried after a backoff period (default 30 s):

```dart
// lib/src/engine/vm_heap_probe.dart

// Replace:
bool _connectFailed = false;

// With:
DateTime? _nextRetryAllowedAt;
static const Duration _reconnectBackoff = Duration(seconds: 30);

// In _ensureConnected():
Future<VmService?> _ensureConnected() async {
  if (_service != null) return _service;
  // Back-off check: if last attempt failed recently, don't retry yet.
  final retryAt = _nextRetryAllowedAt;
  if (retryAt != null && DateTime.now().isBefore(retryAt)) return null;
  try {
    final uri = await _serviceUri();
    if (uri == null) {
      _nextRetryAllowedAt = DateTime.now().add(_reconnectBackoff);
      return null;
    }
    final service = await vmServiceConnectUri(uri.toString());
    await service.getVersion();
    _isolateId =
        developer.Service.getIsolateId(dart_isolate.Isolate.current) ??
        (await service.getVM()).isolates?.first.id;
    _service = service;
    _nextRetryAllowedAt = null; // clear on success
    return service;
  } catch (e) {
    _logger.log('VmHeapProbe connect failed: $e', level: LeakLogLevel.error);
    _nextRetryAllowedAt = DateTime.now().add(_reconnectBackoff);
    return null;
  }
}

// In capture(), when a non-RPCError exception occurs (socket disconnected):
} catch (e) {
  _logger.log('capture failed: $e', level: LeakLogLevel.error);
  _service = null;              // drop connection
  _classRefCache.clear();       // cache is stale after reconnect
  _nextRetryAllowedAt = null;   // allow immediate retry on next call
  return HeapSnapshot(samples: const <ClassSample>[], capturedAt: DateTime.now());
}

// Test seam:
@visibleForTesting
void debugInjectConnectionFactory(Future<VmService> Function() factory) {
  _connectionFactory = factory;
}
Future<VmService> Function()? _connectionFactory;
```

**Commit message:** `fix(detector): replace permanent _connectFailed latch with backoff reconnect in VmHeapProbe`

---

## Milestone 2 — AutoScan config + ScanScheduler

### Task 2.1 — AutoScan config class

**Files to touch:**
- `lib/src/config/leak_radar_config.dart`
- `test/config/auto_scan_test.dart` (new)

**Interface / signature changes:**

Add `AutoScan` value class and two new fields to `LeakRadarConfig`: `autoScan` and `maxRetainingPathRequests`.

```dart
// New class to add to leak_radar_config.dart:
@immutable
final class AutoScan {
  const AutoScan({
    this.onNavigation = false,
    this.period,
    this.navigationDebounce = const Duration(milliseconds: 500),
  });

  final bool onNavigation;
  final Duration? period;
  final Duration navigationDebounce;

  bool get hasPeriodic => period != null;

  AutoScan copyWith({
    bool? onNavigation,
    Duration? period,
    Duration? navigationDebounce,
  }) =>
      AutoScan(
        onNavigation: onNavigation ?? this.onNavigation,
        period: period ?? this.period,
        navigationDebounce: navigationDebounce ?? this.navigationDebounce,
      );

  @override
  bool operator ==(Object other) =>
      other is AutoScan &&
      other.onNavigation == onNavigation &&
      other.period == period &&
      other.navigationDebounce == navigationDebounce;

  @override
  int get hashCode => Object.hash(onNavigation, period, navigationDebounce);
}
```

**Failing test (write first):**

```dart
// test/config/auto_scan_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';

void main() {
  group('AutoScan', () {
    test('default values', () {
      const s = AutoScan();
      expect(s.onNavigation, isFalse);
      expect(s.period, isNull);
      expect(s.hasPeriodic, isFalse);
      expect(s.navigationDebounce, const Duration(milliseconds: 500));
    });

    test('hasPeriodic is true when period is set', () {
      const s = AutoScan(period: Duration(seconds: 30));
      expect(s.hasPeriodic, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      const original = AutoScan(onNavigation: true);
      final copy = original.copyWith(period: const Duration(seconds: 60));
      expect(copy.onNavigation, isTrue);
      expect(copy.period, const Duration(seconds: 60));
    });

    test('equality and hashCode', () {
      const a = AutoScan(onNavigation: true, period: Duration(seconds: 30));
      const b = AutoScan(onNavigation: true, period: Duration(seconds: 30));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('LeakRadarConfig with AutoScan', () {
    test('default config has AutoScan with no triggers', () {
      const config = LeakRadarConfig();
      expect(config.autoScan.hasPeriodic, isFalse);
      expect(config.autoScan.onNavigation, isFalse);
    });

    test('copyWith updates autoScan', () {
      const original = LeakRadarConfig();
      final updated = original.copyWith(
        autoScan: const AutoScan(onNavigation: true),
      );
      expect(updated.autoScan.onNavigation, isTrue);
    });

    test('maxRetainingPathRequests defaults to 5', () {
      const config = LeakRadarConfig();
      expect(config.maxRetainingPathRequests, 5);
    });
  });
}
```

**Implementation notes:**

In `leak_radar_config.dart`, add new fields and update `copyWith`/`==`/`hashCode`:

```dart
@immutable
final class LeakRadarConfig {
  const LeakRadarConfig({
    this.enabled = true,
    this.autoScan = const AutoScan(),          // NEW
    this.suspects = const SuspectSet.empty(),
    this.rules = const <LeakRule>[],
    this.maxSnapshots = 20,
    this.gcCyclesForPreciseLeak = 3,
    this.disposalGrace = const Duration(seconds: 2),
    this.maxRetainingPathRequests = 5,         // NEW
    this.logLevel = LeakLogLevel.warning,
  });

  final bool enabled;
  final AutoScan autoScan;                     // NEW
  // ... existing fields ...
  final int maxRetainingPathRequests;          // NEW

  // Update LeakRadarConfig.standard() factory to accept autoScan:
  factory LeakRadarConfig.standard({
    AutoScan autoScan = const AutoScan(),
    List<LeakRule> rules = const <LeakRule>[],
    SuspectSet? suspects,
    int maxSnapshots = 20,
  }) => LeakRadarConfig(
        enabled: kDebugMode || kProfileMode,
        autoScan: autoScan,
        suspects: suspects ?? SuspectSet.defaults(),
        rules: rules,
        maxSnapshots: maxSnapshots,
      );
```

**Commit message:** `feat(detector): add AutoScan config class + maxRetainingPathRequests to LeakRadarConfig`

---

### Task 2.2 — ScanScheduler (periodic Timer)

**Files to touch:**
- `lib/src/triggers/scan_scheduler.dart` (new file)
- `test/triggers/scan_scheduler_test.dart` (new file)

**Interface / signature changes:** New class. `LeakEngine.start()` will call `_scheduler.start()` (wired in Task 2.3).

**Failing test (write first):**

```dart
// test/triggers/scan_scheduler_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/triggers/scan_scheduler.dart';

void main() {
  group('ScanScheduler', () {
    test('does not fire when period is null', () async {
      var fired = 0;
      final scheduler = ScanScheduler(
        period: null,
        onTick: () async { fired++; },
      );
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      scheduler.stop();
      expect(fired, 0);
    });

    test('fires at the configured period', () async {
      var fired = 0;
      final scheduler = ScanScheduler(
        period: const Duration(milliseconds: 20),
        onTick: () async { fired++; },
      );
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      scheduler.stop();
      // Should have fired approximately 3 times (20ms intervals over 70ms).
      expect(fired, greaterThanOrEqualTo(2));
    });

    test('stop cancels the timer — no more ticks', () async {
      var fired = 0;
      final scheduler = ScanScheduler(
        period: const Duration(milliseconds: 20),
        onTick: () async { fired++; },
      );
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      scheduler.stop();
      final countAtStop = fired;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, countAtStop); // no more ticks after stop
    });

    test('start is idempotent — calling twice does not double-fire', () async {
      var fired = 0;
      final scheduler = ScanScheduler(
        period: const Duration(milliseconds: 20),
        onTick: () async { fired++; },
      );
      scheduler.start();
      scheduler.start(); // second call should be a no-op
      await Future<void>.delayed(const Duration(milliseconds: 60));
      scheduler.stop();
      // Should not have fired at 2x rate.
      expect(fired, lessThanOrEqualTo(5));
    });
  });
}
```

**Implementation notes:**

```dart
// lib/src/triggers/scan_scheduler.dart
import 'dart:async';

/// Fires [onTick] at [period] intervals. No-op when [period] is null.
/// Designed for use by [LeakEngine] only.
class ScanScheduler {
  ScanScheduler({
    required Duration? period,
    required Future<void> Function() onTick,
  })  : _period = period,
        _onTick = onTick;

  final Duration? _period;
  final Future<void> Function() _onTick;
  Timer? _timer;

  /// Starts the periodic timer. Idempotent — a second call is a no-op.
  void start() {
    if (_period == null || _timer != null) return;
    _timer = Timer.periodic(_period!, (_) => _onTick());
  }

  /// Cancels the timer. Safe to call multiple times.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

**Commit message:** `feat(detector): add ScanScheduler for periodic auto-scans`

---

### Task 2.3 — Wire AutoScan into LeakEngine + LeakRadar.init

**Files to touch:**
- `lib/src/engine/leak_engine.dart`
- `lib/src/leak_radar.dart`
- `test/engine/leak_engine_test.dart` (extend existing test file)

**Interface / signature changes:**

`LeakEngine` constructor gains `AutoScan? autoScan`; `start()` creates a `ScanScheduler` when `autoScan.hasPeriodic`.

**Failing test (write first):**

```dart
// test/engine/leak_engine_test.dart — add group:
group('LeakEngine periodic scan via ScanScheduler', () {
  test('periodic scan fires and produces a report on the reports stream', () async {
    final probe = FakeHeapProbe();
    final engine = LeakEngine(
      probe: probe,
      analyzer: LeakAnalyzer(SuspectSet.empty()),
      autoScan: const AutoScan(period: Duration(milliseconds: 30)),
    );

    final reports = <LeakReport>[];
    final sub = engine.reports.listen(reports.add);
    await engine.start();

    await Future<void>.delayed(const Duration(milliseconds: 100));
    await engine.stop();
    await sub.cancel();

    // At least one report should have been emitted.
    expect(reports, isNotEmpty);
    expect(reports.first.trigger, 'periodic');
  });

  test('stop() cancels periodic timer — no reports after stop', () async {
    final probe = FakeHeapProbe();
    final engine = LeakEngine(
      probe: probe,
      analyzer: LeakAnalyzer(SuspectSet.empty()),
      autoScan: const AutoScan(period: Duration(milliseconds: 20)),
    );
    await engine.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await engine.stop();
    final countAtStop = (await engine.reports.toList()).length; // stream is closed
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // No way to receive more reports — stream is closed.
    expect(countAtStop, 0); // reports stream drained when closed
  });
});
```

**Implementation notes:**

```dart
// lib/src/engine/leak_engine.dart — additions

import '../config/leak_radar_config.dart';   // for AutoScan
import '../triggers/scan_scheduler.dart';

@internal
class LeakEngine {
  LeakEngine({
    required HeapProbe probe,
    required LeakAnalyzer analyzer,
    SampleHistory? history,
    LeakObjectRegistry? registry,
    int gcCyclesForPreciseLeak = 3,
    RateLimitedLogger? logger,
    AutoScan? autoScan,                       // NEW
  })  : _probe = probe,
        _analyzer = analyzer,
        _history = history ?? SampleHistory(),
        _registry = registry ?? LeakObjectRegistry(),
        _gcCyclesForPreciseLeak = gcCyclesForPreciseLeak,
        _logger = logger ?? RateLimitedLogger(),
        _autoScan = autoScan ?? const AutoScan();  // NEW

  // ... existing fields ...
  final AutoScan _autoScan;                   // NEW
  ScanScheduler? _scheduler;                 // NEW

  Future<void> start() async {
    // ... existing probe availability check unchanged ...

    // Wire periodic scanner if configured:
    if (_autoScan.hasPeriodic) {
      _scheduler = ScanScheduler(
        period: _autoScan.period,
        onTick: () => runSafelyAsync(
          () => scan(trigger: 'periodic'),
          fallback: null,
          logger: _logger,
        ),
      );
      _scheduler!.start();
    }
  }

  Future<void> stop() async {
    _scheduler?.stop();                        // NEW
    _scheduler = null;
    // ... rest of existing stop() unchanged ...
  }
}
```

In `leak_radar.dart`, pass `config.autoScan` and `maxRetainingPathRequests` when constructing `LeakEngine` and `VmHeapProbe`:

```dart
// In LeakRadar.init():
HeapProbe probe = VmHeapProbe(
  logger: _logger,
  maxRetainingPathRequests: config.maxRetainingPathRequests,  // NEW
);
// ...
final engine = LeakEngine(
  probe: probe,
  analyzer: LeakAnalyzer(config.suspects.merge(config.rules)),
  history: SampleHistory(maxSnapshots: config.maxSnapshots),
  registry: LeakObjectRegistry(disposalGrace: config.disposalGrace),
  gcCyclesForPreciseLeak: config.gcCyclesForPreciseLeak,
  logger: _logger,
  autoScan: config.autoScan,                 // NEW
);
```

**Commit message:** `feat(detector): wire AutoScan/ScanScheduler into LeakEngine and LeakRadar.init`

---

## Milestone 3 — LeakRadarNavigatorObserver

### Task 3.1 — Observer with debounced scan on didPop

**Files to touch:**
- `lib/src/triggers/navigator_observer.dart` (new file)
- `test/triggers/navigator_observer_test.dart` (new file)

**Interface / signature changes:** New `LeakRadarNavigatorObserver` class. Constructor takes a `Future<void> Function()` callback and a `Duration debounce`.

**Failing test (write first):**

```dart
// test/triggers/navigator_observer_test.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/triggers/navigator_observer.dart';

void main() {
  group('LeakRadarNavigatorObserver', () {
    testWidgets('single didPop triggers exactly one scan after debounce', (tester) async {
      var scanCount = 0;
      final observer = LeakRadarNavigatorObserver(
        onScan: () async { scanCount++; },
        debounce: const Duration(milliseconds: 50),
      );

      observer.didPop(Route<void>.of(context: null), null);

      // Before debounce expires: no scan yet.
      await tester.pump(const Duration(milliseconds: 20));
      expect(scanCount, 0);

      // After debounce: one scan.
      await tester.pump(const Duration(milliseconds: 60));
      expect(scanCount, 1);
    });

    testWidgets('rapid didPop calls are coalesced into a single scan', (tester) async {
      var scanCount = 0;
      final observer = LeakRadarNavigatorObserver(
        onScan: () async { scanCount++; },
        debounce: const Duration(milliseconds: 50),
      );

      // Three rapid pops within the debounce window.
      observer.didPop(Route<void>.of(context: null), null);
      await tester.pump(const Duration(milliseconds: 10));
      observer.didPop(Route<void>.of(context: null), null);
      await tester.pump(const Duration(milliseconds: 10));
      observer.didPop(Route<void>.of(context: null), null);

      // After debounce expires.
      await tester.pump(const Duration(milliseconds: 100));
      expect(scanCount, 1);  // coalesced
    });

    testWidgets('didPush and didReplace do not trigger a scan', (tester) async {
      var scanCount = 0;
      final observer = LeakRadarNavigatorObserver(
        onScan: () async { scanCount++; },
        debounce: const Duration(milliseconds: 20),
      );

      observer.didPush(Route<void>.of(context: null), null);
      observer.didReplace(newRoute: null, oldRoute: null);
      await tester.pump(const Duration(milliseconds: 60));
      expect(scanCount, 0);
    });
  });
}
```

**Implementation notes:**

```dart
// lib/src/triggers/navigator_observer.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

/// Triggers a debounced scan when the user navigates back (didPop).
/// Instantiate once and add to [MaterialApp.navigatorObservers].
class LeakRadarNavigatorObserver extends NavigatorObserver {
  LeakRadarNavigatorObserver({
    required Future<void> Function() onScan,
    Duration debounce = const Duration(milliseconds: 500),
  })  : _onScan = onScan,
        _debounce = debounce;

  final Future<void> Function() _onScan;
  final Duration _debounce;
  Timer? _debounceTimer;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      _onScan();
      _debounceTimer = null;
    });
  }

  /// Cancels any pending debounce timer.
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
```

**Commit message:** `feat(detector): add LeakRadarNavigatorObserver with debounced didPop scan`

---

### Task 3.2 — Wire navigatorObserver into LeakEngine and expose on facade

**Files to touch:**
- `lib/src/engine/leak_engine.dart`
- `lib/src/leak_radar.dart`
- `test/engine/leak_engine_test.dart` (extend)

**Interface / signature changes:**

`LeakEngine` gains a `LeakRadarNavigatorObserver? navigatorObserver` getter.  
`LeakRadar` gains a static `NavigatorObserver get navigatorObserver`.

**Failing test (write first):**

```dart
// test/engine/leak_engine_test.dart — add to existing file
group('LeakEngine navigation observer', () {
  test('navigatorObserver triggers a scan with navigation trigger', () async {
    final probe = FakeHeapProbe();
    final engine = LeakEngine(
      probe: probe,
      analyzer: LeakAnalyzer(SuspectSet.empty()),
      autoScan: const AutoScan(
        onNavigation: true,
        navigationDebounce: Duration(milliseconds: 20),
      ),
    );
    final reports = <LeakReport>[];
    engine.reports.listen(reports.add);
    await engine.start();

    // Simulate a pop via the observer.
    engine.navigatorObserver?.didPop(
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
      null,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await engine.stop();

    expect(reports.where((r) => r.trigger == 'navigation'), isNotEmpty);
  });

  test('navigatorObserver is null when onNavigation is false', () async {
    final probe = FakeHeapProbe();
    final engine = LeakEngine(
      probe: probe,
      analyzer: LeakAnalyzer(SuspectSet.empty()),
      autoScan: const AutoScan(onNavigation: false),
    );
    await engine.start();
    expect(engine.navigatorObserver, isNull);
    await engine.stop();
  });
});

// Facade test:
test('LeakRadar.navigatorObserver returns inert observer when disabled', () async {
  // No init called — engine is null.
  final obs = LeakRadar.navigatorObserver;
  expect(obs, isA<NavigatorObserver>());
  // Calling didPop on the inert observer must not throw.
  expect(
    () => obs.didPop(
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
      null,
    ),
    returnsNormally,
  );
});
```

**Implementation notes:**

```dart
// lib/src/engine/leak_engine.dart — additions

LeakRadarNavigatorObserver? _navObserver;

// Expose getter:
LeakRadarNavigatorObserver? get navigatorObserver => _navObserver;

// In start():
if (_autoScan.onNavigation) {
  _navObserver = LeakRadarNavigatorObserver(
    onScan: () => runSafelyAsync(
      () => scan(trigger: 'navigation'),
      fallback: null,
      logger: _logger,
    ),
    debounce: _autoScan.navigationDebounce,
  );
}

// In stop():
_navObserver?.dispose();
_navObserver = null;
```

```dart
// lib/src/leak_radar.dart — new inert observer + getter

/// An inert NavigatorObserver used when the engine is disabled.
class _InertNavigatorObserver extends NavigatorObserver {}
static final NavigatorObserver _inertObserver = _InertNavigatorObserver();

static NavigatorObserver get navigatorObserver =>
    runSafely(
      () => _engine?.navigatorObserver ?? _inertObserver,
      fallback: _inertObserver,
      logger: _logger,
    );
```

**Commit message:** `feat(detector): expose navigatorObserver on LeakEngine and LeakRadar facade`

---

## Milestone 4 — LeakRadarOverlay

### Task 4.1 — Draggable overlay badge widget

**Files to touch:**
- `lib/src/ui/leak_radar_overlay.dart` (new file)
- `test/ui/leak_radar_overlay_test.dart` (new file)

**Interface / signature changes:** New `LeakRadarOverlay` stateful widget that wraps `child`.

**Failing test (write first):**

```dart
// test/ui/leak_radar_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/ui/leak_radar_overlay.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/model/leak_finding.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';

void main() {
  group('LeakRadarOverlay', () {
    testWidgets('renders child unchanged when hidden', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(
            show: false,
            child: const Text('content'),
          ),
        ),
      );
      expect(find.text('content'), findsOneWidget);
      expect(find.byKey(const Key('leak_radar_badge')), findsNothing);
    });

    testWidgets('badge is visible when show:true and a report is supplied', (tester) async {
      final report = LeakReport(
        findings: [
          const LeakFinding(
            className: 'HomeBloc',
            kind: LeakKind.growth,
            severity: LeakSeverity.critical,
            liveCount: 3,
            growth: 2,
          ),
        ],
        capturedAt: DateTime.now(),
        trigger: 'manual',
        status: LeakRadarStatus.active,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(
            show: true,
            initialReport: report,
            child: const Scaffold(body: Text('content')),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('leak_radar_badge')), findsOneWidget);
      // Count text shows 1 finding.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('tapping badge navigates to LeakRadarScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(
            show: true,
            initialReport: LeakReport(
              findings: const [],
              capturedAt: DateTime.now(),
              trigger: 'manual',
              status: LeakRadarStatus.active,
            ),
            child: const Scaffold(body: Text('content')),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('leak_radar_badge')));
      await tester.pumpAndSettle();

      expect(find.text('Leak Radar'), findsOneWidget); // AppBar title
    });

    testWidgets('badge color reflects worst severity', (tester) async {
      // critical → red; warning → orange; info → blue
      final criticalReport = LeakReport(
        findings: [
          const LeakFinding(
            className: 'X',
            kind: LeakKind.notGced,
            severity: LeakSeverity.critical,
            liveCount: 1,
            growth: 0,
          ),
        ],
        capturedAt: DateTime.now(),
        trigger: 'manual',
        status: LeakRadarStatus.active,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(
            show: true,
            initialReport: criticalReport,
            child: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();

      // Find the badge container and check its color.
      final badge = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('leak_radar_badge')),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = badge.decoration as BoxDecoration;
      expect(decoration.color, Colors.red);
    });
  });
}
```

**Implementation notes:**

```dart
// lib/src/ui/leak_radar_overlay.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';
import 'leak_radar_screen.dart';

/// Wraps [child] and floats a draggable badge showing the current worst
/// severity and finding count. Returns [child] unchanged when [show] is false.
class LeakRadarOverlay extends StatefulWidget {
  const LeakRadarOverlay({
    super.key,
    required this.child,
    this.show = true,
    this.initialReport,
  });

  final Widget child;
  final bool show;
  final LeakReport? initialReport; // test seam; production uses LeakRadar.reports

  @override
  State<LeakRadarOverlay> createState() => _LeakRadarOverlayState();
}

class _LeakRadarOverlayState extends State<LeakRadarOverlay> {
  static const double _badgeSize = 48.0;
  static const double _initialRight = 16.0;
  static const double _initialBottom = 100.0;

  double _right = _initialRight;
  double _bottom = _initialBottom;

  LeakReport? _report;
  StreamSubscription<LeakReport>? _sub;

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport ?? LeakRadar.latest;
    _sub = LeakRadar.reports.listen((r) {
      if (mounted) setState(() => _report = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _badgeColor(LeakSeverity s) => switch (s) {
        LeakSeverity.critical => Colors.red,
        LeakSeverity.warning => Colors.orange,
        LeakSeverity.info => Colors.blue,
      };

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          right: _right,
          bottom: _bottom,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _right = (_right - details.delta.dx).clamp(0, double.infinity);
                _bottom = (_bottom - details.delta.dy).clamp(0, double.infinity);
              });
            },
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LeakRadarScreen(),
                ),
              );
            },
            onLongPress: () {
              LeakRadar.scan();
            },
            child: _Badge(
              key: const Key('leak_radar_badge'),
              report: _report,
              badgeColor: _badgeColor,
              size: _badgeSize,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.report,
    required this.badgeColor,
    required this.size,
  });

  final LeakReport? report;
  final Color Function(LeakSeverity) badgeColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final count = r?.findings.length ?? 0;
    final severity = r?.worstSeverity ?? LeakSeverity.info;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: badgeColor(severity),
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(blurRadius: 4, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
```

**Commit message:** `feat(ui): add LeakRadarOverlay draggable badge`

---

### Task 4.2 — facade overlay() method

**Files to touch:**
- `lib/src/leak_radar.dart`
- `lib/flutter_leak_radar.dart` (public export for `LeakRadarOverlay`)

**Failing test (write first):**

```dart
// test/leak_radar_test.dart — add group:
group('LeakRadar.overlay()', () {
  testWidgets('returns child unchanged when not initialized', (tester) async {
    const key = Key('child');
    final child = const SizedBox(key: key);

    final result = LeakRadar.overlay(child: child);

    // When disabled, the same widget instance should be returned.
    expect(result, same(child));
  });

  testWidgets('wraps child in LeakRadarOverlay when enabled and showOverlay:true', (tester) async {
    await LeakRadar.debugInstall(
      LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ),
    );

    final child = const SizedBox();
    final overlaid = LeakRadar.overlay(child: child);
    expect(overlaid, isA<LeakRadarOverlay>());

    await LeakRadar.dispose();
  });
});
```

**Implementation notes:**

Add a `showOverlay` flag to `LeakRadarConfig` and `LeakRadar._showOverlay` storage, then:

```dart
// lib/src/leak_radar.dart

static bool _showOverlay = true;

static Widget overlay({required Widget child}) {
  if (!kEngineEnabled || _engine == null || !_showOverlay) return child;
  return runSafely(
    () => LeakRadarOverlay(show: true, child: child),
    fallback: child,
    logger: _logger,
  );
}
```

In `LeakRadar.init()`, after building the engine, capture `config.showOverlay` into `_showOverlay`. Add `showOverlay` field to `LeakRadarConfig`:

```dart
// In LeakRadarConfig:
final bool showOverlay;  // default: true

// In LeakRadar.init():
_showOverlay = config.showOverlay;
```

Export `LeakRadarOverlay` from the public library:
```dart
// lib/flutter_leak_radar.dart — add:
export 'src/ui/leak_radar_overlay.dart' show LeakRadarOverlay;
```

**Commit message:** `feat(detector): add LeakRadar.overlay() facade method + showOverlay config`

---

## Milestone 5 — Screen upgrades

### Task 5.1 — GrowthSparkline CustomPainter

**Files to touch:**
- `lib/src/ui/growth_sparkline.dart` (new file)
- `test/ui/growth_sparkline_test.dart` (new file, includes golden)

**Failing test (write first):**

```dart
// test/ui/growth_sparkline_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/ui/growth_sparkline.dart';

void main() {
  group('GrowthSparkline', () {
    testWidgets('renders without error for empty series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GrowthSparkline(series: [], width: 80, height: 24),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for single-point series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GrowthSparkline(series: [5], width: 80, height: 24),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for flat series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GrowthSparkline(
              series: [3, 3, 3, 3, 3],
              width: 80,
              height: 24,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for growing series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GrowthSparkline(
              series: [1, 2, 4, 7, 12],
              width: 120,
              height: 32,
              color: Colors.red,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('golden — growing series renders expected sparkline', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: GrowthSparkline(
                series: [1, 2, 4, 7, 12, 18],
                width: 120,
                height: 32,
                color: Colors.red,
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(GrowthSparkline),
        matchesGoldenFile('goldens/growth_sparkline_growing.png'),
      );
    });
  });
}
```

**Implementation notes:**

```dart
// lib/src/ui/growth_sparkline.dart
import 'package:flutter/material.dart';

/// Tiny inline sparkline showing the live-count series from [LeakFinding.series].
///
/// Normalized to fit [height]; points are connected with a stroked line.
/// Handles empty and single-point series gracefully (renders nothing / a dot).
class GrowthSparkline extends StatelessWidget {
  const GrowthSparkline({
    super.key,
    required this.series,
    this.width = 80.0,
    this.height = 24.0,
    this.color = Colors.red,
    this.strokeWidth = 1.5,
  });

  final List<int> series;
  final double width;
  final double height;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          series: series,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.series,
    required this.color,
    required this.strokeWidth,
  });

  final List<int> series;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (series.length == 1) {
      // Single point: draw a dot.
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        strokeWidth,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final maxVal = series.reduce((a, b) => a > b ? a : b);
    final minVal = series.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).toDouble();

    Offset _toOffset(int i, int v) {
      final x = size.width * i / (series.length - 1);
      final y = range == 0
          ? size.height / 2
          : size.height * (1.0 - (v - minVal) / range);
      return Offset(x, y);
    }

    final path = Path();
    path.moveTo(0, _toOffset(0, series.first).dy);
    for (var i = 0; i < series.length; i++) {
      final o = _toOffset(i, series[i]);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.series != series || old.color != color || old.strokeWidth != strokeWidth;
}
```

**Commit message:** `feat(ui): add GrowthSparkline CustomPainter widget`

---

### Task 5.2 — Lazy retaining-path expansion tile

**Files to touch:**
- `lib/src/ui/retaining_path_tile.dart` (new file)
- `lib/src/ui/leak_radar_screen.dart` (upgrade `_FindingTile`)
- `test/ui/retaining_path_tile_test.dart` (new file)

**Failing test (write first):**

```dart
// test/ui/retaining_path_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/ui/retaining_path_tile.dart';
import 'package:flutter_leak_radar/src/model/retaining_path.dart';

void main() {
  group('RetainingPathTile', () {
    testWidgets('shows spinner while fetching', (tester) async {
      final completer = Completer<RetainingPathView?>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainingPathTile(
              className: 'HomeBloc',
              onFetch: () => completer.future,
            ),
          ),
        ),
      );

      // Expand the tile.
      await tester.tap(find.byType(ExpansionTile));
      await tester.pump();

      // Spinner should be visible while future is pending.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders path hops after fetch completes', (tester) async {
      final path = RetainingPathView(
        gcRootType: 'IsolateField',
        elements: [
          const RetainingHop(objectType: 'AppState', field: '_blocs'),
          const RetainingHop(objectType: 'HomeBloc'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainingPathTile(
              className: 'HomeBloc',
              onFetch: () async => path,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.text('GC root: IsolateField'), findsOneWidget);
      expect(find.textContaining('AppState'), findsOneWidget);
      expect(find.textContaining('_blocs'), findsOneWidget);
    });

    testWidgets('shows unavailable message when fetch returns null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainingPathTile(
              className: 'HomeBloc',
              onFetch: () async => null,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.text('Retaining path unavailable'), findsOneWidget);
    });

    testWidgets('does not fetch again on second expand', (tester) async {
      var fetchCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainingPathTile(
              className: 'HomeBloc',
              onFetch: () async {
                fetchCount++;
                return null;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile)); // collapse
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile)); // re-expand
      await tester.pumpAndSettle();

      expect(fetchCount, 1); // fetched only once
    });
  });
}
```

**Implementation notes:**

```dart
// lib/src/ui/retaining_path_tile.dart
import 'package:flutter/material.dart';
import '../model/retaining_path.dart';

/// Expansion tile that lazily fetches and renders a retaining path.
///
/// [onFetch] is called at most once (on first expand). Subsequent expands
/// reuse the cached result. A null return renders "unavailable".
class RetainingPathTile extends StatefulWidget {
  const RetainingPathTile({
    super.key,
    required this.className,
    required this.onFetch,
  });

  final String className;
  final Future<RetainingPathView?> Function() onFetch;

  @override
  State<RetainingPathTile> createState() => _RetainingPathTileState();
}

class _RetainingPathTileState extends State<RetainingPathTile> {
  // Tri-state: null = not fetched, true = fetching, false/value = done.
  bool _fetching = false;
  bool _fetched = false;
  RetainingPathView? _path;

  Future<void> _fetch() async {
    if (_fetched || _fetching) return;
    setState(() => _fetching = true);
    final path = await widget.onFetch();
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _fetched = true;
      _path = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('Retaining path — ${widget.className}'),
      onExpansionChanged: (expanded) {
        if (expanded) _fetch();
      },
      children: [_body()],
    );
  }

  Widget _body() {
    if (_fetching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!_fetched) return const SizedBox.shrink();
    final path = _path;
    if (path == null) {
      return const ListTile(
        dense: true,
        title: Text('Retaining path unavailable'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (path.gcRootType != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.anchor, size: 16),
            title: Text('GC root: ${path.gcRootType}'),
          ),
        for (final hop in path.elements) _HopTile(hop: hop),
      ],
    );
  }
}

class _HopTile extends StatelessWidget {
  const _HopTile({required this.hop});
  final RetainingHop hop;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[hop.objectType];
    if (hop.field != null) parts.add('.${hop.field}');
    if (hop.index != null) parts.add('[${hop.index}]');
    if (hop.mapKey != null) parts.add('["${hop.mapKey}"]');
    return ListTile(
      dense: true,
      leading: const Icon(Icons.arrow_downward, size: 14),
      title: Text(parts.join()),
    );
  }
}
```

**Upgrade `leak_radar_screen.dart`** — replace `_FindingTile` with an upgraded version:

```dart
// lib/src/ui/leak_radar_screen.dart — _FindingTile replacement
// (Replace the entire _FindingTile class)

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});
  final LeakFinding finding;

  Color _color(LeakSeverity s) => switch (s) {
        LeakSeverity.critical => Colors.red,
        LeakSeverity.warning => Colors.orange,
        LeakSeverity.info => Colors.blue,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: _color(finding.severity),
              radius: 8,
            ),
            title: Text(finding.className),
            subtitle: Text(
              '${finding.kind.name} · live ${finding.liveCount} · '
              '+${finding.growth}'
              '${finding.tag != null ? ' · ${finding.tag}' : ''}',
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(finding.severity.name),
                const SizedBox(height: 4),
                GrowthSparkline(series: finding.series),
              ],
            ),
          ),
          if (finding.series.isNotEmpty)
            RetainingPathTile(
              className: finding.className,
              onFetch: () => LeakRadar._fetchRetainingPath(finding.className),
            ),
        ],
      ),
    );
  }
}
```

Note: `LeakRadar._fetchRetainingPath` is a new internal method that routes to `_engine`'s probe (added in Task 6.1 alongside export).

**Commit message:** `feat(ui): add RetainingPathTile + GrowthSparkline into LeakRadarScreen findings`

---

## Milestone 6 — Export/share

### Task 6.1 — LeakRadar.exportToFile() + retaining-path fetch

**Files to touch:**
- `lib/src/leak_radar.dart`
- `lib/src/engine/leak_engine.dart` (add `fetchRetainingPath` delegation)
- `lib/flutter_leak_radar.dart` (export `LeakExportFormat`)
- `test/leak_radar_export_test.dart` (new file)

**Interface / signature changes:**

```dart
// New method on LeakRadar:
static Future<String?> exportToFile({
  LeakExportFormat format = LeakExportFormat.markdown,
}) async { ... }

// New internal delegation on LeakEngine:
Future<RetainingPathView?> fetchRetainingPath(String className) async { ... }

// New enum (add to existing leak_radar.dart or to a small file):
enum LeakExportFormat { json, markdown }
```

**Failing test (write first):**

```dart
// test/leak_radar_export_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/model/leak_finding.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';

void main() {
  tearDown(LeakRadar.dispose);

  group('LeakRadar.exportToFile()', () {
    test('returns null when no report exists', () async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final path = await LeakRadar.exportToFile();
      expect(path, isNull);
    });

    test('writes markdown file and returns absolute path', () async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      // Force a scan so latest is set.
      await LeakRadar.scan();
      final path = await LeakRadar.exportToFile(format: LeakExportFormat.markdown);

      expect(path, isNotNull);
      expect(path, endsWith('.md'));
      final file = File(path!);
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('# Leak report'));
      file.deleteSync();
    });

    test('writes json file and returns absolute path', () async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      await LeakRadar.scan();
      final path = await LeakRadar.exportToFile(format: LeakExportFormat.json);

      expect(path, isNotNull);
      expect(path, endsWith('.json'));
      final file = File(path!);
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('"trigger"'));
      file.deleteSync();
    });

    test('returns null when disabled', () async {
      // No engine installed.
      final path = await LeakRadar.exportToFile();
      expect(path, isNull);
    });
  });
}
```

**Implementation notes:**

```dart
// lib/src/engine/leak_engine.dart — add delegation:
Future<RetainingPathView?> fetchRetainingPath(String className) async {
  return runSafelyAsync(
    () => _probe.retainingPath(className),
    fallback: null,
    logger: _logger,
  );
}
```

```dart
// lib/src/leak_radar.dart — additions

import 'dart:io';
import 'package:path_provider/path_provider.dart';  // NOTE: see design question below

enum LeakExportFormat { json, markdown }

static Future<RetainingPathView?> _fetchRetainingPath(String className) =>
    runSafelyAsync(
      () async => _engine?.fetchRetainingPath(className),
      fallback: null,
      logger: _logger,
    );

static Future<String?> exportToFile({
  LeakExportFormat format = LeakExportFormat.markdown,
}) async {
  if (!kEngineEnabled) return null;
  return runSafelyAsync<String?>(() async {
    final report = _engine?.latest;
    if (report == null) return null;

    final dir = await getTemporaryDirectory();
    final stamp = report.capturedAt.millisecondsSinceEpoch;
    final ext = format == LeakExportFormat.json ? 'json' : 'md';
    final file = File('${dir.path}/leak_report_$stamp.$ext');

    final content = format == LeakExportFormat.json
        ? _jsonEncode(report.toJson())
        : report.toMarkdown();
    await file.writeAsString(content);
    return file.path;
  }, fallback: null, logger: _logger);
}

static String _jsonEncode(Map<String, Object?> map) {
  // Simple recursive JSON encoder — avoids importing dart:convert publicly.
  final b = StringBuffer();
  _writeValue(b, map);
  return b.toString();
}
```

> **Design decision required (see Self-Review):** `path_provider` dependency. Options: (a) add `path_provider` to `dependencies` — cleanest but adds a dep, (b) use `Directory.systemTemp` — no new dep but path may not survive app restarts on all platforms, (c) make the directory configurable via `exportToFile({Directory? directory})` — most flexible, no dep.

**Commit message:** `feat(detector): add LeakRadar.exportToFile() with json/markdown formats`

---

### Task 6.2 — Share button in LeakRadarScreen

**Files to touch:**
- `lib/src/ui/leak_radar_screen.dart`
- `packages/flutter_leak_radar/pubspec.yaml` (add `share_plus`)
- `test/ui/leak_radar_screen_test.dart` (extend)

**Failing test (write first):**

```dart
// test/ui/leak_radar_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/ui/leak_radar_screen.dart';
import 'package:flutter_leak_radar/src/leak_radar.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';

void main() {
  setUp(() async {
    await LeakRadar.debugInstall(
      LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ),
    );
  });
  tearDown(LeakRadar.dispose);

  group('LeakRadarScreen', () {
    testWidgets('shows Export and Share action buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LeakRadarScreen()),
      );
      await tester.pump();
      expect(find.byTooltip('Export'), findsOneWidget);
      expect(find.byTooltip('Share'), findsOneWidget);
    });

    testWidgets('Export button calls exportToFile and shows snackbar', (tester) async {
      // Perform a scan first so latest is non-null.
      await LeakRadar.scan();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LeakRadarScreen())),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();

      // A snackbar should appear with the file path.
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('empty state is shown when no findings', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LeakRadarScreen()),
      );
      await tester.pump();
      expect(find.text('No leaks detected'), findsOneWidget);
    });

    testWidgets('reports stream updates UI without full rebuild', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LeakRadarScreen()),
      );
      await tester.pump();

      // Trigger a scan via the button.
      await tester.tap(find.byTooltip('Scan now'));
      await tester.pumpAndSettle();

      // No exception should occur.
      expect(tester.takeException(), isNull);
    });
  });
}
```

**Implementation notes:**

```dart
// lib/src/ui/leak_radar_screen.dart — updated AppBar actions

import 'package:share_plus/share_plus.dart'; // ONLY here in the UI layer

// In _LeakRadarScreenState, add:
Future<void> _export() async {
  final path = await LeakRadar.exportToFile(format: LeakExportFormat.markdown);
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(path != null ? 'Exported: $path' : 'Export failed'),
    ),
  );
}

Future<void> _share() async {
  final path = await LeakRadar.exportToFile(format: LeakExportFormat.markdown);
  if (!mounted || path == null) return;
  await SharePlus.instance.shareXFiles([XFile(path)], text: 'Leak Radar report');
}

// In AppBar.actions, add alongside existing Scan action:
IconButton(
  tooltip: 'Export',
  icon: const Icon(Icons.download),
  onPressed: _scanning ? null : _export,
),
IconButton(
  tooltip: 'Share',
  icon: const Icon(Icons.share),
  onPressed: _scanning ? null : _share,
),
```

```yaml
# packages/flutter_leak_radar/pubspec.yaml — add to dependencies:
  share_plus: ^10.0.0
```

**Commit message:** `feat(ui): add Export and Share buttons to LeakRadarScreen via share_plus`

---

## Self-Review

### Coverage of all deferred items

- [x] `AutoScan` config class with `onNavigation`, `period`, `navigationDebounce` → Task 2.1
- [x] `AutoScan` wired into `LeakRadarConfig`/`init` → Tasks 2.1, 2.3
- [x] `ScanScheduler` (periodic `Timer`) → Task 2.2
- [x] `LeakRadarNavigatorObserver` (debounced scan on `didPop`) → Task 3.1
- [x] `LeakRadar.navigatorObserver` exposed on facade → Task 3.2
- [x] `LeakRadarOverlay` draggable badge → Task 4.1
- [x] `LeakRadar.overlay({required child})` → Task 4.2
- [x] `GrowthSparkline` CustomPainter over `LeakFinding.series` → Task 5.1
- [x] Lazy retaining-path expansion tile → Task 5.2
- [x] `LeakRadar.exportToFile({format})` → Task 6.1
- [x] Share button using `share_plus` (UI-layer only) → Task 6.2
- [x] VmHeapProbe: cache name→ClassRef → Task 1.1
- [x] VmHeapProbe: `parentMapKey` cast fix → Task 1.2
- [x] VmHeapProbe: wire/enforce `maxRetainingPathRequests` → Task 1.3
- [x] VmHeapProbe: reconnect-latch recovery → Task 1.4

### All tasks have tests

- [x] Every task has at least one failing test written before implementation code.
- [x] Tests follow AAA structure.
- [x] Widget tests use `testWidgets`; pure logic tests use `test`.
- [x] `GrowthSparkline` includes a golden file test.

### Global constraints verified

- [x] No `package:vm_service` import outside `VmHeapProbe` — new files (`scan_scheduler.dart`, `navigator_observer.dart`, `leak_radar_overlay.dart`, `growth_sparkline.dart`, `retaining_path_tile.dart`) import none.
- [x] `share_plus` imported only in `leak_radar_screen.dart` — no other file references it.
- [x] All facade methods (`overlay`, `navigatorObserver`, `exportToFile`) wrapped in `runSafely`/`runSafelyAsync`.
- [x] `kEngineEnabled` checked in all new facade methods before any non-trivial work.
- [x] No `print()` — `_logger.log(...)` and `debugPrint` inside `kDebugMode` only.
- [x] All new value types (`AutoScan`) have `==`, `hashCode`, `copyWith`.
- [x] No `freezed`, no code-gen.

### Potential regressions to watch

- `LeakRadarConfig` gains two new fields (`autoScan`, `maxRetainingPathRequests`). The existing `==`/`hashCode` implementations must be updated in Task 2.1 or the engine equality checks will silently ignore them.
- The `_connectFailed` bool replacement in Task 1.4 changes the reconnect semantics — ensure the existing `VmHeapProbe` integration test still passes after the backoff timer is wired in.
- The existing `_FindingTile` in `leak_radar_screen.dart` is replaced in Task 5.2; any existing widget tests for `_FindingTile` must be updated to the new `Card`-based structure.

---

## Open Design Questions (human must decide before building)

1. **`exportToFile` path provider strategy (Task 6.1).** Three options:
   - (a) Add `path_provider` as a new dependency (cleanest, but widens dep surface).
   - (b) Use `Directory.systemTemp` (no new dep, but not documented as stable on all Flutter platforms).
   - (c) Make `exportToFile({Directory? directory})` accept an explicit directory (most flexible, no dep, caller provides their `getApplicationDocumentsDirectory()` result).
   **Recommendation:** (c) is the cleanest for a library package; (a) is fine if operator ergonomics matter more.

2. **`share_plus` version pin (Task 6.2).** `share_plus: ^10.0.0` is assumed. Confirm the repo's minimum supported Flutter version (3.38) is compatible with share_plus 10.x before merging. Also verify whether the `SharePlus.instance.shareXFiles` API matches the version you pin.

3. **Overlay position persistence (Task 4.1).** Current plan is session-only (in-state `_right`/`_bottom`). The spec lists this as an open question. Decision: session-only (no new dep) vs. persisted to `SharedPreferences` (new dep). Plan implements session-only.

4. **`showOverlay` field on `LeakRadarConfig` (Task 4.2).** The spec references `showOverlay` but the existing `LeakRadarConfig` in the code does not yet have it. Task 4.2 adds it. Confirm the field name and default (`true`) before building.

5. **`_classRefCache` invalidation on reconnect (Task 1.4).** Task 1.4 clears the cache on socket disconnect (`_classRefCache.clear()`). If the reconnect happens mid-session, a new `capture()` will repopulate the cache. This is correct but means the first `retainingPath()` call after a reconnect will fall through to the cold path. Acceptable? (Yes per spec — "reconnect lazily on the next scan".)

6. **Test isolation for `LeakRadar` static state.** The facade uses static fields (`_engine`, `_showOverlay`). Tests that call `LeakRadar.debugInstall()`/`dispose()` must be wrapped in `setUp`/`tearDown` to prevent state leakage. Consider adding a `LeakRadar.debugReset()` helper that clears all static fields, callable from `tearDown`.

---

## Execution Handoff

**Prerequisite:** Confirm `feat/runtime-mvp` is merged and CI is green (54 tests, `flutter analyze` clean) before starting this plan. Create a new branch: `feat/runtime-followup`.

**Order is strict within a milestone; milestones 1–3 may be started in parallel by separate agents, but Milestone 4 requires Milestone 3 (for `navigatorObserver`), and Milestones 5–6 require Milestone 1 (`retainingPath` fixes).**

Suggested agent dispatch for a parallelized session:
- **Agent A:** Milestones 1 + 5.2 (VmHeapProbe fixes → then RetainingPathTile)
- **Agent B:** Milestones 2 + 3 (AutoScan/ScanScheduler → NavigatorObserver)
- **Agent C:** Milestones 4 + 5.1 (Overlay → Sparkline) — can start immediately, no dependencies
- **Agent D:** Milestone 6 (Export/Share) — needs Task 6.1's `LeakEngine.fetchRetainingPath` which requires `LeakEngine` to exist, so starts after Agent B finishes Milestone 2

After all milestones: run `melos run ci` (format + analyze + test) and `melos run custom_lint`. Resolve the path_provider question (open question #1) before Task 6.1 is merged. Update `CHANGELOG.md` with a `## 0.1.0` entry covering the full feature set, and update `lib/flutter_leak_radar.dart` exports to include `AutoScan`, `LeakExportFormat`, and `LeakRadarOverlay`.
