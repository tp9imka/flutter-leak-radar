# radar_workbench Extraction — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a new host-agnostic `radar_workbench` package out of `flutter_leak_radar_devtools` (models + memory/perf/stability views + controllers + interfaces), and reduce the DevTools extension to a thin shell of adapters — with **no user-visible change** and all existing tests still green.

**Architecture:** The DevTools extension today owns everything. We introduce four interfaces (`RadarConnection`, `SnapshotSource`, `SnapshotExporter`, plus the already-existing `SnapshotStore`) and a web-safe `SnapshotAnalyzer`, move all host-agnostic code into `radar_workbench` (preserving the folder layout so relative imports keep working), refactor five "ADAPT" files onto the interfaces, and leave DevTools-specific glue (`serviceManager`, DTD, `web` download) behind three thin adapters. Because `radar_workbench` has no web-interop dependency, its tests run on the plain Dart VM — the migrated tests move off the `--platform chrome` requirement.

**Tech Stack:** Dart 3.10 / Flutter 3.38, pub workspace + Melos, `leak_graph` (pure analysis), `radar_ui` (design system), `vm_service`, `flutter_test`.

## Global Constraints

- SDK floor `>=3.10.0 <4.0.0`; Flutter floor `>=3.38.0` (copy verbatim from `radar_ui/pubspec.yaml`).
- Every package uses `resolution: workspace`.
- Analysis is strict: `dart analyze --fatal-infos` must pass (Melos `analyze` runs `dart analyze --fatal-infos`; CI fails on infos). `radar_workbench` gets its own `analysis_options.yaml` mirroring `radar_ui`'s (`include: package:flutter_lints/flutter.yaml` + `strict-casts`/`strict-inference`/`strict-raw-types`).
- Formatting must pass `dart format --set-exit-if-changed .` — run `dart format .` before every commit.
- `radar_workbench` MUST NOT depend on `devtools_extensions`, `devtools_app_shared`, `dtd`, `package:web`, or `dart:io`/`dart:js_interop` — it must stay web-compilable for the DevTools extension.
- `radar_workbench` deps: `flutter`, `leak_graph: ^0.2.2`, `radar_ui: ^0.1.1`, `vm_service: ^15.0.0`. Dev: `flutter_test`, `flutter_lints: ^5.0.0`. `version: 0.1.0`, `publish_to: none`.
- DevTools extension tests run with `flutter test --platform chrome` (web-interop). `radar_workbench` tests run with `flutter test` (VM).
- Preserve the existing subfolder layout on move (`capture/`, `filter/`, `memory/`, `perf/`, `stability/`, `presentation/`, `session/`, `shell/`) so relative imports survive; add a new `core/` folder for interfaces.
- Comment density stays minimal — do not add narration comments to moved code; keep the doc comments that already exist.
- Use `git mv` for moves (preserve history). Commit after every task.

---

## File Structure

**New package `packages/radar_workbench/`:**

```
pubspec.yaml                         # new
analysis_options.yaml                # new (mirror radar_ui)
lib/radar_workbench.dart             # new barrel
lib/src/core/radar_connection.dart   # NEW interface + RadarConnectionState/RadarConnectionPhase
lib/src/core/snapshot_source.dart    # NEW interface
lib/src/core/snapshot_exporter.dart  # NEW interface
lib/src/capture/snapshot_bundle.dart # MOVE (+ .failed factory)
lib/src/capture/snapshot_analyzer.dart # NEW (web-safe fromBytes/fromGraph)
lib/src/filter/…                     # MOVE (filter_expression, filter_bar)
lib/src/memory/…                     # MOVE (controller + views + helpers)
lib/src/perf/…                       # MOVE (controller + dto + views)
lib/src/stability/…                  # MOVE (errors_view, stalls_view)
lib/src/presentation/…               # MOVE (main_scaffold, retaining_path_tile)
lib/src/session/…                    # MOVE (snapshot_store, session_persistence, radar_session)
lib/src/shell/…                      # MOVE (radar_view, left_rail, connection_bar)
test/…                               # migrated from devtools
```

**`packages/flutter_leak_radar_devtools/` after refactor:**

```
lib/main.dart                                   # STAY (unchanged)
lib/src/app.dart                                # ADAPT (build adapters + install session)
lib/src/adapters/devtools_radar_connection.dart # NEW
lib/src/adapters/devtools_snapshot_source.dart   # NEW
lib/src/adapters/devtools_snapshot_exporter.dart # NEW
lib/src/adapters/devtools_perf_call.dart         # NEW (serviceManager callExtension)
lib/src/connection/connection_state_notifier.dart # STAY
lib/src/session/dtd_snapshot_store.dart          # STAY
lib/src/util/web_download.dart                   # STAY
pubspec.yaml                                     # add radar_workbench dep; bump 0.3.0
test/…                                           # adapter/smoke tests only (rest migrated)
```

**ADAPT files (the only moved files that change beyond location):** `memory_controller.dart`, `snapshots_view.dart`, `shell/connection_bar.dart`, `perf/perf_data_controller.dart`, `session/radar_session.dart`. All other moves are pure `git mv` (relative imports are structure-preserved).

---

## Task 1: Scaffold `radar_workbench` + workspace wiring

**Files:**
- Create: `packages/radar_workbench/pubspec.yaml`
- Create: `packages/radar_workbench/analysis_options.yaml`
- Create: `packages/radar_workbench/lib/radar_workbench.dart`
- Create: `packages/radar_workbench/test/scaffold_test.dart`
- Modify: `pubspec.yaml` (repo root — add to `workspace:` list)

**Interfaces:**
- Produces: an empty but resolvable `radar_workbench` package on the workspace.

- [ ] **Step 1: Create the pubspec**

`packages/radar_workbench/pubspec.yaml`:
```yaml
name: radar_workbench
description: >-
  Host-agnostic analysis workbench for the Radar suite: heap snapshot models,
  the memory/performance/stability views, and the controllers and interfaces the
  DevTools extension and the desktop app both build on.
version: 0.1.0
publish_to: none
repository: https://github.com/tp9imka/flutter-leak-radar

environment:
  sdk: ">=3.10.0 <4.0.0"
  flutter: ">=3.38.0"

resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  leak_graph: ^0.2.2
  radar_ui: ^0.1.1
  vm_service: ^15.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 2: Create analysis_options mirroring radar_ui**

`packages/radar_workbench/analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

- [ ] **Step 3: Create the (temporarily minimal) barrel**

`packages/radar_workbench/lib/radar_workbench.dart`:
```dart
/// Host-agnostic Radar analysis workbench: models, views, controllers, and the
/// interfaces the DevTools extension and the desktop app both build on.
library;
// Exports are added incrementally as each task lands.
```

- [ ] **Step 4: Add the package to the workspace**

In the repo-root `pubspec.yaml`, add `- packages/radar_workbench` to the `workspace:` list (place it after `packages/flutter_leak_radar_devtools`):
```yaml
workspace:
  - packages/flutter_leak_radar
  - packages/flutter_leak_radar_lint
  - packages/flutter_leak_radar_lint/example
  - packages/leak_graph
  - packages/radar_trace
  - packages/flutter_perf_radar
  - packages/flutter_leak_radar_devtools
  - packages/radar_workbench
  - packages/radarscope
  - packages/radar_ui
```

- [ ] **Step 5: Write a trivial test so the package has a green suite**

`packages/radar_workbench/test/scaffold_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('radar_workbench package resolves', () {
    expect(1 + 1, 2);
  });
}
```

- [ ] **Step 6: Resolve the workspace and run the test**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart pub get`
Expected: resolves without error (radar_workbench recognised as a workspace member).

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test`
Expected: PASS (1 test).

If `dart pub get` complains that `flutter_leak_radar_devtools` cannot depend on a `publish_to: none` package — it does not yet; that dependency is added in Task 10. If any *other* resolution error mentions `radar_workbench`, fall back to leaving the dep out until Task 10 (it is not needed before then).

- [ ] **Step 7: Format and commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add packages/radar_workbench pubspec.yaml
git commit -m "feat(radar_workbench): scaffold host-agnostic workbench package"
```

---

## Task 2: Move pure models, filter, formatters (no code change)

Pure leaf files with no host coupling. `git mv` preserves their relative imports (the subfolder layout is identical in the destination). Only `snapshot_bundle.dart` gains a `.failed` factory (Task 4 needs it), which is additive.

**Files:**
- Move: `capture/snapshot_bundle.dart`, `perf/perf_snapshot_dto.dart`, `filter/filter_expression.dart`, `filter/filter_bar.dart`, `memory/filter_target.dart`, `memory/mem_format.dart`, `memory/root_kind_ui.dart`, `memory/sort_header_cell.dart`, `memory/memory_view.dart`, `shell/radar_view.dart`, `presentation/retaining_path_tile.dart` → same relative paths under `radar_workbench/lib/src/`.
- Move test: `test/filter_expression_test.dart` → `radar_workbench/test/filter_expression_test.dart`.
- Modify: `capture/snapshot_bundle.dart` (add `.failed` factory), `lib/radar_workbench.dart` (barrel).

**Interfaces:**
- Produces: `SnapshotBundle` (with `SnapshotBundle.failed({required String label, required String message, DateTime? capturedAt})`), `PerfSnapshotDto`/`TraceKeyDto`/`FramesDto`/`StabilityDto`, `FilterExpression`/`FilterTarget`/`FilterChipData`, `FilterBar`, `ClassRow`, `fmtBytes`/`fmtTime`/`libraryLabel`, `RootBucket`/`RootBucketUi`/`RootDot`, `SortHeaderCell`, `MemoryView`, `RadarView`, `RetainingPathTile` — all under `package:radar_workbench/…`.

- [ ] **Step 1: Move the files with git**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
D=packages/flutter_leak_radar_devtools/lib/src
W=packages/radar_workbench/lib/src
mkdir -p $W/capture $W/perf $W/filter $W/memory $W/shell $W/presentation
git mv $D/capture/snapshot_bundle.dart      $W/capture/snapshot_bundle.dart
git mv $D/perf/perf_snapshot_dto.dart       $W/perf/perf_snapshot_dto.dart
git mv $D/filter/filter_expression.dart     $W/filter/filter_expression.dart
git mv $D/filter/filter_bar.dart            $W/filter/filter_bar.dart
git mv $D/memory/filter_target.dart         $W/memory/filter_target.dart
git mv $D/memory/mem_format.dart            $W/memory/mem_format.dart
git mv $D/memory/root_kind_ui.dart          $W/memory/root_kind_ui.dart
git mv $D/memory/sort_header_cell.dart      $W/memory/sort_header_cell.dart
git mv $D/memory/memory_view.dart           $W/memory/memory_view.dart
git mv $D/shell/radar_view.dart             $W/shell/radar_view.dart
git mv $D/presentation/retaining_path_tile.dart $W/presentation/retaining_path_tile.dart
git mv packages/flutter_leak_radar_devtools/test/filter_expression_test.dart \
       packages/radar_workbench/test/filter_expression_test.dart
```

- [ ] **Step 2: Add the `.failed` factory to `snapshot_bundle.dart`**

In `packages/radar_workbench/lib/src/capture/snapshot_bundle.dart`, add this factory inside the `SnapshotBundle` class, immediately after the existing `factory SnapshotBundle.fromJson(...)`:
```dart
  /// Builds a bundle representing a failed capture/analysis: empty histogram,
  /// empty clusters, and a single warning carrying [message]. Never throws.
  factory SnapshotBundle.failed({
    required String label,
    required String message,
    DateTime? capturedAt,
  }) => SnapshotBundle(
    capturedAt: capturedAt ?? DateTime.now(),
    label: label,
    histogram: const [],
    analysisResult: GraphAnalysisResult(
      clusters: const [],
      stats: GraphAnalysisStats(
        totalObjects: 0,
        reachableObjects: 0,
        leakCandidates: 0,
        clusters: 0,
        suppressedByAppFilter: 0,
        warnings: [message],
      ),
    ),
  );
```

- [ ] **Step 3: Fix the migrated test's import package**

In `packages/radar_workbench/test/filter_expression_test.dart`, change the two devtools imports from:
```dart
import 'package:flutter_leak_radar_devtools/src/filter/filter_bar.dart';
import 'package:flutter_leak_radar_devtools/src/filter/filter_expression.dart';
```
to:
```dart
import 'package:radar_workbench/src/filter/filter_bar.dart';
import 'package:radar_workbench/src/filter/filter_expression.dart';
```

- [ ] **Step 4: Export from the barrel**

Replace the placeholder comment in `packages/radar_workbench/lib/radar_workbench.dart` with:
```dart
export 'src/capture/snapshot_bundle.dart';
export 'src/filter/filter_bar.dart';
export 'src/filter/filter_expression.dart';
export 'src/memory/filter_target.dart';
export 'src/memory/mem_format.dart';
export 'src/memory/memory_view.dart';
export 'src/memory/root_kind_ui.dart';
export 'src/memory/sort_header_cell.dart';
export 'src/perf/perf_snapshot_dto.dart';
export 'src/presentation/retaining_path_tile.dart';
export 'src/shell/radar_view.dart';
```

- [ ] **Step 5: Run the migrated test on the VM**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test test/filter_expression_test.dart`
Expected: PASS (all `filter_expression_test` groups green — no `--platform chrome` needed).

- [ ] **Step 6: Analyze both packages**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && dart analyze --fatal-infos .`
Expected: `No issues found!`

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/flutter_leak_radar_devtools && dart analyze --fatal-infos .`
Expected: errors ONLY for files that still import the just-moved files (e.g. `class_histogram_view.dart`, `snapshots_view.dart`). These are fixed as those files move in later tasks — record them but do not fix here. If any error is in a file NOT scheduled to move (per the File Structure), stop and investigate.

- [ ] **Step 7: Format and commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "refactor(radar_workbench): move pure models, filter, formatters"
```

---

## Task 3: Core interfaces + session persistence + store

**Files:**
- Create: `packages/radar_workbench/lib/src/core/radar_connection.dart`
- Create: `packages/radar_workbench/lib/src/core/snapshot_source.dart`
- Create: `packages/radar_workbench/lib/src/core/snapshot_exporter.dart`
- Move: `session/snapshot_store.dart` → `radar_workbench/lib/src/session/snapshot_store.dart` (self-contained; `session_persistence.dart` moves in Task 5 with `memory_controller`, on which it depends)
- Create: `packages/radar_workbench/test/fakes.dart` (shared test doubles)
- Test: `packages/radar_workbench/test/core_test.dart`
- Modify: `lib/radar_workbench.dart` (barrel)

**Interfaces:**
- Consumes: `SnapshotBundle` (Task 2), `RadarView` (Task 2).
- Produces:
  - `enum RadarConnectionPhase { connecting, connected, disconnected }`
  - `class RadarConnectionState { RadarConnectionPhase phase; String? vmName; String? isolateName; }`
  - `abstract interface class RadarConnection implements Listenable { RadarConnectionState get state; VmService? get vmService; IsolateRef? get isolateRef; }`
  - `abstract interface class SnapshotSource { Future<SnapshotBundle> capture({String label}); }`
  - `abstract interface class SnapshotExporter { Future<void> export(SnapshotBundle bundle, {String? suggestedName}); }`
  - Moved `SnapshotStore`/`PersistedSession`/`InMemorySnapshotStore` (`SessionPersistence` moves in Task 5).
  - Test doubles `FakeRadarConnection`, `FakeSnapshotSource`, `RecordingExporter`.

- [ ] **Step 1: Create `radar_connection.dart`**

`packages/radar_workbench/lib/src/core/radar_connection.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

/// Phase of a host's connection to a target app's VM service.
enum RadarConnectionPhase { connecting, connected, disconnected }

/// Immutable snapshot of a [RadarConnection]'s state.
@immutable
final class RadarConnectionState {
  const RadarConnectionState({required this.phase, this.vmName, this.isolateName});
  final RadarConnectionPhase phase;
  final String? vmName;
  final String? isolateName;
}

/// The single seam between a host (DevTools / desktop) and the workbench.
///
/// Exposes the live [vmService] + main [isolateRef] handles that capture and
/// service-extension calls need, and notifies listeners on connect/disconnect.
/// Implementations: `DevToolsRadarConnection` (over serviceManager) and the
/// desktop's `VmServiceUriConnection` (over a direct ws:// client).
abstract interface class RadarConnection implements Listenable {
  RadarConnectionState get state;
  VmService? get vmService;
  IsolateRef? get isolateRef;
}
```

- [ ] **Step 2: Create `snapshot_source.dart` and `snapshot_exporter.dart`**

`packages/radar_workbench/lib/src/core/snapshot_source.dart`:
```dart
import '../capture/snapshot_bundle.dart';

/// Produces a fully-analyzed [SnapshotBundle] from a live connection.
///
/// File import is NOT a [SnapshotSource] — it lives host-side and feeds
/// [SnapshotAnalyzer.fromBytes] directly. Implementations never throw; they
/// return a bundle carrying an error result on failure.
abstract interface class SnapshotSource {
  Future<SnapshotBundle> capture({String label = ''});
}
```

`packages/radar_workbench/lib/src/core/snapshot_exporter.dart`:
```dart
import '../capture/snapshot_bundle.dart';

/// Writes a [SnapshotBundle] out of the app: a browser download in DevTools,
/// a native save dialog on desktop.
abstract interface class SnapshotExporter {
  Future<void> export(SnapshotBundle bundle, {String? suggestedName});
}
```

- [ ] **Step 3: Move the session store**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
D=packages/flutter_leak_radar_devtools/lib/src
W=packages/radar_workbench/lib/src
mkdir -p $W/session
git mv $D/session/snapshot_store.dart $W/session/snapshot_store.dart
```
No content change: its relative imports (`../capture/snapshot_bundle.dart`, `../shell/radar_view.dart`) already resolve inside `radar_workbench`. `session_persistence.dart` is intentionally left in the DevTools package until Task 5 (it imports `../memory/memory_controller.dart`, which moves then) so the workbench stays analyze-clean at each intervening gate.

- [ ] **Step 4: Create shared test doubles**

`packages/radar_workbench/test/fakes.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// A [RadarConnection] whose state is driven directly by the test.
class FakeRadarConnection extends ChangeNotifier implements RadarConnection {
  FakeRadarConnection({
    RadarConnectionState state = const RadarConnectionState(
      phase: RadarConnectionPhase.disconnected,
    ),
    VmService? vmService,
    IsolateRef? isolateRef,
  }) : _state = state,
       _vmService = vmService,
       _isolateRef = isolateRef;

  RadarConnectionState _state;
  VmService? _vmService;
  IsolateRef? _isolateRef;

  @override
  RadarConnectionState get state => _state;
  @override
  VmService? get vmService => _vmService;
  @override
  IsolateRef? get isolateRef => _isolateRef;

  /// Test hook: mutate the connection and notify listeners.
  void set({
    RadarConnectionState? state,
    VmService? vmService,
    IsolateRef? isolateRef,
  }) {
    if (state != null) _state = state;
    _vmService = vmService;
    _isolateRef = isolateRef;
    notifyListeners();
  }
}

/// A [SnapshotSource] that returns queued bundles (or a failure).
class FakeSnapshotSource implements SnapshotSource {
  FakeSnapshotSource([this._next]);
  SnapshotBundle? _next;
  int captureCount = 0;

  void queue(SnapshotBundle bundle) => _next = bundle;

  @override
  Future<SnapshotBundle> capture({String label = ''}) async {
    captureCount++;
    return _next ?? SnapshotBundle.failed(label: label, message: 'no bundle queued');
  }
}

/// A [SnapshotExporter] that records what it was asked to export.
class RecordingExporter implements SnapshotExporter {
  final List<SnapshotBundle> exported = [];
  @override
  Future<void> export(SnapshotBundle bundle, {String? suggestedName}) async {
    exported.add(bundle);
  }
}
```

- [ ] **Step 5: Write the interface test**

`packages/radar_workbench/test/core_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

void main() {
  test('FakeRadarConnection notifies and exposes state', () {
    final conn = FakeRadarConnection();
    var notified = 0;
    conn.addListener(() => notified++);
    expect(conn.state.phase, RadarConnectionPhase.disconnected);
    conn.set(
      state: const RadarConnectionState(phase: RadarConnectionPhase.connected),
    );
    expect(notified, 1);
    expect(conn.state.phase, RadarConnectionPhase.connected);
  });

  test('RecordingExporter records exports', () async {
    final exporter = RecordingExporter();
    final bundle = SnapshotBundle.failed(label: 'x', message: 'm');
    await exporter.export(bundle);
    expect(exporter.exported.single.label, 'x');
  });
}
```

- [ ] **Step 6: Export interfaces from the barrel**

Add to `packages/radar_workbench/lib/radar_workbench.dart`:
```dart
export 'src/core/radar_connection.dart';
export 'src/core/snapshot_source.dart';
export 'src/core/snapshot_exporter.dart';
export 'src/session/snapshot_store.dart';
```
(`session_persistence` is exported in Task 5, once `memory_controller` — which it imports — has moved.)

- [ ] **Step 7: Run the test**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test test/core_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 8: Format and commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "feat(radar_workbench): core interfaces + session store/persistence"
```

---

## Task 4: `SnapshotAnalyzer` (web-safe, isolate-backed)

Extract the analysis half of the old `SnapshotService` into a host-agnostic analyzer that both hosts (and file import) share. The VM-service capture half becomes the DevTools adapter in Task 9.

**Files:**
- Create: `packages/radar_workbench/lib/src/capture/snapshot_analyzer.dart`
- Test: `packages/radar_workbench/test/snapshot_analyzer_test.dart`
- Modify: `lib/radar_workbench.dart` (barrel)

**Interfaces:**
- Consumes: `SnapshotBundle` (+ `.failed`), `leak_graph` (`heapGraphFromBytes`, `HeapGraphView`, `GraphLeakAnalyzer`, `GraphAnalysisOptions`, `GraphAnalysisResult`, `ClassCount`).
- Produces:
  - `class SnapshotAnalyzer { const SnapshotAnalyzer({GraphAnalysisOptions options}); Future<SnapshotBundle> fromGraph(HeapGraphView graph, {String label}); Future<SnapshotBundle> fromBytes(Uint8List bytes, {String label}); }`

- [ ] **Step 1: Write the failing test**

`packages/radar_workbench/test/snapshot_analyzer_test.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  test('fromBytes on garbage completes without throwing and yields empty analysis', () async {
    const analyzer = SnapshotAnalyzer();
    final bundle = await analyzer.fromBytes(
      Uint8List.fromList([0, 1, 2, 3, 4]),
      label: 'garbage',
    );
    expect(bundle.label, 'garbage');
    expect(bundle.analysisResult.clusters, isEmpty);
    expect(bundle.histogram, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test test/snapshot_analyzer_test.dart`
Expected: FAIL — `SnapshotAnalyzer` is not defined.

- [ ] **Step 3: Implement the analyzer**

`packages/radar_workbench/lib/src/capture/snapshot_analyzer.dart`:
```dart
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:leak_graph/leak_graph.dart';

import 'snapshot_bundle.dart';

/// Parses and analyzes heap snapshots off the UI thread, host-agnostically.
///
/// `fromGraph` analyzes an already-parsed graph (the live-capture path);
/// `fromBytes` parses raw `dartheap` bytes and analyzes them entirely inside
/// the background isolate (the file-import path — the graph never touches the
/// main isolate, which matters for large desktop dumps).
///
/// Uses [compute], which runs on a real isolate on native and a web worker /
/// main thread on web, so a single implementation serves both hosts. Never
/// throws — analysis failures return a [SnapshotBundle.failed].
class SnapshotAnalyzer {
  const SnapshotAnalyzer({this.options = const GraphAnalysisOptions()});

  static const _log = 'radarWorkbench.analyzer';

  final GraphAnalysisOptions options;

  Future<SnapshotBundle> fromGraph(HeapGraphView graph, {String label = ''}) async {
    final capturedAt = DateTime.now();
    try {
      final histogram = graph.classHistogram();
      final result = await compute(_analyzeGraph, (graph, options));
      return SnapshotBundle(
        capturedAt: capturedAt,
        label: label,
        histogram: histogram,
        analysisResult: result,
      );
    } catch (e, s) {
      developer.log('fromGraph failed', name: _log, error: e, stackTrace: s);
      return SnapshotBundle.failed(
        capturedAt: capturedAt,
        label: label,
        message: 'Analysis failed — see console for details.',
      );
    }
  }

  Future<SnapshotBundle> fromBytes(Uint8List bytes, {String label = ''}) async {
    final capturedAt = DateTime.now();
    try {
      final res = await compute(_analyzeBytes, (bytes, options));
      return SnapshotBundle(
        capturedAt: capturedAt,
        label: label,
        histogram: res.histogram,
        analysisResult: res.result,
      );
    } catch (e, s) {
      developer.log('fromBytes failed', name: _log, error: e, stackTrace: s);
      return SnapshotBundle.failed(
        capturedAt: capturedAt,
        label: label,
        message: 'Snapshot parse/analysis failed — see console for details.',
      );
    }
  }
}

// Top-level entry points required by [compute].

GraphAnalysisResult _analyzeGraph((HeapGraphView, GraphAnalysisOptions) req) =>
    const GraphLeakAnalyzer().analyze(req.$1, req.$2);

({List<ClassCount> histogram, GraphAnalysisResult result}) _analyzeBytes(
  (Uint8List, GraphAnalysisOptions) req,
) {
  final graph = heapGraphFromBytes(req.$1);
  return (
    histogram: graph.classHistogram(),
    result: const GraphLeakAnalyzer().analyze(graph, req.$2),
  );
}
```

- [ ] **Step 4: Export it**

Add to `packages/radar_workbench/lib/radar_workbench.dart`:
```dart
export 'src/capture/snapshot_analyzer.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test test/snapshot_analyzer_test.dart`
Expected: PASS.

If `compute` fails under `flutter test` with a sentinel/serialization error on the `(bytes, options)` record, the fallback is to run the parse+analyze synchronously when `kIsWeb == false && !kReleaseMode` is not the concern — but do NOT change the design; instead verify `GraphAnalysisOptions` is a const/value type (it is) and that the record args are sendable. The garbage-bytes test does not construct a real graph, so this should pass as written.

- [ ] **Step 6: Analyze + format + commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "feat(radar_workbench): web-safe SnapshotAnalyzer (fromBytes/fromGraph)"
```

---

## Task 5: Move + refactor `MemoryController` onto the interfaces

**Files:**
- Move+modify: `memory/memory_controller.dart` → `radar_workbench/lib/src/memory/memory_controller.dart`
- Move: `session/session_persistence.dart` → `radar_workbench/lib/src/session/session_persistence.dart` (clean move; its `../memory/memory_controller.dart` import now resolves)
- Test: `packages/radar_workbench/test/memory_controller_test.dart` (migrated from `shell_memory_test.dart`, MemoryController + Session-persistence groups)
- Modify: `lib/radar_workbench.dart` (barrel)

**Interfaces:**
- Consumes: `SnapshotSource`, `RadarConnection` (Task 3), `SnapshotBundle` (Task 2), `leak_graph` (`computeDiff`, `ClassCountDiff`).
- Produces: `class MemoryController extends ChangeNotifier` with constructor `MemoryController({required SnapshotSource snapshotSource, required RadarConnection connection})`; unchanged public surface (`snapshots`, `selectedIds`, `persistableSnapshots`, `capturing`, `error`, `canCapture`, `pair`/`focused`/`comparison`/`comparingAgainstEmpty`, `diff`, `capture`, `toggleSelection`, `remove`, `clearAll`, `rehydrate`, `forceGc`, `debugAdd`, `byId`).

- [ ] **Step 1: Move the controller and session_persistence**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
git mv packages/flutter_leak_radar_devtools/lib/src/memory/memory_controller.dart \
       packages/radar_workbench/lib/src/memory/memory_controller.dart
git mv packages/flutter_leak_radar_devtools/lib/src/session/session_persistence.dart \
       packages/radar_workbench/lib/src/session/session_persistence.dart
```
`session_persistence.dart` needs no content change — its imports (`../memory/memory_controller.dart`, `../shell/radar_view.dart`, `snapshot_store.dart`) now all resolve inside `radar_workbench`.

- [ ] **Step 2: Rewrite its imports and constructor**

In `packages/radar_workbench/lib/src/memory/memory_controller.dart`:

Replace the import block:
```dart
import '../capture/snapshot_bundle.dart';
import '../capture/snapshot_service.dart';
import '../connection/connection_state_notifier.dart';
import '../session/snapshot_store.dart';
```
with:
```dart
import '../capture/snapshot_bundle.dart';
import '../core/radar_connection.dart';
import '../core/snapshot_source.dart';
import '../session/snapshot_store.dart';
```

Replace the constructor + fields:
```dart
  MemoryController({
    required SnapshotService service,
    required ConnectionStateNotifier connection,
  }) : _service = service,
       _connection = connection {
    _connection.addListener(notifyListeners);
  }

  final SnapshotService _service;
  final ConnectionStateNotifier _connection;
```
with:
```dart
  MemoryController({
    required SnapshotSource snapshotSource,
    required RadarConnection connection,
  }) : _snapshotSource = snapshotSource,
       _connection = connection {
    _connection.addListener(notifyListeners);
  }

  final SnapshotSource _snapshotSource;
  final RadarConnection _connection;
```

Replace the capture call inside `Future<void> capture(...)`:
```dart
      final bundle = await _service.capture(
        vmService: _connection.vmService!,
        isolateRef: _connection.isolateRef!,
        label: label ?? 'Snapshot $id',
      );
```
with:
```dart
      final bundle = await _snapshotSource.capture(label: label ?? 'Snapshot $id');
```

Leave everything else (including `canCapture`, `forceGc` using `_connection.vmService`/`_connection.isolateRef`, and `getAllocationProfile(iso.id!, reset: true)`) unchanged.

- [ ] **Step 3: Migrate the MemoryController + Session-persistence tests**

Create `packages/radar_workbench/test/memory_controller_test.dart` by copying the `MemoryController` and `Session persistence` groups out of the old `packages/flutter_leak_radar_devtools/test/shell_memory_test.dart`. Use these imports (replacing the devtools `src/...` imports and the `ConnectionStateNotifier`/`SnapshotService` usage with the fakes):
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';
```
Construct the controller in these tests with:
```dart
final connection = FakeRadarConnection();
final controller = MemoryController(
  snapshotSource: FakeSnapshotSource(),
  connection: connection,
);
```
For the test `re-notifies its listeners when the VM connection changes`, drive the change via the fake:
```dart
connection.set(
  state: const RadarConnectionState(phase: RadarConnectionPhase.connected),
);
```
(The old test toggled a `ConnectionStateNotifier`; the fake's `set` is the direct equivalent and fires `notifyListeners`.) Keep every assertion identical. Populate snapshots via `controller.debugAdd(bundle)` exactly as the original did.

> Note: leave the old `shell_memory_test.dart` in place for now (it still references not-yet-moved views); Task 7 migrates the rest of it and Task 10 deletes the remainder.

- [ ] **Step 4: Export the controller + session_persistence**

Add to `packages/radar_workbench/lib/radar_workbench.dart`:
```dart
export 'src/memory/memory_controller.dart';
export 'src/session/session_persistence.dart';
```

- [ ] **Step 5: Run the migrated tests**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test test/memory_controller_test.dart`
Expected: PASS (all MemoryController + Session-persistence assertions green on the VM).

- [ ] **Step 6: Analyze + format + commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "refactor(radar_workbench): MemoryController onto SnapshotSource + RadarConnection"
```

---

## Task 6: Move + refactor `PerfDataController`

Drop the `serviceManager`-based default; replace it with a pure `_notConnected` default that reports the extension as unavailable. The real DevTools call implementation moves to the adapter in Task 9.

**Files:**
- Move+modify: `perf/perf_data_controller.dart` → `radar_workbench/lib/src/perf/perf_data_controller.dart`
- Move: the perf/stability view files (`frames_view.dart`, `traces_view.dart`, `perf_state_views.dart`, `../stability/errors_view.dart`, `../stability/stalls_view.dart`)
- Test: `packages/radar_workbench/test/perf_stability_test.dart` (migrated)
- Modify: `lib/radar_workbench.dart` (barrel)

**Interfaces:**
- Produces: `class PerfDataController extends ChangeNotifier` with `PerfDataController({Future<Map<String,Object?>> Function(String method)? callExtension})` (default → always throws `ExtensionNotAvailableException`); `ExtensionNotAvailableException`; unchanged `refresh`/`resetFrames`/`loadState`/`snapshot`/`errorMessage`. Views `FramesView`, `TracesView`, `ErrorsView`, `StallsView`, `PerfRadarNotDetectedView` et al.

- [ ] **Step 1: Move the controller + perf/stability views**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
D=packages/flutter_leak_radar_devtools/lib/src
W=packages/radar_workbench/lib/src
mkdir -p $W/stability
git mv $D/perf/perf_data_controller.dart $W/perf/perf_data_controller.dart
git mv $D/perf/frames_view.dart          $W/perf/frames_view.dart
git mv $D/perf/traces_view.dart          $W/perf/traces_view.dart
git mv $D/perf/perf_state_views.dart     $W/perf/perf_state_views.dart
git mv $D/stability/errors_view.dart     $W/stability/errors_view.dart
git mv $D/stability/stalls_view.dart     $W/stability/stalls_view.dart
```
The view files import only `perf_data_controller.dart`, `perf_snapshot_dto.dart`, `perf_state_views.dart`, and `radar_ui` — all resolved inside `radar_workbench`. No content change needed for the views.

- [ ] **Step 2: Refactor the controller — remove the DevTools default**

In `packages/radar_workbench/lib/src/perf/perf_data_controller.dart`:

Remove these two imports:
```dart
import 'dart:convert';
import 'package:devtools_extensions/devtools_extensions.dart';
```

Change the field initialiser default from `_defaultCallExtension` to `_notConnected`:
```dart
  PerfDataController({
    Future<Map<String, Object?>> Function(String method)? callExtension,
  }) : _callExtension = callExtension ?? _notConnected;
```

Delete the entire `static Future<Map<String, Object?>> _defaultCallExtension(...) async { … }` method and replace it with:
```dart
  /// Default when no host connection is wired: the extension is unavailable, so
  /// [refresh] transitions to [PerfLoadState.notAvailable] without any VM call.
  static Future<Map<String, Object?>> _notConnected(String method) async =>
      throw const ExtensionNotAvailableException();
```

Keep the `ExtensionNotAvailableException` class at the bottom of the file unchanged. (`dart:developer` stays — it is still used by `refresh`/`resetFrames` logging.)

- [ ] **Step 3: Migrate the perf/stability test**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
git mv packages/flutter_leak_radar_devtools/test/perf_stability_test.dart \
       packages/radar_workbench/test/perf_stability_test.dart
```
In `packages/radar_workbench/test/perf_stability_test.dart`, replace the six `package:flutter_leak_radar_devtools/src/...` imports with their `package:radar_workbench/src/...` equivalents (same relative paths). No test-body changes: the tests already inject `callExtension` fakes or use the no-arg constructor (whose default now yields `notAvailable`, which no existing test contradicts).

- [ ] **Step 4: Export**

Add to `packages/radar_workbench/lib/radar_workbench.dart`:
```dart
export 'src/perf/frames_view.dart';
export 'src/perf/perf_data_controller.dart';
export 'src/perf/perf_state_views.dart';
export 'src/perf/traces_view.dart';
export 'src/stability/errors_view.dart';
export 'src/stability/stalls_view.dart';
```

- [ ] **Step 5: Run the migrated test on the VM**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test test/perf_stability_test.dart`
Expected: PASS — all `PerfSnapshotDto`, `TraceKeyDto`, `TracesView`, `FramesView`, `ErrorsView`, `StallsView`, `PerfDataController` groups green on the VM (no chrome).

- [ ] **Step 6: Analyze + format + commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "refactor(radar_workbench): move perf/stability views + decouple PerfDataController"
```

---

## Task 7: Move remaining views (histogram, diff, snapshots, paths, detail, shell, scaffold)

**Files:**
- Move: `memory/class_histogram_view.dart`, `memory/diff_table.dart`, `memory/retaining_paths_view.dart`, `memory/class_detail_panel.dart`, `shell/left_rail.dart`, `presentation/main_scaffold.dart` (clean moves).
- Move+modify: `memory/snapshots_view.dart` (drop `web_download`, add `onExport`), `shell/connection_bar.dart` (bind `RadarConnection`).
- Test: migrate the remaining `shell_memory_test.dart` widget groups into `packages/radar_workbench/test/views_test.dart`.
- Modify: `lib/radar_workbench.dart` (barrel).

**Interfaces:**
- Consumes: `MemoryController`, `RadarConnection`, `RadarConnectionState`/`RadarConnectionPhase`, all Task 2/6 widgets.
- Produces: `ClassHistogramView`, `DiffTable`, `RetainingPathsView`, `ClassDetailPanel`, `LeftRail`, `LeakRadarMainScaffold`, `ConnectionBar({required RadarConnection connection})`, `SnapshotsView({required MemoryController controller, required void Function(SnapshotBundle) onExport})`.

- [ ] **Step 1: Move the clean view files**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
D=packages/flutter_leak_radar_devtools/lib/src
W=packages/radar_workbench/lib/src
git mv $D/memory/class_histogram_view.dart $W/memory/class_histogram_view.dart
git mv $D/memory/diff_table.dart           $W/memory/diff_table.dart
git mv $D/memory/retaining_paths_view.dart $W/memory/retaining_paths_view.dart
git mv $D/memory/class_detail_panel.dart   $W/memory/class_detail_panel.dart
git mv $D/shell/left_rail.dart             $W/shell/left_rail.dart
git mv $D/presentation/main_scaffold.dart  $W/presentation/main_scaffold.dart
git mv $D/memory/snapshots_view.dart       $W/memory/snapshots_view.dart
git mv $D/shell/connection_bar.dart        $W/shell/connection_bar.dart
```
`class_histogram_view`, `diff_table`, `retaining_paths_view`, `class_detail_panel`, `left_rail` need **no content change** (all their relative imports resolve inside `radar_workbench`). `main_scaffold` is edited in Step 4.

- [ ] **Step 2: Refactor `connection_bar.dart` onto `RadarConnection`**

In `packages/radar_workbench/lib/src/shell/connection_bar.dart`:

Replace the import:
```dart
import '../connection/connection_state_notifier.dart';
```
with:
```dart
import '../core/radar_connection.dart';
```

Change the widget's field + constructor from `ConnectionStateNotifier notifier` to `RadarConnection connection`:
```dart
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({super.key, required this.connection});

  final RadarConnection connection;
```
Then update the body: every read of `notifier` becomes `connection`, `notifier.state` yields a `RadarConnectionState`, and the phase enum is now `RadarConnectionPhase.connected` / `.connecting` / `.disconnected` (was `ExtensionConnectionPhase.*`). The `state.vmName` / `state.isolateName` fields are identical. If the bar listens via `AnimatedBuilder`/`ListenableBuilder`, pass `connection` as the animation/listenable (it implements `Listenable`).

- [ ] **Step 3: Refactor `snapshots_view.dart` to export via callback**

In `packages/radar_workbench/lib/src/memory/snapshots_view.dart`:

Remove the import:
```dart
import '../util/web_download.dart';
```

Add an `onExport` field to the widget and its constructor:
```dart
class SnapshotsView extends StatefulWidget {
  const SnapshotsView({
    super.key,
    required this.controller,
    required this.onExport,
  });

  final MemoryController controller;
  final void Function(SnapshotBundle bundle) onExport;
```
Find the existing call to `downloadJson('heap_${…}.json', bundle.toJson())` (in the export/download action handler) and replace it with:
```dart
      widget.onExport(bundle);
```
(The filename + JSON encoding now live in the exporter impl — Task 9.)

- [ ] **Step 4: Point `main_scaffold` at the injected exporter + connection**

In `packages/radar_workbench/lib/src/presentation/main_scaffold.dart`, the scaffold reads `RadarSession.instance` (moved in Task 8). Two wiring changes:
- Where it builds `SnapshotsView(controller: session.memory)`, add `onExport:`:
```dart
      SnapshotsView(
        controller: session.memory,
        onExport: (bundle) => session.exporter.export(bundle),
      ),
```
- Where it builds `ConnectionBar(notifier: session.connection)` (previously a `ConnectionStateNotifier`), it becomes `ConnectionBar(connection: session.connection)` (now a `RadarConnection`).

> `session.exporter` and `session.connection` (as `RadarConnection`) are defined by the Task 8 `RadarSession` refactor. If executing strictly in order, `main_scaffold` will not analyze clean until Task 8 lands — that is expected; do not add stopgaps.

- [ ] **Step 5: Migrate the remaining widget tests**

Create `packages/radar_workbench/test/views_test.dart` from the `ConnectionBar`, `LeftRail`, `SnapshotsView`, `ClassHistogramView`, and `RetainingPathsView` groups of the old `shell_memory_test.dart`. Imports:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';
```
Adaptations:
- `ConnectionBar` test: construct `ConnectionBar(connection: FakeRadarConnection())` (disconnected by default) — the "shows disconnected chip" assertion is unchanged.
- `SnapshotsView` tests: construct `SnapshotsView(controller: controller, onExport: (_) {})`; build the controller with `MemoryController(snapshotSource: FakeSnapshotSource(), connection: FakeRadarConnection())` and populate via `debugAdd`.
- `ClassHistogramView` / `RetainingPathsView` tests: unchanged except the controller construction above and the import package.
- `LeftRail` tests: unchanged except the import package.
Keep all assertions byte-for-byte identical.

- [ ] **Step 6: Export the views**

Add to `packages/radar_workbench/lib/radar_workbench.dart`:
```dart
export 'src/memory/class_detail_panel.dart';
export 'src/memory/class_histogram_view.dart';
export 'src/memory/diff_table.dart';
export 'src/memory/retaining_paths_view.dart';
export 'src/memory/snapshots_view.dart';
export 'src/shell/connection_bar.dart';
export 'src/shell/left_rail.dart';
```
(`main_scaffold` is NOT exported yet — it imports `radar_session`, which moves in Task 8. Exporting it here would pull an unresolved file into `views_test`'s barrel import. Its export is added in Task 8.)

- [ ] **Step 7: Run the migrated widget tests**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test test/views_test.dart`
Expected: PASS — all migrated widget groups green on the VM.

> This step depends on Task 8's `RadarSession` for `main_scaffold` to analyze; if running task-by-task, `views_test.dart` itself does not import `main_scaffold`, so it passes here, but `dart analyze` on the package will still flag `main_scaffold` until Task 8. Defer the package-wide analyze gate to Task 8, Step 5.

- [ ] **Step 8: Format + commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "refactor(radar_workbench): move remaining views; export via callback, bind RadarConnection"
```

---

## Task 8: Move + refactor `RadarSession` for host injection

**Files:**
- Move+modify: `session/radar_session.dart` → `radar_workbench/lib/src/session/radar_session.dart`
- Test: `packages/radar_workbench/test/radar_session_test.dart`
- Modify: `lib/radar_workbench.dart` (barrel)

**Interfaces:**
- Consumes: `RadarConnection`, `MemoryController`, `PerfDataController`, `SnapshotExporter`, `SnapshotStore`/`PersistedSession`, `SessionPersistence`, `RadarView`.
- Produces: `class RadarSession` with `RadarSession({required RadarConnection connection, required MemoryController memory, required PerfDataController perf, required SnapshotExporter exporter, VoidCallback? onInit})`, static `RadarSession install(RadarSession)` / `RadarSession get instance` / `@visibleForTesting debugReset()`, plus unchanged `currentView`, `ensureInitialized()`, `attachStore(...)`, `selectView(...)`.

- [ ] **Step 1: Move the file**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
git mv packages/flutter_leak_radar_devtools/lib/src/session/radar_session.dart \
       packages/radar_workbench/lib/src/session/radar_session.dart
```

- [ ] **Step 2: Rewrite it for injection**

Replace the entire body of `packages/radar_workbench/lib/src/session/radar_session.dart` with:
```dart
import 'package:flutter/foundation.dart';

import '../core/radar_connection.dart';
import '../core/snapshot_exporter.dart';
import '../memory/memory_controller.dart';
import '../perf/perf_data_controller.dart';
import '../shell/radar_view.dart';
import 'session_persistence.dart';
import 'snapshot_store.dart';

/// Process-wide holder for the workbench's controllers and view selection.
///
/// DevTools disposes and rebuilds the extension's Flutter tree on tab switches;
/// the desktop app keeps one session for the window's lifetime. Holding the
/// controllers here — not in a `State` — means captured snapshots, the diff
/// selection, and the active view survive rebuilds.
///
/// The host builds the concrete [connection]/[memory]/[perf]/[exporter] (over
/// serviceManager, a ws:// client, files, etc.) and calls [install] before the
/// UI reads [instance].
class RadarSession {
  RadarSession({
    required this.connection,
    required this.memory,
    required this.perf,
    required this.exporter,
    VoidCallback? onInit,
  }) : _onInit = onInit;

  final RadarConnection connection;
  final MemoryController memory;
  final PerfDataController perf;
  final SnapshotExporter exporter;
  final VoidCallback? _onInit;

  static RadarSession? _instance;

  /// The installed session. Throws if the host has not called [install].
  static RadarSession get instance =>
      _instance ??
      (throw StateError('RadarSession not installed. Call RadarSession.install().'));

  /// Installs [session] as the process-wide instance.
  static void install(RadarSession session) => _instance = session;

  @visibleForTesting
  static void debugReset() => _instance = null;

  /// Currently selected left-rail destination; persisted across rebuilds.
  RadarView currentView = RadarView.snapshotDiff;

  SessionPersistence? _persistence;
  bool _initialized = false;
  bool _storeAttached = false;

  /// Runs the host's one-time init (e.g. connection watching) once.
  void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _onInit?.call();
  }

  /// Attaches a durable [store]: restores any previously persisted session,
  /// then begins debounced persistence. Idempotent.
  Future<void> attachStore(
    SnapshotStore store, {
    void Function()? onRestored,
  }) async {
    if (_storeAttached) return;
    _storeAttached = true;
    final persistence = SessionPersistence(
      store: store,
      memory: memory,
      readView: () => currentView,
    );
    _persistence = persistence;
    final session = await persistence.load();
    if (session != null && session.bundles.isNotEmpty) {
      currentView = session.view;
      memory.rehydrate(session);
      onRestored?.call();
    }
    persistence.start();
  }

  /// Updates the active view and schedules a debounced persist.
  void selectView(RadarView view) {
    currentView = view;
    _persistence?.schedule();
  }
}
```

- [ ] **Step 3: Write the session test**

`packages/radar_workbench/test/radar_session_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

RadarSession _build() {
  final connection = FakeRadarConnection();
  return RadarSession(
    connection: connection,
    memory: MemoryController(
      snapshotSource: FakeSnapshotSource(),
      connection: connection,
    ),
    perf: PerfDataController(),
    exporter: RecordingExporter(),
  );
}

void main() {
  tearDown(RadarSession.debugReset);

  test('instance throws before install', () {
    expect(() => RadarSession.instance, throwsStateError);
  });

  test('install exposes the session', () {
    final s = _build();
    RadarSession.install(s);
    expect(identical(RadarSession.instance, s), isTrue);
  });

  test('ensureInitialized runs onInit exactly once', () {
    var calls = 0;
    final connection = FakeRadarConnection();
    final s = RadarSession(
      connection: connection,
      memory: MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: connection,
      ),
      perf: PerfDataController(),
      exporter: RecordingExporter(),
      onInit: () => calls++,
    );
    s.ensureInitialized();
    s.ensureInitialized();
    expect(calls, 1);
  });

  test('attachStore restores a persisted session', () async {
    final s = _build();
    final store = InMemorySnapshotStore();
    await store.persist(
      PersistedSession(
        bundles: [
          SnapshotBundle(
            id: 1,
            capturedAt: DateTime(2026),
            label: 'restored',
            histogram: const [],
            analysisResult: const GraphAnalysisResult(
              clusters: [],
              stats: GraphAnalysisStats(
                totalObjects: 0,
                reachableObjects: 0,
                leakCandidates: 0,
                clusters: 0,
                suppressedByAppFilter: 0,
                warnings: [],
              ),
            ),
          ),
        ],
        selectedIds: const [1],
        view: RadarView.classHistogram,
      ),
    );
    await s.attachStore(store);
    expect(s.memory.snapshots.single.label, 'restored');
    expect(s.currentView, RadarView.classHistogram);
  });
}
```

- [ ] **Step 4: Export the session + the scaffold**

Add to `packages/radar_workbench/lib/radar_workbench.dart` (the `main_scaffold` export was deferred from Task 7 to here, now that `radar_session` exists):
```dart
export 'src/presentation/main_scaffold.dart';
export 'src/session/radar_session.dart';
```

- [ ] **Step 5: Run tests + full package analyze**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && flutter test`
Expected: PASS — the whole `radar_workbench` suite green on the VM (scaffold, core, analyzer, memory_controller, perf_stability, views, radar_session).

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && dart analyze --fatal-infos .`
Expected: `No issues found!` — `main_scaffold` now resolves (`RadarSession` has `exporter` + `RadarConnection` connection).

- [ ] **Step 6: Format + commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "refactor(radar_workbench): host-injected RadarSession + install()"
```

---

## Task 9: DevTools adapters + rewire `app.dart`

**Files:**
- Create: `packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_radar_connection.dart`
- Create: `packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_snapshot_source.dart`
- Create: `packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_snapshot_exporter.dart`
- Create: `packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_perf_call.dart`
- Modify: `packages/flutter_leak_radar_devtools/lib/src/app.dart`
- Modify: `packages/flutter_leak_radar_devtools/pubspec.yaml` (add `radar_workbench: ^0.1.0`, bump `version: 0.3.0`)

**Interfaces:**
- Consumes: `radar_workbench` (`RadarConnection`, `RadarConnectionState`/`RadarConnectionPhase`, `SnapshotSource`, `SnapshotExporter`, `SnapshotAnalyzer`, `SnapshotBundle`, `MemoryController`, `PerfDataController`, `ExtensionNotAvailableException`, `RadarSession`, `LeakRadarMainScaffold`), the retained `ConnectionStateNotifier` / `web_download` / `DtdSnapshotStore`.
- Produces: `DevToolsRadarConnection`, `DevToolsSnapshotSource`, `DevToolsSnapshotExporter`, `devtoolsPerfCallExtension`, and a rewired `LeakRadarDevToolsExtension`.

- [ ] **Step 1: Add the radar_workbench dependency + bump version**

In `packages/flutter_leak_radar_devtools/pubspec.yaml`:
- change `version: 0.2.1` → `version: 0.3.0`
- under `dependencies:`, add `radar_workbench: ^0.1.0` (keep `leak_graph`, `radar_ui`, `vm_service`, `devtools_extensions`, `devtools_app_shared`, `dtd`, `web`).

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart pub get`
Expected: resolves; `radar_workbench` linked from the workspace. If pub rejects a hosted-style dependency on the `publish_to: none` member, change the line to a path dependency:
```yaml
  radar_workbench:
    path: ../radar_workbench
```
and re-run `dart pub get` (expected: resolves).

- [ ] **Step 2: Create the connection adapter**

`packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_radar_connection.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

import '../connection/connection_state_notifier.dart';

/// Adapts the DevTools [ConnectionStateNotifier] to the workbench's
/// [RadarConnection] interface, mapping the extension's phase enum + state.
class DevToolsRadarConnection extends ChangeNotifier implements RadarConnection {
  DevToolsRadarConnection(this._inner) {
    _inner.addListener(notifyListeners);
  }

  final ConnectionStateNotifier _inner;

  @override
  RadarConnectionState get state {
    final s = _inner.state;
    return RadarConnectionState(
      phase: switch (s.phase) {
        ExtensionConnectionPhase.connecting => RadarConnectionPhase.connecting,
        ExtensionConnectionPhase.connected => RadarConnectionPhase.connected,
        ExtensionConnectionPhase.disconnected => RadarConnectionPhase.disconnected,
      },
      vmName: s.vmName,
      isolateName: s.isolateName,
    );
  }

  @override
  VmService? get vmService => _inner.vmService;

  @override
  IsolateRef? get isolateRef => _inner.isolateRef;

  @override
  void dispose() {
    _inner.removeListener(notifyListeners);
    super.dispose();
  }
}
```

- [ ] **Step 3: Create the snapshot-source adapter**

`packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_snapshot_source.dart`:
```dart
import 'dart:developer' as developer;

import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// Captures a heap snapshot from the connected app's VM service and hands the
/// parsed graph to the shared [SnapshotAnalyzer]. Never throws.
class DevToolsSnapshotSource implements SnapshotSource {
  const DevToolsSnapshotSource(this._connection, this._analyzer);

  final RadarConnection _connection;
  final SnapshotAnalyzer _analyzer;

  static const _log = 'leakRadarDevTools.snapshot';

  @override
  Future<SnapshotBundle> capture({String label = ''}) async {
    final svc = _connection.vmService;
    final iso = _connection.isolateRef;
    if (svc == null || iso == null) {
      return SnapshotBundle.failed(
        label: label,
        message: 'Not connected to a running app.',
      );
    }
    try {
      final graph = await HeapSnapshotGraph.getSnapshot(svc, iso);
      return _analyzer.fromGraph(VmSnapshotGraphView(graph), label: label);
    } catch (e, s) {
      developer.log('capture failed', name: _log, error: e, stackTrace: s);
      return SnapshotBundle.failed(
        label: label,
        message: 'Snapshot capture failed — see console for details.',
      );
    }
  }
}
```

- [ ] **Step 4: Create the exporter adapter**

`packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_snapshot_exporter.dart`:
```dart
import 'package:radar_workbench/radar_workbench.dart';

import '../util/web_download.dart';

/// Exports a bundle as a browser download of its JSON.
class DevToolsSnapshotExporter implements SnapshotExporter {
  const DevToolsSnapshotExporter();

  @override
  Future<void> export(SnapshotBundle bundle, {String? suggestedName}) async {
    final base = suggestedName ?? 'heap_${bundle.id}_${bundle.label}';
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    downloadJson('$safe.json', bundle.toJson());
  }
}
```

- [ ] **Step 5: Create the perf call-extension function**

`packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_perf_call.dart`:
```dart
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// Calls a VM service extension via DevTools' [serviceManager] on the main
/// isolate, unwrapping the `{"result": …}` envelope and mapping "method not
/// found" (-32601) to [ExtensionNotAvailableException]. This is the DevTools
/// implementation of [PerfDataController]'s injectable `callExtension`.
Future<Map<String, Object?>> devtoolsPerfCallExtension(String method) async {
  final svc = serviceManager.service;
  if (svc == null) throw const ExtensionNotAvailableException();
  final isolateId = serviceManager.isolateManager.mainIsolate.value?.id;
  if (isolateId == null) throw const ExtensionNotAvailableException();

  try {
    final response = await svc.callServiceExtension(method, isolateId: isolateId);
    final json = response.json;
    if (json == null) {
      throw StateError('Extension returned null JSON for $method');
    }
    final result = json['result'];
    if (result is String) {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, Object?>) return decoded;
      return json.cast<String, Object?>();
    }
    return json.cast<String, Object?>();
  } on Exception catch (e) {
    if (e.toString().contains('-32601') ||
        e.toString().toLowerCase().contains('not found') ||
        e.toString().toLowerCase().contains('unknown method')) {
      throw const ExtensionNotAvailableException();
    }
    rethrow;
  }
}
```

- [ ] **Step 6: Rewire `app.dart` to build + install the session**

Replace the whole body of `packages/flutter_leak_radar_devtools/lib/src/app.dart` with:
```dart
import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'adapters/devtools_perf_call.dart';
import 'adapters/devtools_radar_connection.dart';
import 'adapters/devtools_snapshot_exporter.dart';
import 'adapters/devtools_snapshot_source.dart';
import 'connection/connection_state_notifier.dart';
import 'session/dtd_snapshot_store.dart';

/// Root widget of the Leak Radar DevTools extension.
///
/// Builds the DevTools-specific adapters, installs the shared [RadarSession],
/// and attaches the durable [DtdSnapshotStore] so a session captured before
/// this iframe was disposed is restored on return.
class LeakRadarDevToolsExtension extends StatefulWidget {
  const LeakRadarDevToolsExtension({super.key});

  @override
  State<LeakRadarDevToolsExtension> createState() =>
      _LeakRadarDevToolsExtensionState();
}

class _LeakRadarDevToolsExtensionState
    extends State<LeakRadarDevToolsExtension> {
  @override
  void initState() {
    super.initState();
    final notifier = ConnectionStateNotifier();
    final connection = DevToolsRadarConnection(notifier);
    final source = DevToolsSnapshotSource(connection, const SnapshotAnalyzer());
    RadarSession.install(
      RadarSession(
        connection: connection,
        memory: MemoryController(snapshotSource: source, connection: connection),
        perf: PerfDataController(callExtension: devtoolsPerfCallExtension),
        exporter: const DevToolsSnapshotExporter(),
        onInit: notifier.init,
      ),
    );
    unawaited(RadarSession.instance.attachStore(DtdSnapshotStore()));
  }

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: LeakRadarMainScaffold());
  }
}
```

- [ ] **Step 7: Analyze the extension**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/flutter_leak_radar_devtools && dart analyze --fatal-infos .`
Expected: errors ONLY about the now-orphaned moved files still present under `lib/src/` (e.g. `snapshot_service.dart`, `memory/*`, `perf/*`, `stability/*`, `presentation/main_scaffold.dart`, `shell/*` that were moved) being unused, or the old `test/shell_memory_test.dart` referencing moved paths. Those are deleted in Task 10. There must be **no** error in `main.dart`, `app.dart`, the four adapters, `connection_state_notifier.dart`, `dtd_snapshot_store.dart`, or `web_download.dart`.

- [ ] **Step 8: Format + commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "feat(devtools): adapters + install shared RadarSession"
```

---

## Task 10: Delete migrated originals; migrate residual tests; green both suites

**Files:**
- Delete: any remaining moved sources still under `packages/flutter_leak_radar_devtools/lib/src/` (`capture/snapshot_service.dart`, `capture/snapshot_bundle.dart` if still present, `memory/` view/controller files, `perf/` files, `stability/` files, `filter/` files, `presentation/main_scaffold.dart`, `presentation/retaining_path_tile.dart`, `shell/left_rail.dart`, `shell/radar_view.dart`, `shell/connection_bar.dart`, `session/snapshot_store.dart`, `session/session_persistence.dart`, `session/radar_session.dart`) — everything already `git mv`d is gone; this step removes stragglers not moved (notably `capture/snapshot_service.dart`).
- Delete: `packages/flutter_leak_radar_devtools/test/shell_memory_test.dart` (fully migrated across Tasks 5/7).
- Create: `packages/flutter_leak_radar_devtools/test/adapters_test.dart`
- Keep: `packages/flutter_leak_radar_devtools/test/placeholder_test.dart`.

**Interfaces:**
- Produces: a DevTools package containing only shell + adapters + retained glue, with a chrome-runnable test suite.

- [ ] **Step 1: Remove the orphaned `snapshot_service.dart` and any straggler moved files**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
git rm packages/flutter_leak_radar_devtools/lib/src/capture/snapshot_service.dart
# Verify nothing else remains that was supposed to move:
find packages/flutter_leak_radar_devtools/lib/src -type f | sort
```
Expected remaining files ONLY:
```
lib/src/adapters/devtools_perf_call.dart
lib/src/adapters/devtools_radar_connection.dart
lib/src/adapters/devtools_snapshot_exporter.dart
lib/src/adapters/devtools_snapshot_source.dart
lib/src/app.dart
lib/src/connection/connection_state_notifier.dart
lib/src/session/dtd_snapshot_store.dart
lib/src/util/web_download.dart
```
If any moved file is still present, `git rm` it. Also remove now-empty dirs (`capture/`, `memory/`, `perf/`, `stability/`, `filter/`, `presentation/`, `shell/`) — `git` drops them automatically once empty.

- [ ] **Step 2: Delete the fully-migrated test**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
git rm packages/flutter_leak_radar_devtools/test/shell_memory_test.dart
```

- [ ] **Step 3: Write a chrome-side adapter test**

`packages/flutter_leak_radar_devtools/test/adapters_test.dart`:
```dart
import 'package:flutter_leak_radar_devtools/src/adapters/devtools_snapshot_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  test('DevToolsSnapshotExporter builds a sanitized filename and does not throw',
      () async {
    const exporter = DevToolsSnapshotExporter();
    final bundle = SnapshotBundle.failed(label: 'A B/C', message: 'm');
    // downloadJson requires a DOM; under the web test host it is a no-op path,
    // so this asserts the export call completes without throwing.
    await expectLater(exporter.export(bundle), completes);
  });
}
```

> This test imports `web_download` transitively, so it must run under `--platform chrome`.

- [ ] **Step 4: Run the DevTools suite on chrome**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/flutter_leak_radar_devtools && flutter test --platform chrome`
Expected: PASS (`placeholder_test`, `adapters_test`). If chrome is unavailable in the environment, record that the suite must be run in CI on chrome and verify at minimum `dart analyze --fatal-infos .` is clean (next step).

- [ ] **Step 5: Analyze the DevTools package clean**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/flutter_leak_radar_devtools && dart analyze --fatal-infos .`
Expected: `No issues found!`

- [ ] **Step 6: Analyze the workbench clean + run its full suite**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/radar_workbench && dart analyze --fatal-infos . && flutter test`
Expected: `No issues found!` and all tests PASS.

- [ ] **Step 7: Format + commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "refactor(devtools): remove migrated sources; thin shell only"
```

---

## Task 11: Full CI gate + extension rebundle

**Files:**
- Modify (optional rebundle): `packages/flutter_leak_radar/extension/devtools/build/**`, `packages/flutter_leak_radar_devtools/extension/devtools/config.yaml`

**Interfaces:**
- Produces: a repo that passes `melos run ci`.

- [ ] **Step 1: Run the full local CI gate**

Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && melos run ci`
Expected: `format-check` → `analyze` (all packages, `--fatal-infos`) → `test` → `custom_lint` all pass. Note: Melos `test` runs `flutter test` per package on the VM; the DevTools package's web-interop suite may need `--platform chrome` separately — if Melos runs the devtools tests on the VM and they fail to compile, that is the known web-interop limitation; run the devtools suite explicitly with `cd packages/flutter_leak_radar_devtools && flutter test --platform chrome` and treat the Melos `test` as covering the VM-safe packages (radar_workbench included).

- [ ] **Step 2: Bump the extension config version**

In `packages/flutter_leak_radar_devtools/extension/devtools/config.yaml`, change `version: 0.1.0` → `version: 0.3.0` to match the pubspec.

- [ ] **Step 3: (Optional, release hygiene) Rebuild the bundled extension**

The published `flutter_leak_radar` bundles the built extension at `flutter_leak_radar/extension/devtools/build/`. Rebuilding is a release concern, not required for Phase 1 correctness. If rebuilding now:
Run: `cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages/flutter_leak_radar_devtools && dart run devtools_extensions build_and_copy --source=. --dest=../flutter_leak_radar/extension/devtools`
Expected: build succeeds and refreshes `build/`. If the environment cannot build web, skip and leave a note in the commit body that the bundle must be rebuilt at release time.

- [ ] **Step 4: Final commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar
dart format .
git add -A
git commit -m "chore(devtools): bump extension to 0.3.0; Phase 1 extraction complete"
```

---

## Self-Review Notes (for the executor)

- **No behavior change is the acceptance test.** The DevTools extension's user-visible behavior is identical; the proof is that every migrated test keeps its original assertions and passes, now on the VM under `radar_workbench`.
- **The only semantic edits** are: `MemoryController` constructor (service/notifier → source/connection), `PerfDataController` default (serviceManager → `_notConnected`), `SnapshotsView` export (direct download → `onExport`), `ConnectionBar` (concrete notifier → `RadarConnection`), and `RadarSession` (hard singleton → injected + `install`). Everything else is a pure move.
- **Web-safety guard:** after Task 10, grep the workbench for banned imports and expect zero hits:
  `cd packages/radar_workbench && ! grep -rn "devtools_extensions\|package:web\|dart:js_interop\|dart:io\|package:dtd" lib`
- If any task's analyze/tests fail for a reason not anticipated in its notes, stop and use superpowers:systematic-debugging before proceeding.
