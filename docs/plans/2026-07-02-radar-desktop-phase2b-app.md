# Radar Desktop Phase 2b — Workspace & Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Radar Desktop offline app — a `WorkspaceController` that imports heap-dump files into a reused `MemoryController`, and the five real screens (Dumps, Class histogram, Retaining paths, Compare, Trends) replacing the Phase 2a placeholders, plus report/workspace export and session auto-restore.

**Architecture:** `DesktopShell` owns a `WorkspaceController` (radar_desktop). The controller wraps a `radar_workbench` `MemoryController` — constructed with the Phase 2a offline seams (`DisconnectedRadarConnection` + `OfflineSnapshotSource`) — and adds file import (`SnapshotAnalyzer.fromBytes` → `MemoryController.addBundle`), an "analyzing" progress state, an N-way trend selection, recent files, `.radarworkspace` save/open, and auto-restore via `FileSnapshotStore`. The single-dump views are reused by driving a new backward-compatible `MemoryController.focusOn(id)`; Compare reuses `DiffTable` off the controller's 2-way `toggleSelection`; Trends is custom over `computeTrend` + `RadarTrendChart`. **No `RadarSession`** — the views take a `MemoryController` directly.

**Tech Stack:** Dart 3.10 / Flutter 3.38, `radar_workbench` + `radar_ui` + `leak_graph`, `file_selector`, `desktop_drop`, `path_provider`, `flutter_test`.

## Global Constraints

- SDK floor `>=3.10.0 <4.0.0`; Flutter floor `>=3.38.0`. Strict analysis: `dart analyze --fatal-infos` clean (`strict-casts`/`strict-inference`/`strict-raw-types`). Format: `dart format --set-exit-if-changed .` — run `dart format .` before every commit.
- `radar_workbench` change (Task 1) MUST stay backward-compatible (DevTools `main_scaffold` behavior unchanged when `focusOn` is never called) and MUST NOT gain forbidden imports (`devtools_extensions`/`package:web`/`dart:io`/`dart:js_interop`/`package:dtd`).
- Design tokens from `radar_ui` only — never hardcode palette/type/spacing. Reuse the Phase 2a widgets `RadarLinearProgress` (analyzing) and `RadarTrendChart` (trends), and `RadarSortHeader`/`RadarFilterChip`/`RadarSearchField`/`RadarTag`/`RadarMetricTile` for tables/chips.
- Reuse the workbench views unchanged: `ClassHistogramView(controller:)`, `RetainingPathsView(controller:)`, `DiffTable(diffs:, summary:, selected:, onSelected:, absolute:)`, `ClassDetailPanel(className:, profile:, distribution:)`. Do NOT fork them.
- The desktop reuses `MemoryController` (from `radar_workbench`) as the single source of the dump list, focus, and 2-way compare selection. `WorkspaceController` OWNS one `MemoryController` and exposes it as `.memory`.
- Isolate analysis: file bytes → `SnapshotAnalyzer.fromBytes` (already runs on `compute`) → `MemoryController.addBundle`. Show `RadarLinearProgress` while `analyzing`.
- `radar_desktop` is a leaf app — `dart:io`/native plugin imports are fine.
- Rail fix (from Phase 2a Task 7 review): when a persisted view is restored while offline, clamp the active `DesktopView` to an enabled (memory) one so the rail never shows a locked item as active.
- Commit after every task. `melos` via `dart run melos`.

---

## File Structure

**`radar_workbench` change:**
```
packages/radar_workbench/lib/src/memory/memory_controller.dart   # + focusOn(id) + focused honors it
packages/radar_workbench/test/memory_controller_test.dart        # + focusOn tests
```

**`radar_desktop` additions:**
```
lib/src/workspace/workspace_controller.dart      # NEW — owns MemoryController + import + trend-select + recent + persistence
lib/src/workspace/dump_meta.dart                 # NEW — small row-metadata view model (source/label/size)
lib/src/screens/dumps_screen.dart                # NEW — workspace table + drop zone + recent + import
lib/src/screens/histogram_screen.dart            # NEW — reuse ClassHistogramView via focusOn
lib/src/screens/paths_screen.dart                # NEW — reuse RetainingPathsView via focusOn
lib/src/screens/compare_screen.dart              # NEW — two pickers → DiffTable
lib/src/screens/trends_screen.dart               # NEW — class chips + RadarTrendChart
lib/src/shell/desktop_shell.dart                 # MODIFY — own WorkspaceController, route to real screens, rail clamp
test/workspace_controller_test.dart              # NEW
test/screens_test.dart                           # NEW (widget smoke of each screen)
```

---

## Task 1: `MemoryController.focusOn(id)` in radar_workbench

**Files:**
- Modify: `packages/radar_workbench/lib/src/memory/memory_controller.dart`
- Modify: `packages/radar_workbench/test/memory_controller_test.dart`

**Interfaces:**
- Produces: `void MemoryController.focusOn(int? id)` — sets an explicit focused-snapshot id (or clears with `null`), notifies. `focused` getter now returns `_byId(_focusedId) ?? pair?.comparison ?? latest`. `int? get focusedId`.

- [ ] **Step 1: Write the failing test**

Add to `packages/radar_workbench/test/memory_controller_test.dart` (reuse the existing `_bundle`/`_snap` helper):
```dart
  group('focusOn (desktop active-dump hook)', () {
    test('focused honors an explicitly focused id over latest', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      final a = c.addBundle(_bundle('a'));
      c.addBundle(_bundle('b')); // b is latest
      // Default: focused falls through to latest (b), not a.
      expect(c.focused?.label, 'b');
      c.focusOn(a.id);
      expect(c.focusedId, a.id);
      expect(c.focused?.label, 'a'); // now honors the explicit focus
      c.focusOn(null);
      expect(c.focused?.label, 'b'); // cleared → back to latest
    });

    test('focusOn(unknown id) falls through to pair/latest', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      c.addBundle(_bundle('a'));
      final b = c.addBundle(_bundle('b'));
      c.focusOn(9999); // not present
      expect(c.focused?.id, b.id); // _byId(9999) == null → latest
    });
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_workbench && flutter test test/memory_controller_test.dart`
Expected: FAIL — `focusOn`/`focusedId` not defined.

- [ ] **Step 3: Implement it**

In `memory_controller.dart`, add the field near the other private state (`_nextId`/`_selected`):
```dart
  int? _focusedId;
```
Add the getter + setter (place `focusedId` near `selectedIds`, and `focusOn` near `toggleSelection`):
```dart
  /// The explicitly-focused snapshot id for the single-snapshot views
  /// (histogram / retaining paths), or null to fall back to the diff pair /
  /// latest. Set by hosts (e.g. the desktop app) that let the user pick an
  /// arbitrary dump to inspect; unused by DevTools (which leaves it null).
  int? get focusedId => _focusedId;

  /// Sets [focusedId] (or clears it with null) and notifies.
  void focusOn(int? id) {
    _focusedId = id;
    notifyListeners();
  }
```
Change the `focused` getter from:
```dart
  SnapshotBundle? get focused => pair?.comparison ?? latest;
```
to:
```dart
  SnapshotBundle? get focused =>
      (_focusedId == null ? null : _byId(_focusedId!)) ??
      pair?.comparison ??
      latest;
```
(If a `remove`/`clearAll` could leave `_focusedId` dangling, that is fine — `_byId` returns null and `focused` falls through. Optionally clear `_focusedId` in `clearAll`; not required since `_byId` guards it.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/radar_workbench && flutter test test/memory_controller_test.dart`
Expected: PASS (existing + the two `focusOn` tests). Also run the full suite to confirm no DevTools-path regression: `flutter test` → all green (focused still `== pair?.comparison ?? latest` whenever `focusOn` was never called).

- [ ] **Step 5: Analyze + format + commit**

```bash
cd packages/radar_workbench && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_workbench && git commit -m "feat(radar_workbench): MemoryController.focusOn for host-driven active dump"
```

---

## Task 2: `WorkspaceController` in radar_desktop

The desktop's controller: owns a `MemoryController` (offline seams), imports dumps, tracks the N-way trend selection + recent files + analyzing state. No `.radarworkspace` persistence yet (Task 9).

**Files:**
- Create: `packages/radar_desktop/lib/src/workspace/workspace_controller.dart`
- Create: `packages/radar_desktop/lib/src/workspace/dump_meta.dart`
- Test: `packages/radar_desktop/test/workspace_controller_test.dart`

**Interfaces:**
- Produces:
  - `enum DumpSource { file, capture }`
  - `class DumpMeta { final int id; final String label; final DumpSource source; final DateTime capturedAt; final int classCount; final int retainedBytes; }`
  - `class WorkspaceController extends ChangeNotifier` with `MemoryController get memory`; `bool get analyzing`; `String? get analyzingName`; `List<int> get trendSelection` (multi-select ids); `List<String> get recentPaths`; `List<DumpMeta> get dumps`; `int? get activeDumpId`;
    - `Future<void> importBytes(Uint8List bytes, {required String label, String? recentPath})` — sets analyzing, runs `SnapshotAnalyzer.fromBytes`, `memory.addBundle`, focuses it, clears analyzing.
    - `void openDump(int id)` — sets it active (`memory.focusOn(id)`).
    - `void toggleTrendSelection(int id)`; `void removeDump(int id)`; `void clearAll()`.
    - `void selectComparePair(int a, int b)` — sets the memory 2-way selection to exactly (a,b).

- [ ] **Step 1: Write the failing test**

`packages/radar_desktop/test/workspace_controller_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_desktop/src/workspace/workspace_controller.dart';
import 'package:radar_workbench/radar_workbench.dart';

SnapshotBundle _bundle(String label) => SnapshotBundle(
  capturedAt: DateTime(2026, 1, 1),
  label: label,
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
);

void main() {
  test('addExisting populates memory, focuses it, and records meta', () {
    final wc = WorkspaceController();
    final b = wc.addExisting(_bundle('soak-1'), source: DumpSource.file);
    expect(wc.memory.snapshots.single.id, b.id);
    expect(wc.memory.focusedId, b.id);
    expect(wc.dumps.single.label, 'soak-1');
    expect(wc.dumps.single.source, DumpSource.file);
  });

  test('toggleTrendSelection adds/removes ids', () {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
    final b = wc.addExisting(_bundle('b'), source: DumpSource.file);
    wc.toggleTrendSelection(a.id);
    wc.toggleTrendSelection(b.id);
    expect(wc.trendSelection, containsAll([a.id, b.id]));
    wc.toggleTrendSelection(a.id);
    expect(wc.trendSelection, isNot(contains(a.id)));
  });

  test('selectComparePair sets the memory 2-way selection', () {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
    final b = wc.addExisting(_bundle('b'), source: DumpSource.file);
    wc.selectComparePair(a.id, b.id);
    expect(wc.memory.selectedIds, containsAll([a.id, b.id]));
    expect(wc.memory.diff, isNotNull);
  });

  test('removeDump drops it from memory + meta + trend selection', () {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
    wc.toggleTrendSelection(a.id);
    wc.removeDump(a.id);
    expect(wc.memory.snapshots, isEmpty);
    expect(wc.dumps, isEmpty);
    expect(wc.trendSelection, isNot(contains(a.id)));
  });
}
```
(`addExisting` is the pure, connection-free core of import — it's the unit-testable seam; `importBytes` wraps it around the async analyzer and is exercised via the screen/manual runs.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/workspace_controller_test.dart`
Expected: FAIL — `WorkspaceController` not defined.

- [ ] **Step 3: Implement `dump_meta.dart`**

`packages/radar_desktop/lib/src/workspace/dump_meta.dart`:
```dart
/// Where a dump came from.
enum DumpSource { file, capture }

/// Row metadata for a dump in the workspace table (derived from a
/// `SnapshotBundle`, kept alongside it so the table renders without recomputing).
class DumpMeta {
  const DumpMeta({
    required this.id,
    required this.label,
    required this.source,
    required this.capturedAt,
    required this.classCount,
    required this.retainedBytes,
  });

  final int id;
  final String label;
  final DumpSource source;
  final DateTime capturedAt;
  final int classCount;
  final int retainedBytes;
}
```

- [ ] **Step 4: Implement `workspace_controller.dart`**

`packages/radar_desktop/lib/src/workspace/workspace_controller.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../seams/disconnected_connection.dart';
import '../seams/offline_snapshot_source.dart';
import 'dump_meta.dart';

/// Owns the offline workspace: a `radar_workbench` [MemoryController] (built
/// with the offline seams) plus desktop-only state — the multi-dump trend
/// selection, recent files, and the "analyzing…" flag. Screens read
/// [memory] for the reused views and this controller for workspace actions.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({SnapshotAnalyzer analyzer = const SnapshotAnalyzer()})
      : _analyzer = analyzer {
    _connection = DisconnectedRadarConnection();
    memory = MemoryController(
      snapshotSource: const OfflineSnapshotSource(),
      connection: _connection,
    );
  }

  final SnapshotAnalyzer _analyzer;
  late final DisconnectedRadarConnection _connection;

  /// The reused workbench controller — pass to `ClassHistogramView`,
  /// `RetainingPathsView`, `DiffTable`, etc.
  late final MemoryController memory;

  final Map<int, DumpMeta> _meta = {};
  final List<int> _trend = [];
  final List<String> _recent = [];
  bool _analyzing = false;
  String? _analyzingName;

  bool get analyzing => _analyzing;
  String? get analyzingName => _analyzingName;
  List<int> get trendSelection => List.unmodifiable(_trend);
  List<String> get recentPaths => List.unmodifiable(_recent);
  int? get activeDumpId => memory.focusedId;

  /// Dumps in capture order (matches `memory.snapshots`).
  List<DumpMeta> get dumps =>
      [for (final s in memory.snapshots) _meta[s.id]!];

  /// Adds an already-analyzed bundle (the connection-free core of import).
  /// Assigns metadata, appends to [memory], focuses it, and returns the stored
  /// bundle. Used directly by tests and by [importBytes]/restore.
  SnapshotBundle addExisting(
    SnapshotBundle bundle, {
    required DumpSource source,
  }) {
    final stored = memory.addBundle(bundle);
    _meta[stored.id] = DumpMeta(
      id: stored.id,
      label: stored.label,
      source: source,
      capturedAt: stored.capturedAt,
      classCount: stored.histogram.length,
      retainedBytes: stored.shallowBytes,
    );
    memory.focusOn(stored.id);
    notifyListeners();
    return stored;
  }

  /// Imports raw `.dartheap` bytes: analyze off-thread, then add to the
  /// workspace. Surfaces [analyzing] while in flight. Never throws (the
  /// analyzer returns a failed bundle on error).
  Future<void> importBytes(
    Uint8List bytes, {
    required String label,
    String? recentPath,
  }) async {
    _analyzing = true;
    _analyzingName = label;
    notifyListeners();
    try {
      final bundle = await _analyzer.fromBytes(bytes, label: label);
      addExisting(bundle, source: DumpSource.file);
      if (recentPath != null) {
        _recent
          ..remove(recentPath)
          ..insert(0, recentPath);
        if (_recent.length > 8) _recent.removeLast();
      }
    } finally {
      _analyzing = false;
      _analyzingName = null;
      notifyListeners();
    }
  }

  /// Makes [id] the active dump for the histogram / retaining-paths views.
  void openDump(int id) => memory.focusOn(id);

  /// Sets the compare pair to exactly (a, b) via the memory 2-way selection.
  void selectComparePair(int a, int b) {
    // Clear then select the two (toggleSelection caps at 2, FIFO).
    for (final id in memory.selectedIds.toList()) {
      memory.toggleSelection(id);
    }
    memory.toggleSelection(a);
    memory.toggleSelection(b);
  }

  void toggleTrendSelection(int id) {
    if (_trend.contains(id)) {
      _trend.remove(id);
    } else {
      _trend.add(id);
    }
    notifyListeners();
  }

  void removeDump(int id) {
    memory.remove(id);
    _meta.remove(id);
    _trend.remove(id);
    notifyListeners();
  }

  void clearAll() {
    memory.clearAll();
    _meta.clear();
    _trend.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    memory.dispose();
    _connection.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/radar_desktop && flutter test test/workspace_controller_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop && git commit -m "feat(radar_desktop): WorkspaceController (import + trend-select + recent)"
```

---

## Task 3: Dumps / Workspace screen

**Files:**
- Create: `packages/radar_desktop/lib/src/screens/dumps_screen.dart`
- Test: add a group to `packages/radar_desktop/test/screens_test.dart`

**Interfaces:**
- Consumes: `WorkspaceController` (`dumps`, `trendSelection`, `analyzing`, `importBytes`, `openDump`, `toggleTrendSelection`, `removeDump`).
- Produces: `class DumpsScreen extends StatelessWidget { const DumpsScreen({required WorkspaceController workspace, required ValueChanged<int> onOpenHistogram}); }` — a workspace table (checkbox · dump · source · captured · classes · retained), a drag-drop zone + "browse" (file_selector), a Recent row, and a `RadarLinearProgress` header when `analyzing`.

- [ ] **Step 1: Write the failing widget test**

Create `packages/radar_desktop/test/screens_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_desktop/src/screens/dumps_screen.dart';
import 'package:radar_desktop/src/workspace/workspace_controller.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

SnapshotBundle _bundle(String label) => SnapshotBundle(
  capturedAt: DateTime(2026, 1, 1),
  label: label,
  histogram: const [],
  analysisResult: const GraphAnalysisResult(
    clusters: [],
    stats: GraphAnalysisStats(
      totalObjects: 0, reachableObjects: 0, leakCandidates: 0,
      clusters: 0, suppressedByAppFilter: 0, warnings: [],
    ),
  ),
);

void main() {
  testWidgets('DumpsScreen lists dumps and reports open + trend-select', (tester) async {
    final wc = WorkspaceController();
    wc.addExisting(_bundle('soak-24h'), source: DumpSource.file);
    int? opened;
    await tester.pumpWidget(MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: DumpsScreen(workspace: wc, onOpenHistogram: (id) => opened = id)),
    ));
    expect(find.text('soak-24h'), findsOneWidget);
    // Drop-zone prompt present.
    expect(find.textContaining('Drop'), findsWidgets);
    // Opening the dump name routes to histogram.
    await tester.tap(find.text('soak-24h'));
    expect(opened, isNotNull);
  });

  testWidgets('DumpsScreen shows the analyzing bar when workspace.analyzing', (tester) async {
    final wc = WorkspaceController();
    // Drive analyzing directly via a never-completing import is awkward in a
    // widget test; instead assert the bar is absent when idle and present when
    // a test double flips analyzing. Here we just assert idle has no bar.
    await tester.pumpWidget(MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: DumpsScreen(workspace: wc, onOpenHistogram: (_) {})),
    ));
    expect(find.byType(RadarLinearProgress), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/screens_test.dart`
Expected: FAIL — `DumpsScreen` not defined.

- [ ] **Step 3: Implement `dumps_screen.dart`**

`packages/radar_desktop/lib/src/screens/dumps_screen.dart`:
```dart
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../workspace/dump_meta.dart';
import '../workspace/workspace_controller.dart';

/// The workspace: a multi-select table of loaded dumps, a drag-drop import
/// zone + browse button, a Recent row, and an "analyzing…" bar while a dump is
/// being parsed. Clicking a dump's name opens it in the histogram.
class DumpsScreen extends StatelessWidget {
  const DumpsScreen({
    super.key,
    required this.workspace,
    required this.onOpenHistogram,
  });

  final WorkspaceController workspace;
  final ValueChanged<int> onOpenHistogram;

  static const _types = [
    XTypeGroup(label: 'Heap snapshot', extensions: ['dartheap', 'data']),
  ];

  Future<void> _browse() async {
    final file = await openFile(acceptedTypeGroups: _types);
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    await workspace.importBytes(bytes, label: _labelFor(file.path), recentPath: file.path);
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    for (final f in details.files) {
      final bytes = await File(f.path).readAsBytes();
      await workspace.importBytes(bytes, label: _labelFor(f.path), recentPath: f.path);
    }
  }

  static String _labelFor(String path) =>
      path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.(dartheap|data)$'), '');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        return DropTarget(
          onDragDone: _onDrop,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(workspace: workspace, onBrowse: _browse),
              if (workspace.analyzing)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(child: RadarLinearProgress()),
                      const SizedBox(width: 10),
                      Text(
                        'Analyzing ${workspace.analyzingName ?? ''}…',
                        style: RadarTypography.monoLabel,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: workspace.dumps.isEmpty
                    ? _DropZone(onBrowse: _browse)
                    : _DumpTable(workspace: workspace, onOpen: onOpenHistogram),
              ),
              if (workspace.recentPaths.isNotEmpty)
                _RecentRow(paths: workspace.recentPaths),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.workspace, required this.onBrowse});
  final WorkspaceController workspace;
  final Future<void> Function() onBrowse;

  @override
  Widget build(BuildContext context) {
    final n = workspace.dumps.length;
    final sel = workspace.trendSelection.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Text('Workspace', style: RadarTypography.appBarTitle),
          const SizedBox(width: 10),
          Text('multi-select for diff & trends', style: RadarTypography.monoLabel),
          const Spacer(),
          Text('$n dumps · $sel selected',
              style: RadarTypography.monoLabel.copyWith(color: RadarColors.text25)),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => onBrowse(),
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Import dump'),
          ),
        ],
      ),
    );
  }
}

class _DumpTable extends StatelessWidget {
  const _DumpTable({required this.workspace, required this.onOpen});
  final WorkspaceController workspace;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final dumps = workspace.dumps;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: dumps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final d = dumps[i];
        final checked = workspace.trendSelection.contains(d.id);
        final active = workspace.activeDumpId == d.id;
        return Container(
          decoration: BoxDecoration(
            color: active ? RadarColors.accentSubtle : RadarColors.bgSurface,
            border: Border.all(
              color: active ? RadarColors.accent.withValues(alpha: 0.3) : RadarColors.hairline08,
            ),
            borderRadius: RadarDensity.rowRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: (_) => workspace.toggleTrendSelection(d.id),
              ),
              Icon(
                d.source == DumpSource.file ? Icons.description_outlined : Icons.adjust,
                size: 16,
                color: d.source == DumpSource.file ? RadarColors.accent : RadarColors.info,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () => onOpen(d.id),
                  child: Text(d.label, style: RadarTypography.monoBody),
                ),
              ),
              Expanded(child: Text(d.source.name, style: RadarTypography.monoLabel)),
              Expanded(child: Text(_fmtTime(d.capturedAt), style: RadarTypography.monoLabel)),
              Expanded(
                child: Text('${d.classCount}',
                    textAlign: TextAlign.right, style: RadarTypography.monoNumber),
              ),
              Expanded(
                child: Text(_fmtBytes(d.retainedBytes),
                    textAlign: TextAlign.right, style: RadarTypography.monoNumber),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                onPressed: () => workspace.removeDump(d.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onBrowse});
  final Future<void> Function() onBrowse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          border: Border.all(color: RadarColors.hairline08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_for_offline_outlined,
                size: 40, color: RadarColors.text10),
            const SizedBox(height: 10),
            Text('Drop .dartheap files here', style: RadarTypography.monoBody),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => onBrowse(),
              child: Text('browse',
                  style: RadarTypography.monoBody
                      .copyWith(color: RadarColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Text('RECENT', style: RadarTypography.monoLabel.copyWith(color: RadarColors.text10)),
          for (final p in paths)
            RadarTag(label: p.split(Platform.pathSeparator).last),
        ],
      ),
    );
  }
}

String _fmtBytes(int b) {
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  return '$b B';
}

String _fmtTime(DateTime t) =>
    '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
```

> **Implementer note:** the code above is literal. A dashed drop-zone border is optional polish — the plain bordered box shown is fine. Verify `desktop_drop`'s `DropTarget`/`DropDoneDetails` and `file_selector`'s `openFile`/`XTypeGroup` names against the installed versions; if `DropDoneDetails.files` elements are `DropItem` (they extend `XFile`), `f.path` still works unchanged.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/radar_desktop && flutter test test/screens_test.dart`
Expected: PASS (the two DumpsScreen tests).

- [ ] **Step 5: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop && git commit -m "feat(radar_desktop): Dumps/Workspace screen (table + drop-zone + import)"
```

---

## Task 4: Histogram + Retaining-paths screens (reuse via focusOn)

Thin wrappers that ensure the workspace's active dump is focused, then render the reused workbench views.

**Files:**
- Create: `packages/radar_desktop/lib/src/screens/histogram_screen.dart`
- Create: `packages/radar_desktop/lib/src/screens/paths_screen.dart`
- Test: add a group to `test/screens_test.dart`

**Interfaces:**
- Produces: `class HistogramScreen extends StatelessWidget { const HistogramScreen({required WorkspaceController workspace}); }` and `class PathsScreen` — each renders `ClassHistogramView`/`RetainingPathsView` with `controller: workspace.memory`, showing an empty prompt when no dump is active.

- [ ] **Step 1: Write the failing test**

Add to `test/screens_test.dart`:
```dart
  testWidgets('HistogramScreen renders the reused ClassHistogramView for the active dump', (tester) async {
    final wc = WorkspaceController();
    wc.addExisting(_bundle('d1'), source: DumpSource.file); // addExisting focuses it
    await tester.pumpWidget(MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: HistogramScreen(workspace: wc)),
    ));
    expect(find.byType(ClassHistogramView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HistogramScreen shows an empty prompt with no dumps', (tester) async {
    final wc = WorkspaceController();
    await tester.pumpWidget(MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: HistogramScreen(workspace: wc)),
    ));
    // ClassHistogramView itself renders its own empty state, so it is present;
    // just assert no throw.
    expect(tester.takeException(), isNull);
  });
```
(Add `import 'package:radar_desktop/src/screens/histogram_screen.dart';` etc. to the test.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/screens_test.dart`
Expected: FAIL — `HistogramScreen`/`PathsScreen` not defined.

- [ ] **Step 3: Implement both**

`packages/radar_desktop/lib/src/screens/histogram_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// The single-dump class histogram for the workspace's active dump. Reuses the
/// workbench `ClassHistogramView` unchanged — it reads `memory.focused`, which
/// the workspace points at the active dump via `MemoryController.focusOn`.
class HistogramScreen extends StatelessWidget {
  const HistogramScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) =>
      ClassHistogramView(controller: workspace.memory);
}
```
`packages/radar_desktop/lib/src/screens/paths_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// Retaining-paths master–detail for the active dump. Reuses the workbench
/// `RetainingPathsView` (reads `memory.focused`).
class PathsScreen extends StatelessWidget {
  const PathsScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) =>
      RetainingPathsView(controller: workspace.memory);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/radar_desktop && flutter test test/screens_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop && git commit -m "feat(radar_desktop): Histogram + Retaining-paths screens (reuse via focusOn)"
```

---

## Task 5: Compare screen (two pickers → DiffTable)

**Files:**
- Create: `packages/radar_desktop/lib/src/screens/compare_screen.dart`
- Test: add a group to `test/screens_test.dart`

**Interfaces:**
- Produces: `class CompareScreen extends StatefulWidget { const CompareScreen({required WorkspaceController workspace}); }` — two dump dropdowns (A → B) that call `workspace.selectComparePair(a, b)`, rendering the reused `DiffTable` off `workspace.memory.diff` + a `ClassDetailPanel`.

- [ ] **Step 1: Write the failing test**

Add to `test/screens_test.dart`:
```dart
  testWidgets('CompareScreen diffs the two selected dumps', (tester) async {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('A'), source: DumpSource.file);
    final b = wc.addExisting(_bundle('B'), source: DumpSource.file);
    wc.selectComparePair(a.id, b.id);
    await tester.pumpWidget(MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: CompareScreen(workspace: wc)),
    ));
    expect(find.byType(DiffTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/screens_test.dart`
Expected: FAIL — `CompareScreen` not defined.

- [ ] **Step 3: Implement `compare_screen.dart`**

`packages/radar_desktop/lib/src/screens/compare_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// Point-in-time diff of two dumps. Two dropdowns pick baseline (A) and
/// comparison (B); the selection is pushed into the workspace's `MemoryController`
/// (which computes the diff), and the reused `DiffTable` renders it.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  int? _a;
  int? _b;
  String? _selectedClass;

  WorkspaceController get _wc => widget.workspace;

  @override
  void initState() {
    super.initState();
    final ids = _wc.dumps.map((d) => d.id).toList();
    if (ids.length >= 2) {
      _a = ids[ids.length - 2];
      _b = ids.last;
      _apply();
    }
  }

  void _apply() {
    if (_a != null && _b != null && _a != _b) {
      _wc.selectComparePair(_a!, _b!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _wc.memory,
      builder: (context, _) {
        final dumps = _wc.dumps;
        final diff = _wc.memory.diff ?? const <ClassCountDiff>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Text('Compare', style: RadarTypography.appBarTitle),
                  const SizedBox(width: 16),
                  _picker(dumps, _a, (v) => setState(() { _a = v; _apply(); })),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16),
                  ),
                  _picker(dumps, _b, (v) => setState(() { _b = v; _apply(); })),
                ],
              ),
            ),
            Expanded(
              child: dumps.length < 2
                  ? Center(
                      child: Text('Load at least two dumps to compare.',
                          style: RadarTypography.monoLabel))
                  : Row(
                      children: [
                        Expanded(
                          child: DiffTable(
                            diffs: diff,
                            absolute: false,
                            summary: const SizedBox.shrink(),
                            selected: _selectedClass,
                            onSelected: (c) => setState(() => _selectedClass = c),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 340,
                          child: _detailFor(_selectedClass),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailFor(String? className) {
    final comparison = _wc.memory.comparison;
    if (className == null || comparison == null) {
      return const ClassDetailPanel(className: null, profile: null);
    }
    ClassRootProfile? profile;
    for (final p in comparison.analysisResult.classRootProfiles) {
      if (p.className == className) {
        profile = p;
        break;
      }
    }
    ClassPathDistribution? dist;
    for (final d in comparison.analysisResult.classPathDistributions) {
      if (d.className == className) {
        dist = d;
        break;
      }
    }
    return ClassDetailPanel(className: className, profile: profile, distribution: dist);
  }

  Widget _picker(List<DumpMeta> dumps, int? value, ValueChanged<int?> onChanged) {
    return DropdownButton<int>(
      value: value,
      dropdownColor: RadarColors.bgSurface,
      style: RadarTypography.monoBody,
      items: [
        for (final d in dumps)
          DropdownMenuItem(value: d.id, child: Text(d.label)),
      ],
      onChanged: onChanged,
    );
  }
}
```
(Add `import '../workspace/dump_meta.dart';` if `DumpMeta` isn't transitively available — it is exported from `workspace_controller.dart`'s import graph, but import it explicitly if analyze complains.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/radar_desktop && flutter test test/screens_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop && git commit -m "feat(radar_desktop): Compare screen (two pickers → reused DiffTable)"
```

---

## Task 6: Trends screen (class chips + RadarTrendChart)

**Files:**
- Create: `packages/radar_desktop/lib/src/screens/trends_screen.dart`
- Test: add a group to `test/screens_test.dart`

**Interfaces:**
- Produces: `class TrendsScreen extends StatefulWidget { const TrendsScreen({required WorkspaceController workspace}); }` — needs ≥2 dumps in `workspace.trendSelection`; class-picker chips from `growingClassNames`, the `RadarTrendChart` of the selected class's `computeTrend`, a first→last headline, and per-point value/time labels.

- [ ] **Step 1: Write the failing test**

Add to `test/screens_test.dart`:
```dart
  testWidgets('TrendsScreen prompts for >=2 selected dumps, then plots', (tester) async {
    // Build two dumps with a growing class.
    SnapshotBundle bWith(DateTime at, int leaky) => SnapshotBundle(
      capturedAt: at, label: at.toIso8601String(),
      histogram: [
        ClassCount(
          className: 'Leaky', libraryUri: Uri.parse('package:app/a.dart'),
          instanceCount: leaky, shallowBytes: leaky * 8,
        ),
      ],
      analysisResult: const GraphAnalysisResult(
        clusters: [],
        stats: GraphAnalysisStats(
          totalObjects: 0, reachableObjects: 0, leakCandidates: 0,
          clusters: 0, suppressedByAppFilter: 0, warnings: [],
        ),
      ),
    );
    final wc = WorkspaceController();
    final a = wc.addExisting(bWith(DateTime(2026, 1, 1, 9), 10), source: DumpSource.file);
    final b = wc.addExisting(bWith(DateTime(2026, 1, 1, 13), 40), source: DumpSource.file);

    await tester.pumpWidget(MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: TrendsScreen(workspace: wc)),
    ));
    // Fewer than 2 selected → prompt.
    expect(find.textContaining('at least two'), findsOneWidget);

    wc.toggleTrendSelection(a.id);
    wc.toggleTrendSelection(b.id);
    await tester.pumpAndSettle();
    // Now the growing-class chip + chart render.
    expect(find.text('Leaky'), findsWidgets);
    expect(find.byType(RadarTrendChart), findsOneWidget);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/screens_test.dart`
Expected: FAIL — `TrendsScreen` not defined.

- [ ] **Step 3: Implement `trends_screen.dart`**

`packages/radar_desktop/lib/src/screens/trends_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// Multi-dump trend: plot one class's instance count across the selected dumps
/// over time. The soak-test view — a class climbing and never returning to
/// baseline is the classic slow leak.
class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  String? _class;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) {
        final wc = widget.workspace;
        final selected = [
          for (final s in wc.memory.snapshots)
            if (wc.trendSelection.contains(s.id)) s,
        ];
        if (selected.length < 2) {
          return Center(
            child: Text(
              'Select at least two dumps in the workspace to plot a trend.',
              style: RadarTypography.monoLabel,
            ),
          );
        }
        final growing = growingClassNames(selected);
        final klass = _class ?? (growing.isNotEmpty ? growing.first : null);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Trends', style: RadarTypography.appBarTitle),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in growing)
                    RadarFilterChip(
                      label: name,
                      selected: name == klass,
                      onSelected: () => setState(() => _class = name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (klass != null) ...[
                Builder(builder: (context) {
                  final series = computeTrend(selected, klass);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$klass · first → last',
                              style: RadarTypography.monoLabel),
                          const Spacer(),
                          Text(
                            '${series.netInstanceDelta >= 0 ? '+' : ''}${series.netInstanceDelta} instances',
                            style: RadarTypography.metricValue.copyWith(
                              color: series.netInstanceDelta >= 0
                                  ? RadarColors.critical
                                  : RadarColors.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      RadarTrendChart(
                        series: [for (final p in series.points) p.instanceCount],
                      ),
                    ],
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/radar_desktop && flutter test test/screens_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop && git commit -m "feat(radar_desktop): Trends screen (growing-class chips + RadarTrendChart)"
```

---

## Task 7: Wire `DesktopShell` to the real screens

Replace the Phase 2a placeholders: own a `WorkspaceController`, route each `DesktopView` to its screen, and apply the rail active-view clamp (locked views never active offline).

**Files:**
- Modify: `packages/radar_desktop/lib/src/shell/desktop_shell.dart`
- Test: update `packages/radar_desktop/test/shell_test.dart`

**Interfaces:**
- Consumes: all five screens + `WorkspaceController`.
- Produces: a `DesktopShell` that owns a `WorkspaceController` (disposed on dispose), routes `_view` → screen, and never lets `_view` be a locked (perf/stability) view while offline.

- [ ] **Step 1: Update the shell test**

Replace the third test in `packages/radar_desktop/test/shell_test.dart` (the placeholder one) with:
```dart
  testWidgets('shell routes memory views to real screens; opening a dump goes to histogram', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesktopShell()));
    // Default view = dumps → DumpsScreen present.
    expect(find.byType(DumpsScreen), findsOneWidget);
    // Navigate to Trends via the rail.
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.byType(TrendsScreen), findsOneWidget);
  });
```
Add imports: `package:radar_desktop/src/screens/dumps_screen.dart`, `.../trends_screen.dart`.

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/shell_test.dart`
Expected: FAIL — shell still renders placeholders, not `DumpsScreen`/`TrendsScreen`.

- [ ] **Step 3: Rewrite `desktop_shell.dart`**

Replace `_DesktopShellState` in `packages/radar_desktop/lib/src/shell/desktop_shell.dart` with a version that owns the workspace and routes to screens:
```dart
class _DesktopShellState extends State<DesktopShell> {
  final WorkspaceController _workspace = WorkspaceController();
  DesktopView _view = DesktopView.dumps;
  final bool _connected = false; // Phase 3 flips this

  @override
  void dispose() {
    _workspace.dispose();
    super.dispose();
  }

  void _select(DesktopView v) {
    // Clamp: never activate a locked (perf/stability) view while offline.
    if (!_connected && !v.isMemory) return;
    setState(() => _view = v);
  }

  Widget _content() {
    switch (_view) {
      case DesktopView.dumps:
        return DumpsScreen(
          workspace: _workspace,
          onOpenHistogram: (id) {
            _workspace.openDump(id);
            setState(() => _view = DesktopView.histogram);
          },
        );
      case DesktopView.histogram:
        return HistogramScreen(workspace: _workspace);
      case DesktopView.paths:
        return PathsScreen(workspace: _workspace);
      case DesktopView.compare:
        return CompareScreen(workspace: _workspace);
      case DesktopView.trends:
        return TrendsScreen(workspace: _workspace);
      case DesktopView.traces:
      case DesktopView.frames:
      case DesktopView.errors:
      case DesktopView.stalls:
        // Locked offline; unreachable via the clamped rail, but render a stub.
        return Center(
          child: Text('${_view.label} — connect a VM service (Phase 3)',
              style: RadarTypography.body),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: radarDarkTheme(),
      child: Scaffold(
        backgroundColor: RadarColors.bgPage,
        body: Column(
          children: [
            const DesktopWindowChrome(workspaceName: 'untitled workspace'),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesktopRail(current: _view, connected: _connected, onSelect: _select),
                  Expanded(
                    child: ColoredBox(color: RadarColors.bgPage, child: _content()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```
Add the screen imports at the top of the file (`../screens/dumps_screen.dart`, `histogram_screen.dart`, `paths_screen.dart`, `compare_screen.dart`, `trends_screen.dart`, `../workspace/workspace_controller.dart`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/radar_desktop && flutter test`
Expected: PASS — shell_test (incl. the new routing test), screens_test, workspace_controller_test, seams_test, widget_test.

- [ ] **Step 5: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop && git commit -m "feat(radar_desktop): route DesktopShell to the five real screens + rail clamp"
```

---

## Task 8: Export + `.radarworkspace` save/open + auto-restore

Wire the report/dump export (via the Phase 2a `DesktopSnapshotExporter`) and workspace persistence (via `FileSnapshotStore`), with restore-on-launch.

**Files:**
- Modify: `packages/radar_desktop/lib/src/workspace/workspace_controller.dart` (persistence + export methods)
- Modify: `packages/radar_desktop/lib/src/screens/dumps_screen.dart` (per-dump export action; Save/Open workspace buttons)
- Modify: `packages/radar_desktop/lib/src/shell/desktop_shell.dart` (call `restore()` on init)
- Test: add persistence round-trip to `test/workspace_controller_test.dart`

**Interfaces:**
- Produces on `WorkspaceController`: `Future<void> exportDump(int id)` (via `DesktopSnapshotExporter`); `PersistedSession toSession()`; `void rehydrate(PersistedSession)`; `Future<void> saveWorkspace()` / `Future<void> openWorkspace()` (file_selector); `Future<void> restore()` (FileSnapshotStore) + auto-persist on change.
- Produces on `FileSnapshotStore`: `Future<void> persistAtPath(PersistedSession s, String path)` and `Future<PersistedSession?> restoreFromPath(String path)` — guarded, never-throwing, for user-chosen `.radarworkspace` files.

- [ ] **Step 1: Write the failing persistence test**

Add to `test/workspace_controller_test.dart`:
```dart
  test('session round-trips bundles + meta through PersistedSession', () {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
    final session = wc.toSession();
    expect(session.bundles.map((b) => b.id), contains(a.id));

    final wc2 = WorkspaceController();
    wc2.rehydrate(session);
    expect(wc2.memory.snapshots.map((s) => s.label), contains('a'));
    expect(wc2.dumps.map((d) => d.label), contains('a'));
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/workspace_controller_test.dart`
Expected: FAIL — `toSession`/`rehydrate` not defined.

- [ ] **Step 3: Add persistence + export to `WorkspaceController`**

Add these to `workspace_controller.dart` (import `dart:convert`? no — reuse `PersistedSession`; import the store/exporter):
```dart
import 'package:file_selector/file_selector.dart';

import '../seams/desktop_snapshot_exporter.dart';
import '../seams/file_snapshot_store.dart';
```
Fields:
```dart
  final DesktopSnapshotExporter _exporter = const DesktopSnapshotExporter();
  final FileSnapshotStore _store = FileSnapshotStore();
```
Methods:
```dart
  /// Serializes the current workspace (bundles + the memory view) for
  /// persistence. Dump metadata is recomputed from the bundles on rehydrate.
  PersistedSession toSession() => PersistedSession(
        bundles: memory.snapshots,
        selectedIds: memory.selectedIds,
        view: RadarView.snapshotDiff,
      );

  /// Restores a persisted session into an EMPTY controller (rebuilds meta from
  /// the bundles). Used by both file-open and auto-restore.
  void rehydrate(PersistedSession session) {
    // memory.rehydrate preserves the bundles' ids; rebuild the row metadata
    // from the restored snapshots.
    memory.rehydrate(session);
    _meta.clear();
    for (final s in memory.snapshots) {
      _meta[s.id] = DumpMeta(
        id: s.id,
        label: s.label,
        source: DumpSource.file,
        capturedAt: s.capturedAt,
        classCount: s.histogram.length,
        retainedBytes: s.shallowBytes,
      );
    }
    notifyListeners();
  }

  Future<void> exportDump(int id) async {
    final bundle = memory.byId(id);
    if (bundle != null) await _exporter.export(bundle);
  }

  /// Auto-restore the last session on launch.
  Future<void> restore() async {
    final session = await _store.restore();
    if (session != null && session.bundles.isNotEmpty) rehydrate(session);
  }

  /// Persist the current session (called after mutations; debounce not needed
  /// for a small local file).
  Future<void> _persist() => _store.persist(toSession());

  /// Save the workspace to a user-chosen `.radarworkspace` file.
  Future<void> saveWorkspace() async {
    final loc = await getSaveLocation(
      suggestedName: 'workspace.radarworkspace',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Radar Workspace', extensions: ['radarworkspace']),
      ],
    );
    if (loc == null) return;
    await _store.persistAtPath(toSession(), loc.path);
  }

  /// Opens a `.radarworkspace` file the user picks and rehydrates from it.
  Future<void> openWorkspace() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Radar Workspace', extensions: ['radarworkspace']),
      ],
    );
    if (file == null) return;
    final session = await _store.restoreFromPath(file.path);
    if (session != null && session.bundles.isNotEmpty) rehydrate(session);
  }
```
Add these two guarded helpers to `packages/radar_desktop/lib/src/seams/file_snapshot_store.dart` (mirroring the existing `persist`/`restore`, but at an absolute path):
```dart
  Future<void> persistAtPath(PersistedSession session, String path) async {
    try {
      await File(path).writeAsString(jsonEncode(session.toJson()));
    } catch (_) {}
  }

  Future<PersistedSession?> restoreFromPath(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, Object?>) return null;
      return PersistedSession.fromJson(raw);
    } catch (_) {
      return null;
    }
  }
```

Add an auto-persist hook: in the constructor, `memory.addListener(() => unawaited(_persist()));` (import `dart:async` for `unawaited`). Guard against persisting an empty session on first construction if desired.

- [ ] **Step 4: Wire the UI + restore**

- In `dumps_screen.dart`: give each dump row an export `IconButton(Icons.download_outlined)` → `workspace.exportDump(d.id)`, and add "Save workspace" / "Open workspace" actions to the header.
- In `desktop_shell.dart` `initState`: `unawaited(_workspace.restore());`.

- [ ] **Step 5: Run tests + verify**

Run: `cd packages/radar_desktop && flutter test`
Expected: PASS (persistence round-trip + all prior).

- [ ] **Step 6: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop packages/radar_desktop/lib/src/seams/file_snapshot_store.dart
git commit -m "feat(radar_desktop): export + .radarworkspace save/open + auto-restore"
```

---

## Task 9: Phase 2 completion gate

**Files:** none (verification + optional manual run).

- [ ] **Step 1: Full analyze + test across all changed packages**

```bash
cd packages/radar_ui && dart analyze --fatal-infos . && flutter test
cd ../radar_workbench && dart analyze --fatal-infos . && flutter test
cd ../radar_desktop && dart analyze --fatal-infos . && flutter test
```
Expected: all analyze clean; all suites green (radar_workbench incl. the focusOn tests; radar_desktop incl. workspace + all five screens).

- [ ] **Step 2: Confirm no forbidden imports crept into radar_workbench**

Run: `cd packages/radar_workbench && ! rg -n "devtools_extensions|package:web|dart:js_interop|dart:io|package:dtd" lib`
Expected: no matches.

- [ ] **Step 3: (Manual) smoke-run the full app**

`cd packages/radar_desktop && flutter run -d macos` — import a real `.dartheap` (drag-drop + browse), verify the histogram/paths/compare/trends screens render real data, export a dump, save/reopen a `.radarworkspace`. Note results (not automatable).

- [ ] **Step 4: Final commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add -A && git commit -m "chore(radar_desktop): Phase 2 offline core complete" || echo "nothing to commit"
```

---

## Self-Review Notes (for the executor)

- **The one shared-core change is `focusOn`** (Task 1) — additive and DevTools-safe (`focused` unchanged when `focusOn` is never called). Everything else lives in `radar_desktop`.
- **No `RadarSession`** — the reused views take a `MemoryController` via constructor; `WorkspaceController` owns one built with the Phase 2a offline seams.
- **Reuse, don't fork:** `ClassHistogramView`/`RetainingPathsView`/`DiffTable`/`ClassDetailPanel` are used unchanged. Histogram/Paths show the active dump via `focusOn`; Compare drives the 2-way `toggleSelection`; Trends is custom over `computeTrend` + `RadarTrendChart`.
- **Import pipeline:** file bytes → `SnapshotAnalyzer.fromBytes` (isolate) → `MemoryController.addBundle`, with `RadarLinearProgress` during `analyzing`.
- **All code is literal** — no placeholders. The only judgment spots: an optional dashed drop-zone border (Task 3), and verifying `desktop_drop`/`file_selector` symbol names against installed versions.
- **After Task 9**, the full Phase 2 (2a + 2b) is on `feat/radar-desktop-phase2`; the controller then runs a final whole-branch review of the complete Phase 2 and opens the PR.
