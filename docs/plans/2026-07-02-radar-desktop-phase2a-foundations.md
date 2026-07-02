# Radar Desktop Phase 2a — Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundations for the Radar Desktop offline app — two new `radar_ui` widgets, two `radar_workbench` additions the desktop needs, and a launchable macOS `radar_desktop` package with the custom radar-dark window shell (frameless window + custom title bar + left rail routing to placeholders). No workspace/import/screens yet — that's Phase 2b.

**Architecture:** `radar_desktop` is a new `publish_to: none` Flutter desktop app (macOS-first) that consumes `radar_workbench` (the individual analysis views, controllers, interfaces) and `radar_ui` (design system). It provides its own custom window chrome (via `window_manager`) and its own navigation (`DesktopView` enum + custom rail) — it does NOT reuse `LeakRadarMainScaffold`/`LeftRail`, which are DevTools-specific. This sub-plan lands the shared primitives (`RadarTrendChart`, `RadarLinearProgress`, `MemoryController.addBundle`, `computeTrend`) and the app shell; Phase 2b builds the workspace, file import, and screens on top.

**Tech Stack:** Dart 3.10 / Flutter 3.38, pub workspace + Melos, `radar_workbench` + `radar_ui` + `leak_graph`, `window_manager ^0.5.1`, `file_selector ^1.1.0`, `desktop_drop ^0.7.1`, `path_provider ^2.1.6`, `flutter_test`.

## Global Constraints

- SDK floor `>=3.10.0 <4.0.0`; Flutter floor `>=3.38.0`. All new packages/apps use `resolution: workspace`.
- Strict analysis: `dart analyze --fatal-infos` must pass. `radar_ui` and `radar_workbench` already set `strict-casts`/`strict-inference`/`strict-raw-types`; `radar_desktop` mirrors that `analysis_options.yaml`.
- Formatting: `dart format --set-exit-if-changed .` must pass — run `dart format .` before every commit.
- `radar_ui` MUST stay pure Flutter (no third-party deps) — the two new widgets use only `package:flutter` + the existing tokens.
- `radar_workbench` MUST NOT gain forbidden imports (`devtools_extensions`/`devtools_app_shared`/`dtd`/`package:web`/`dart:io`/`dart:js_interop`) — the additions (`addBundle`, `computeTrend`) are pure Dart/Flutter.
- Design tokens: use `radar_ui`'s `RadarColors`/`RadarTypography`/`RadarDensity`/`RadarSeverity` — never hardcode palette/type/spacing. Radar-dark: base `RadarColors.bgPage` (#0b0e10), surface `bgSurface` (#0e1316), rail `bgRail` (#0a0e0f), accent `accent` (#2fe39b), amber `warning` (#f5b54a) for trends, cyan `info`, red `critical`. Rail width **210px** (desktop, per the mockup — wider than the DevTools `LeftRail`'s 198px).
- `window_manager` calls live ONLY in the app bootstrap (`main()` / a `bootstrapWindow()` helper), NEVER inside widgets — so the shell/rail widgets stay unit-testable on the VM without a real window.
- macOS deployment target stays at the `flutter create` default `10.15` (satisfies all four plugins). Add `com.apple.security.files.user-selected.read-write` to both `macos/Runner/*.entitlements` (needed by `file_selector`/`desktop_drop`).
- `radar_desktop` version `0.1.0`, `publish_to: none`. `radar_ui` bumps to `0.2.0` (new widgets). `radar_workbench` stays `0.1.0` (additive, no breaking change) — bump patch is optional; keep `0.1.0`.
- Commit after every task. Use `dart run melos` (melos is a workspace dev-dep, not on PATH).

---

## File Structure

**`radar_ui` additions:**
```
packages/radar_ui/lib/src/widgets/radar_linear_progress.dart   # NEW — indeterminate bar
packages/radar_ui/lib/src/widgets/radar_trend_chart.dart       # NEW — line+area+markers chart
packages/radar_ui/lib/radar_ui.dart                            # +2 exports
packages/radar_ui/pubspec.yaml                                 # 0.1.1 → 0.2.0
packages/radar_ui/test/radar_linear_progress_test.dart         # NEW
packages/radar_ui/test/radar_trend_chart_test.dart             # NEW
```

**`radar_workbench` additions:**
```
packages/radar_workbench/lib/src/memory/memory_controller.dart # + addBundle()
packages/radar_workbench/lib/src/trend/trend.dart              # NEW — computeTrend + TrendSeries/TrendPoint
packages/radar_workbench/lib/radar_workbench.dart              # +1 export (trend.dart)
packages/radar_workbench/test/memory_controller_test.dart      # + addBundle tests
packages/radar_workbench/test/trend_test.dart                  # NEW
```

**`radar_desktop` (new app):**
```
packages/radar_desktop/pubspec.yaml
packages/radar_desktop/analysis_options.yaml
packages/radar_desktop/macos/…                                 # flutter create runner
packages/radar_desktop/lib/main.dart                           # bootstrap window + runApp
packages/radar_desktop/lib/src/app/bootstrap.dart              # window_manager init (native-only)
packages/radar_desktop/lib/src/app/desktop_view.dart           # DesktopView enum
packages/radar_desktop/lib/src/shell/desktop_window_chrome.dart# custom title bar
packages/radar_desktop/lib/src/shell/desktop_rail.dart         # 210px custom rail
packages/radar_desktop/lib/src/shell/desktop_shell.dart        # scaffold + routing (placeholders)
packages/radar_desktop/lib/src/seams/disconnected_connection.dart # RadarConnection (offline)
packages/radar_desktop/lib/src/seams/offline_snapshot_source.dart # SnapshotSource (offline)
packages/radar_desktop/lib/src/seams/desktop_snapshot_exporter.dart # SnapshotExporter (file_selector)
packages/radar_desktop/lib/src/seams/file_snapshot_store.dart  # SnapshotStore (path_provider)
packages/radar_desktop/test/…                                  # seam + shell widget tests
pubspec.yaml (root)                                            # + packages/radar_desktop in workspace
```

Phase 2b will add `lib/src/workspace/…` and `lib/src/screens/…`.

---

## Task 1: `RadarLinearProgress` (indeterminate bar) in radar_ui

**Files:**
- Create: `packages/radar_ui/lib/src/widgets/radar_linear_progress.dart`
- Test: `packages/radar_ui/test/radar_linear_progress_test.dart`
- Modify: `packages/radar_ui/lib/radar_ui.dart`

**Interfaces:**
- Produces: `class RadarLinearProgress extends StatefulWidget { const RadarLinearProgress({Key? key, double height, Color color, Color trackColor}); }` — an indeterminate left-to-right sweep bar (the "Analyzing…" affordance).

- [ ] **Step 1: Write the failing test**

`packages/radar_ui/test/radar_linear_progress_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  testWidgets('RadarLinearProgress renders and animates without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 200, child: RadarLinearProgress())),
      ),
    );
    expect(find.byType(RadarLinearProgress), findsOneWidget);
    // Advance the animation a couple of frames; must not throw.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_ui && flutter test test/radar_linear_progress_test.dart`
Expected: FAIL — `RadarLinearProgress` not defined.

- [ ] **Step 3: Implement the widget**

`packages/radar_ui/lib/src/widgets/radar_linear_progress.dart`:
```dart
import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';

/// An indeterminate left-to-right sweep bar — the "analyzing…" affordance for
/// long background work (e.g. parsing a large heap dump).
///
/// Compositor-friendly: animates only a translated child, never layout.
class RadarLinearProgress extends StatefulWidget {
  const RadarLinearProgress({
    super.key,
    this.height = 2.0,
    this.color = RadarColors.accent,
    this.trackColor = RadarColors.hairline08,
  });

  final double height;
  final Color color;
  final Color trackColor;

  @override
  State<RadarLinearProgress> createState() => _RadarLinearProgressState();
}

class _RadarLinearProgressState extends State<RadarLinearProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: widget.trackColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 0.0;
              final barWidth = trackWidth * 0.4;
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // Sweep from off-left to off-right.
                  final travel = trackWidth + barWidth;
                  final dx = _controller.value * travel - barWidth;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: barWidth,
                        child: ColoredBox(color: widget.color),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Export it**

Add to `packages/radar_ui/lib/radar_ui.dart` after the `radar_live_pulse_dot.dart` export:
```dart
export 'src/widgets/radar_linear_progress.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/radar_ui && flutter test test/radar_linear_progress_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + format + commit**

```bash
cd packages/radar_ui && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_ui && git commit -m "feat(radar_ui): RadarLinearProgress indeterminate bar"
```

---

## Task 2: `RadarTrendChart` in radar_ui + bump 0.2.0

**Files:**
- Create: `packages/radar_ui/lib/src/widgets/radar_trend_chart.dart`
- Test: `packages/radar_ui/test/radar_trend_chart_test.dart`
- Modify: `packages/radar_ui/lib/radar_ui.dart`, `packages/radar_ui/pubspec.yaml`

**Interfaces:**
- Produces: `class RadarTrendChart extends StatelessWidget { const RadarTrendChart({Key? key, required List<num> series, Color color, double strokeWidth, double height}); }` — a full-size line + filled-area + point-markers chart. Handles empty (renders nothing) and single-point (flat line + one marker). Modeled on `_SparklinePainter` but with padding for markers and a filled area.

- [ ] **Step 1: Write the failing test**

`packages/radar_ui/test/radar_trend_chart_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  testWidgets('renders a multi-point series without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: RadarTrendChart(series: [15, 24, 42, 89]),
          ),
        ),
      ),
    );
    expect(find.byType(RadarTrendChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and single-point series do not throw', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: 300, height: 120, child: RadarTrendChart(series: [])),
              SizedBox(width: 300, height: 120, child: RadarTrendChart(series: [7])),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_ui && flutter test test/radar_trend_chart_test.dart`
Expected: FAIL — `RadarTrendChart` not defined.

- [ ] **Step 3: Implement the widget**

`packages/radar_ui/lib/src/widgets/radar_trend_chart.dart`:
```dart
import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';

/// A full-size trend chart: a stroked line, a translucent filled area beneath
/// it, and a circular marker at each point. Used for plotting a class's
/// instance/byte count across N heap dumps over time (the soak-test view).
///
/// Modeled on [RadarSparkline]'s painter but sized for a panel, with inset
/// padding so end markers aren't clipped and a filled area under the line.
/// Renders nothing for an empty series; a flat line + single marker for one
/// point.
class RadarTrendChart extends StatelessWidget {
  const RadarTrendChart({
    super.key,
    required this.series,
    this.color = RadarColors.warning,
    this.strokeWidth = 2.0,
    this.height = 200.0,
  });

  /// Y values in point order (non-negative).
  final List<num> series;

  /// Line + marker color; area is drawn at 10% opacity of this.
  final Color color;

  final double strokeWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendPainter(
          series: series,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.series,
    required this.color,
    required this.strokeWidth,
  });

  final List<num> series;
  final Color color;
  final double strokeWidth;

  static const _inset = 6.0; // room for end markers
  static const _markerRadius = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final left = _inset;
    final right = size.width - _inset;
    final top = _inset;
    final bottom = size.height - _inset;
    final plotW = (right - left).clamp(0.0, double.infinity);
    final plotH = (bottom - top).clamp(0.0, double.infinity);

    final maxVal = series.reduce((a, b) => a > b ? a : b);
    final minVal = series.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).toDouble();

    Offset toOffset(int i, num v) {
      final x = series.length == 1
          ? left + plotW / 2
          : left + plotW * i / (series.length - 1);
      final y = range == 0
          ? top + plotH / 2
          : top + plotH * (1.0 - (v - minVal) / range);
      return Offset(x, y);
    }

    final points = <Offset>[
      for (var i = 0; i < series.length; i++) toOffset(i, series[i]),
    ];

    // Filled area under the line.
    if (points.length > 1) {
      final area = Path()..moveTo(points.first.dx, bottom);
      for (final p in points) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(points.last.dx, bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.10),
      );
    }

    // The line.
    if (points.length > 1) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        line.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }

    // Markers.
    final markerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    for (final p in points) {
      canvas.drawCircle(p, _markerRadius, markerPaint);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.series != series ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
```

- [ ] **Step 4: Export it + bump the package version**

Add to `packages/radar_ui/lib/radar_ui.dart` (after the `radar_linear_progress.dart` export from Task 1):
```dart
export 'src/widgets/radar_trend_chart.dart';
```
In `packages/radar_ui/pubspec.yaml`, change `version: 0.1.1` → `version: 0.2.0`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/radar_ui && flutter test test/radar_trend_chart_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Analyze + format + commit**

```bash
cd packages/radar_ui && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_ui && git commit -m "feat(radar_ui): RadarTrendChart (line+area+markers); bump 0.2.0"
```

> **Constraint cascade (handled by the controller after this task):** `^0.1.1` does NOT admit `0.2.0` (a 0.x caret locks the minor), and on this Dart/Flutter version workspace `dart pub get` **HARD-FAILS** version solving — it is NOT a non-fatal warning. **Five** packages pin `radar_ui: ^0.1.1`: `radar_workbench`, `flutter_perf_radar`, `flutter_leak_radar`, `flutter_leak_radar_devtools`, `radarscope`. After this task the controller bumped all five to `radar_ui: ^0.2.0` (commit `871eeac`) so `dart pub get` resolves. The implementer of THIS task must NOT touch those five pubspecs — obtain RED/GREEN/analyze evidence with `--no-pub` against the already-resolved graph and report the cascade as a blocker (which is what happened).

---

## Task 3: `MemoryController.addBundle` in radar_workbench

The desktop imports pre-analyzed bundles from files; `MemoryController` currently only gains snapshots via live `capture()`. Add a public method to append an already-built bundle (assigning a session id and auto-selecting the first two, mirroring `capture`'s selection behavior).

**Files:**
- Modify: `packages/radar_workbench/lib/src/memory/memory_controller.dart`
- Modify: `packages/radar_workbench/test/memory_controller_test.dart`

**Interfaces:**
- Consumes: `SnapshotBundle`.
- Produces: `SnapshotBundle MemoryController.addBundle(SnapshotBundle bundle)` — assigns the next session id, appends, auto-selects while `< 2` selected, notifies, and returns the stored (id-assigned) bundle.

- [ ] **Step 1: Write the failing test**

Add this `group` to `packages/radar_workbench/test/memory_controller_test.dart` (it already imports the package + fakes; reuse its existing `_snap`/bundle helpers — if the file builds bundles via a local helper, use it; otherwise build a `SnapshotBundle` with an empty histogram + a minimal `GraphAnalysisResult` exactly as the existing `Session persistence` tests do):
```dart
  group('addBundle (desktop import path)', () {
    test('assigns sequential ids, appends, and auto-selects the first two', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      final a = c.addBundle(_bundle('a'));
      final b = c.addBundle(_bundle('b'));
      final third = c.addBundle(_bundle('c'));

      expect(c.snapshots.map((s) => s.label), ['a', 'b', 'c']);
      expect(a.id, 1);
      expect(b.id, 2);
      expect(third.id, 3);
      // First two auto-selected; third not (selection caps at 2).
      expect(c.selectedIds, [1, 2]);
    });

    test('ids from addBundle do not collide with a later capture id', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      c.addBundle(_bundle('a'));
      final b = c.addBundle(_bundle('b'));
      expect(b.id, 2);
      expect(c.byId(2)?.label, 'b');
    });
  });
```
Add a local helper at the top of `main()` if one does not already exist:
```dart
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
```
(If the test file already defines an equivalent bundle helper, reuse it instead of adding a duplicate.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_workbench && flutter test test/memory_controller_test.dart`
Expected: FAIL — `addBundle` not defined.

- [ ] **Step 3: Implement `addBundle`**

In `packages/radar_workbench/lib/src/memory/memory_controller.dart`, add this public method next to `capture` (it reuses the existing private `_nextId`, `_snapshots`, `_selected` fields and mirrors `capture`'s id-assign + auto-select):
```dart
  /// Appends a pre-built, already-analyzed [bundle] (e.g. imported from a heap
  /// dump file) without going through the VM service. Assigns the next session
  /// id, auto-selects it while fewer than two are selected (so a diff appears
  /// without extra taps, matching [capture]), notifies listeners, and returns
  /// the stored id-assigned bundle.
  SnapshotBundle addBundle(SnapshotBundle bundle) {
    final id = _nextId++;
    final stored = bundle.copyWith(id: id);
    _snapshots.add(stored);
    if (_selected.length < 2) _selected.add(id);
    notifyListeners();
    return stored;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/radar_workbench && flutter test test/memory_controller_test.dart`
Expected: PASS (existing + the new `addBundle` group).

- [ ] **Step 5: Analyze + format + commit**

```bash
cd packages/radar_workbench && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_workbench && git commit -m "feat(radar_workbench): MemoryController.addBundle for file-import path"
```

---

## Task 4: `computeTrend` + `TrendSeries`/`TrendPoint` in radar_workbench

**Files:**
- Create: `packages/radar_workbench/lib/src/trend/trend.dart`
- Test: `packages/radar_workbench/test/trend_test.dart`
- Modify: `packages/radar_workbench/lib/radar_workbench.dart`

**Interfaces:**
- Consumes: `SnapshotBundle` (`capturedAt`, `histogram`), `ClassCount` (`className`, `instanceCount`, `shallowBytes`) from leak_graph.
- Produces:
  - `final class TrendPoint { final DateTime capturedAt; final int instanceCount; final int shallowBytes; }`
  - `final class TrendSeries { final String className; final List<TrendPoint> points; int get firstInstances; int get lastInstances; int get netInstanceDelta; }`
  - `TrendSeries computeTrend(List<SnapshotBundle> bundles, String className)` — sorts bundles by `capturedAt`, reads the matching `ClassCount` per bundle (0 when absent), returns the series.
  - `List<String> growingClassNames(List<SnapshotBundle> bundles)` — classes whose instanceCount is strictly higher in the last-captured bundle than the first (the "growing classes" picker set).

- [ ] **Step 1: Write the failing test**

`packages/radar_workbench/test/trend_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';

SnapshotBundle _b(DateTime at, Map<String, int> counts) => SnapshotBundle(
  capturedAt: at,
  label: at.toIso8601String(),
  histogram: [
    for (final e in counts.entries)
      ClassCount(
        className: e.key,
        libraryUri: Uri.parse('package:app/app.dart'),
        instanceCount: e.value,
        shallowBytes: e.value * 10,
      ),
  ],
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
  final t0 = DateTime(2026, 1, 1, 9);
  final t1 = DateTime(2026, 1, 1, 13);
  final t2 = DateTime(2026, 1, 1, 21);

  test('computeTrend sorts by capturedAt and reads per-class counts', () {
    // Deliberately out of order to prove sorting.
    final bundles = [
      _b(t2, {'Leaky': 42}),
      _b(t0, {'Leaky': 15}),
      _b(t1, {'Leaky': 24}),
    ];
    final s = computeTrend(bundles, 'Leaky');
    expect(s.className, 'Leaky');
    expect(s.points.map((p) => p.instanceCount), [15, 24, 42]);
    expect(s.points.map((p) => p.shallowBytes), [150, 240, 420]);
    expect(s.firstInstances, 15);
    expect(s.lastInstances, 42);
    expect(s.netInstanceDelta, 27);
  });

  test('absent class in a snapshot reads as 0, not dropped', () {
    final bundles = [
      _b(t0, {'Leaky': 5}),
      _b(t1, {'Other': 3}), // Leaky missing here
      _b(t2, {'Leaky': 9}),
    ];
    final s = computeTrend(bundles, 'Leaky');
    expect(s.points.map((p) => p.instanceCount), [5, 0, 9]);
  });

  test('growingClassNames returns classes that grew first→last', () {
    final bundles = [
      _b(t0, {'Grow': 1, 'Flat': 5, 'Shrink': 9}),
      _b(t1, {'Grow': 10, 'Flat': 5, 'Shrink': 2}),
    ];
    final names = growingClassNames(bundles);
    expect(names, contains('Grow'));
    expect(names, isNot(contains('Flat')));
    expect(names, isNot(contains('Shrink')));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_workbench && flutter test test/trend_test.dart`
Expected: FAIL — `computeTrend` not defined.

- [ ] **Step 3: Implement it**

`packages/radar_workbench/lib/src/trend/trend.dart`:
```dart
import 'package:leak_graph/leak_graph.dart';

import '../capture/snapshot_bundle.dart';

/// One point in a class's trend: its instance/byte count in a single snapshot.
final class TrendPoint {
  const TrendPoint({
    required this.capturedAt,
    required this.instanceCount,
    required this.shallowBytes,
  });
  final DateTime capturedAt;
  final int instanceCount;
  final int shallowBytes;
}

/// A single class's instance/byte counts across N snapshots, oldest first.
final class TrendSeries {
  const TrendSeries({required this.className, required this.points});
  final String className;
  final List<TrendPoint> points;

  int get firstInstances => points.isEmpty ? 0 : points.first.instanceCount;
  int get lastInstances => points.isEmpty ? 0 : points.last.instanceCount;
  int get netInstanceDelta => lastInstances - firstInstances;
}

int _countIn(SnapshotBundle bundle, String className) {
  for (final c in bundle.histogram) {
    if (c.className == className) return c.instanceCount;
  }
  return 0;
}

int _bytesIn(SnapshotBundle bundle, String className) {
  for (final c in bundle.histogram) {
    if (c.className == className) return c.shallowBytes;
  }
  return 0;
}

/// Builds a [TrendSeries] for [className] across [bundles], ordered by
/// [SnapshotBundle.capturedAt]. Snapshots where the class is absent read as 0
/// (matching `computeDiff`'s zero-baseline convention) rather than being
/// dropped, so a class that momentarily vanishes doesn't break the line.
TrendSeries computeTrend(List<SnapshotBundle> bundles, String className) {
  final ordered = [...bundles]
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  return TrendSeries(
    className: className,
    points: [
      for (final b in ordered)
        TrendPoint(
          capturedAt: b.capturedAt,
          instanceCount: _countIn(b, className),
          shallowBytes: _bytesIn(b, className),
        ),
    ],
  );
}

/// Class names whose instance count is strictly higher in the last-captured
/// bundle than in the first — the candidate set for the Trends class picker.
List<String> growingClassNames(List<SnapshotBundle> bundles) {
  if (bundles.length < 2) return const [];
  final ordered = [...bundles]
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  final first = ordered.first;
  final last = ordered.last;
  final names = <String>{
    for (final c in first.histogram) c.className,
    for (final c in last.histogram) c.className,
  };
  final growing = <String>[
    for (final name in names)
      if (_countIn(last, name) > _countIn(first, name)) name,
  ]..sort(
      (a, b) => (_countIn(last, b) - _countIn(first, b))
          .compareTo(_countIn(last, a) - _countIn(first, a)),
    );
  return growing;
}
```

- [ ] **Step 4: Export it**

Add to `packages/radar_workbench/lib/radar_workbench.dart` (alphabetical among the `src/…` exports, e.g. after the `src/stability/…` exports or grouped logically):
```dart
export 'src/trend/trend.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/radar_workbench && flutter test test/trend_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Analyze + format + commit**

```bash
cd packages/radar_workbench && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_workbench && git commit -m "feat(radar_workbench): computeTrend + TrendSeries for the Trends view"
```

---

## Task 5: Scaffold the `radar_desktop` package + macOS runner + workspace wiring

**Files:**
- Create (via `flutter create`): `packages/radar_desktop/` (macos runner, lib/main.dart, pubspec.yaml, test/)
- Modify: `packages/radar_desktop/pubspec.yaml`, create `packages/radar_desktop/analysis_options.yaml`, `packages/radar_desktop/lib/main.dart` (placeholder), macOS entitlements
- Modify: root `pubspec.yaml` (workspace list)

**Interfaces:**
- Produces: a resolvable `radar_desktop` workspace member that builds a trivial placeholder app and has a green (empty) test.

- [ ] **Step 1: Scaffold the package with a macOS runner**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/packages
flutter create --platforms=macos --org com.tp9imka --project-name radar_desktop radar_desktop
```
This generates `radar_desktop/{lib/main.dart,test/widget_test.dart,pubspec.yaml,macos/…}`.

- [ ] **Step 2: Replace the pubspec**

Overwrite `packages/radar_desktop/pubspec.yaml`:
```yaml
name: radar_desktop
description: >-
  Standalone macOS-first desktop app for offline heap-dump leak/memory
  analysis, built on radar_workbench + radar_ui.
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
  radar_workbench: ^0.1.0
  radar_ui: ^0.2.0
  leak_graph: ^0.2.2
  vm_service: ^15.0.0
  window_manager: ^0.5.1
  file_selector: ^1.1.0
  desktop_drop: ^0.7.1
  path_provider: ^2.1.6
  path: ^1.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 3: Add analysis_options mirroring the workspace**

`packages/radar_desktop/analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

- [ ] **Step 4: Add the package to the workspace**

In the root `pubspec.yaml`, add `- packages/radar_desktop` to the `workspace:` list (after `packages/radar_workbench`).

- [ ] **Step 5: Add the macOS file-access entitlement**

In BOTH `packages/radar_desktop/macos/Runner/DebugProfile.entitlements` and `packages/radar_desktop/macos/Runner/Release.entitlements`, add (inside the top-level `<dict>`):
```xml
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
```
(Keep the existing `com.apple.security.app-sandbox` key.)

- [ ] **Step 6: Replace main.dart with a placeholder**

`packages/radar_desktop/lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  runApp(const RadarDesktopApp());
}

/// Placeholder app — the real window shell arrives in Task 7.
class RadarDesktopApp extends StatelessWidget {
  const RadarDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: radarDarkTheme(),
      home: const Scaffold(
        body: Center(child: Text('Radar Desktop')),
      ),
    );
  }
}
```

- [ ] **Step 7: Replace the generated widget test**

Overwrite `packages/radar_desktop/test/widget_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/main.dart';

void main() {
  testWidgets('placeholder app boots', (tester) async {
    await tester.pumpWidget(const RadarDesktopApp());
    expect(find.text('Radar Desktop'), findsOneWidget);
  });
}
```

- [ ] **Step 8: Resolve, analyze, test**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart pub get
cd packages/radar_desktop && dart analyze --fatal-infos . && flutter test
```
Expected: `dart pub get` resolves (radar_desktop + the four desktop plugins downloaded); analyze clean; test PASS. If `dart pub get` reports a radar_ui `^0.1.1` vs `0.2.0` constraint issue that BLOCKS resolution (not just a warning), change `radar_ui: ^0.1.1` → `radar_ui: ^0.2.0` in `packages/radar_desktop/pubspec.yaml` and re-run (radar_desktop is new, so it may as well require the current radar_ui).

- [ ] **Step 9: Format + commit**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop pubspec.yaml && git commit -m "feat(radar_desktop): scaffold package + macOS runner + workspace wiring"
```

---

## Task 6: Offline seams — connection, source, exporter, store

Four small host-implementations of the `radar_workbench` interfaces for the offline desktop. `DisconnectedRadarConnection` + `OfflineSnapshotSource` satisfy `MemoryController`'s constructor offline (no live VM); `DesktopSnapshotExporter` + `FileSnapshotStore` provide native file I/O. (The live `VmServiceUriConnection` is Phase 3.)

**Files:**
- Create: `packages/radar_desktop/lib/src/seams/disconnected_connection.dart`
- Create: `packages/radar_desktop/lib/src/seams/offline_snapshot_source.dart`
- Create: `packages/radar_desktop/lib/src/seams/desktop_snapshot_exporter.dart`
- Create: `packages/radar_desktop/lib/src/seams/file_snapshot_store.dart`
- Test: `packages/radar_desktop/test/seams_test.dart`

**Interfaces:**
- Produces:
  - `class DisconnectedRadarConnection extends ChangeNotifier implements RadarConnection` — always disconnected; `vmService`/`isolateRef` null.
  - `class OfflineSnapshotSource implements SnapshotSource` — `capture` returns `SnapshotBundle.failed`.
  - `class DesktopSnapshotExporter implements SnapshotExporter` — writes JSON via `file_selector`'s `getSaveLocation`.
  - `class FileSnapshotStore implements SnapshotStore` — persists `PersistedSession` JSON under `getApplicationSupportDirectory()`.

- [ ] **Step 1: Write the failing test (seams that are unit-testable)**

`packages/radar_desktop/test/seams_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/disconnected_connection.dart';
import 'package:radar_desktop/src/seams/offline_snapshot_source.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  test('DisconnectedRadarConnection is always disconnected', () {
    final c = DisconnectedRadarConnection();
    expect(c.state.phase, RadarConnectionPhase.disconnected);
    expect(c.vmService, isNull);
    expect(c.isolateRef, isNull);
  });

  test('OfflineSnapshotSource.capture returns a failed bundle, never throws', () async {
    const source = OfflineSnapshotSource();
    final bundle = await source.capture(label: 'x');
    expect(bundle.label, 'x');
    expect(bundle.analysisResult.clusters, isEmpty);
  });

  test('MemoryController wires cleanly with the offline seams', () {
    final controller = MemoryController(
      snapshotSource: const OfflineSnapshotSource(),
      connection: DisconnectedRadarConnection(),
    );
    expect(controller.canCapture, isFalse);
    expect(controller.snapshots, isEmpty);
  });
}
```
(`DesktopSnapshotExporter`/`FileSnapshotStore` touch native file dialogs / the filesystem and aren't unit-tested here; they're exercised via Phase 2b integration + manual runs. Keep them minimal and obviously-correct.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/seams_test.dart`
Expected: FAIL — the seam classes aren't defined.

- [ ] **Step 3: Implement the four seams**

`packages/radar_desktop/lib/src/seams/disconnected_connection.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// The offline desktop connection: permanently disconnected. Phase 3 replaces
/// this with a live `VmServiceUriConnection`. Never notifies (its state is
/// constant), but implements [Listenable] via [ChangeNotifier] so consumers
/// (e.g. [MemoryController], `ConnectionBar`) can subscribe uniformly.
class DisconnectedRadarConnection extends ChangeNotifier
    implements RadarConnection {
  @override
  RadarConnectionState get state =>
      const RadarConnectionState(phase: RadarConnectionPhase.disconnected);

  @override
  VmService? get vmService => null;

  @override
  IsolateRef? get isolateRef => null;
}
```

`packages/radar_desktop/lib/src/seams/offline_snapshot_source.dart`:
```dart
import 'package:radar_workbench/radar_workbench.dart';

/// Offline stand-in for a live capture source. `MemoryController` requires a
/// [SnapshotSource], but the offline desktop never calls `capture()` (it
/// imports pre-analyzed bundles via `MemoryController.addBundle`). If it is
/// called, it fails cleanly rather than throwing.
class OfflineSnapshotSource implements SnapshotSource {
  const OfflineSnapshotSource();

  @override
  Future<SnapshotBundle> capture({String label = ''}) async =>
      SnapshotBundle.failed(
        label: label,
        message: 'Offline — connect a VM service to capture live heaps.',
      );
}
```

`packages/radar_desktop/lib/src/seams/desktop_snapshot_exporter.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// Exports a snapshot bundle as a JSON file via a native save dialog.
class DesktopSnapshotExporter implements SnapshotExporter {
  const DesktopSnapshotExporter();

  @override
  Future<void> export(SnapshotBundle bundle, {String? suggestedName}) async {
    final base = suggestedName ?? 'heap_${bundle.id}_${bundle.label}';
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final location = await getSaveLocation(
      suggestedName: '$safe.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null) return; // user cancelled
    final json = const JsonEncoder.withIndent('  ').convert(bundle.toJson());
    await File(location.path).writeAsString(json);
  }
}
```

`packages/radar_desktop/lib/src/seams/file_snapshot_store.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// Auto-restore session store backed by a JSON file under the app support
/// directory (`~/Library/Application Support/<bundle-id>/`). Degrades
/// gracefully — never throws into the UI; a read/parse failure yields null.
class FileSnapshotStore implements SnapshotStore {
  FileSnapshotStore({this.fileName = 'radar_desktop_session.json'});

  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, fileName));
  }

  @override
  Future<void> persist(PersistedSession session) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(session.toJson()));
    } catch (_) {
      // Best-effort persistence; ignore I/O failures.
    }
  }

  @override
  Future<PersistedSession?> restore() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, Object?>) return null;
      return PersistedSession.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/radar_desktop && flutter test test/seams_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop && git commit -m "feat(radar_desktop): offline seams (connection/source/exporter/store)"
```

---

## Task 7: Custom window shell — chrome + rail + routing (placeholders)

Build the radar-dark window: frameless (`window_manager`, traffic lights kept) + a custom title bar + a 210px left rail (`DesktopView`) routing to placeholder panels. `window_manager` init lives only in the bootstrap; the shell/rail/chrome widgets are pure and VM-testable.

**Files:**
- Create: `packages/radar_desktop/lib/src/app/desktop_view.dart`
- Create: `packages/radar_desktop/lib/src/app/bootstrap.dart`
- Create: `packages/radar_desktop/lib/src/shell/desktop_window_chrome.dart`
- Create: `packages/radar_desktop/lib/src/shell/desktop_rail.dart`
- Create: `packages/radar_desktop/lib/src/shell/desktop_shell.dart`
- Modify: `packages/radar_desktop/lib/main.dart`
- Test: `packages/radar_desktop/test/shell_test.dart`

**Interfaces:**
- Produces:
  - `enum DesktopView { dumps, histogram, paths, compare, trends, traces, frames, errors, stalls }` with `bool get isMemory`, `bool get isPerf`, `bool get isStability`, `String get label`.
  - `Future<void> bootstrapWindow()` — `window_manager` init (native-only; guarded so it's a no-op off-desktop).
  - `class DesktopWindowChrome extends StatelessWidget` — the draggable title bar (traffic-light gutter + centered `"<workspace> — Radar Desktop"`).
  - `class DesktopRail extends StatelessWidget { required DesktopView current; required ValueChanged<DesktopView> onSelect; bool connected; }` — 210px rail, MEMORY group always active, PERFORMANCE/STABILITY locked when `!connected`.
  - `class DesktopShell extends StatefulWidget` — composes chrome + rail + a placeholder content panel per view.

- [ ] **Step 1: Write the failing shell test**

`packages/radar_desktop/test/shell_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/app/desktop_view.dart';
import 'package:radar_desktop/src/shell/desktop_rail.dart';
import 'package:radar_desktop/src/shell/desktop_shell.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  testWidgets('rail lists the five memory destinations and reports taps', (tester) async {
    DesktopView? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(
          body: DesktopRail(
            current: DesktopView.dumps,
            connected: false,
            onSelect: (v) => tapped = v,
          ),
        ),
      ),
    );
    for (final label in ['Dumps', 'Class histogram', 'Retaining paths', 'Compare', 'Trends']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Trends'));
    expect(tapped, DesktopView.trends);
  });

  testWidgets('performance/stability items are locked when offline', (tester) async {
    DesktopView? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(
          body: DesktopRail(
            current: DesktopView.dumps,
            connected: false,
            onSelect: (v) => tapped = v,
          ),
        ),
      ),
    );
    // Tapping a locked Performance item does nothing.
    await tester.tap(find.text('Traces'));
    expect(tapped, isNull);
  });

  testWidgets('shell renders the placeholder for the selected view', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesktopShell()));
    expect(find.byType(DesktopRail), findsOneWidget);
    // Default view is dumps; its placeholder names it.
    expect(find.textContaining('Dumps'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/radar_desktop && flutter test test/shell_test.dart`
Expected: FAIL — the shell types aren't defined.

- [ ] **Step 3: Implement `desktop_view.dart`**

`packages/radar_desktop/lib/src/app/desktop_view.dart`:
```dart
/// Navigation destinations in the Radar Desktop rail. Distinct from
/// `radar_workbench`'s `RadarView` because the desktop adds Dumps/Compare/
/// Trends (offline workspace features) and reuses only the shared VIEWS.
enum DesktopView {
  dumps,
  histogram,
  paths,
  compare,
  trends,
  traces,
  frames,
  errors,
  stalls;

  bool get isMemory =>
      this == dumps ||
      this == histogram ||
      this == paths ||
      this == compare ||
      this == trends;
  bool get isPerf => this == traces || this == frames;
  bool get isStability => this == errors || this == stalls;

  String get label => switch (this) {
        DesktopView.dumps => 'Dumps',
        DesktopView.histogram => 'Class histogram',
        DesktopView.paths => 'Retaining paths',
        DesktopView.compare => 'Compare',
        DesktopView.trends => 'Trends',
        DesktopView.traces => 'Traces',
        DesktopView.frames => 'Frames',
        DesktopView.errors => 'Errors',
        DesktopView.stalls => 'Stalls',
      };
}
```

- [ ] **Step 4: Implement `bootstrap.dart` (window_manager, native-only)**

`packages/radar_desktop/lib/src/app/bootstrap.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Initializes the frameless window. macOS keeps its traffic-light buttons
/// (`TitleBarStyle.hidden` hides only the title text/bar chrome, not the
/// window buttons); a custom title bar is drawn by [DesktopWindowChrome].
///
/// No-op on non-desktop targets (e.g. the VM test host), so widget tests never
/// touch the plugin.
Future<void> bootstrapWindow() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.macOS &&
      defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return;
  }
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1180, 760),
    minimumSize: Size(920, 600),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
    title: 'Radar Desktop',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
```

- [ ] **Step 5: Implement `desktop_window_chrome.dart`**

> `DragToMoveArea` is a `window_manager` *widget* (not a direct plugin call); building it is safe on the VM test host — only an actual drag invokes `windowManager.startDragging()`. If the shell widget test (Task 7 Step 1) throws because `DragToMoveArea` touches a platform channel at build time on the VM, wrap it with a platform guard: use `DragToMoveArea` only when `!kIsWeb && defaultTargetPlatform` is a desktop platform, else render the same title-bar `Container` without the drag wrapper. Prefer the plain form as written first; add the guard only if the test forces it, and note it in the report.

`packages/radar_desktop/lib/src/shell/desktop_window_chrome.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:window_manager/window_manager.dart';

/// The custom title bar: a draggable strip with a left gutter reserved for the
/// macOS traffic lights and a centered "<workspace> — Radar Desktop" label.
class DesktopWindowChrome extends StatelessWidget {
  const DesktopWindowChrome({super.key, required this.workspaceName});

  final String workspaceName;

  static const double height = 38;
  static const double _trafficLightGutter = 78; // room for macOS buttons

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Container(
        height: height,
        color: RadarColors.bgPanel,
        alignment: Alignment.center,
        child: Row(
          children: [
            const SizedBox(width: _trafficLightGutter),
            Expanded(
              child: Center(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: workspaceName,
                        style: RadarTypography.appBarTitle,
                      ),
                      TextSpan(
                        text: '  —  Radar Desktop',
                        style: RadarTypography.appBarTitle.copyWith(
                          color: RadarColors.text40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: _trafficLightGutter),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement `desktop_rail.dart`**

`packages/radar_desktop/lib/src/shell/desktop_rail.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../app/desktop_view.dart';

/// The 210px left navigation. MEMORY group is always active; PERFORMANCE and
/// STABILITY are locked (dimmed, non-interactive) until [connected].
class DesktopRail extends StatelessWidget {
  const DesktopRail({
    super.key,
    required this.current,
    required this.onSelect,
    required this.connected,
  });

  final DesktopView current;
  final ValueChanged<DesktopView> onSelect;
  final bool connected;

  static const double width = 210;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: RadarColors.bgRail,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _group('MEMORY'),
          for (final v in const [
            DesktopView.dumps,
            DesktopView.histogram,
            DesktopView.paths,
            DesktopView.compare,
            DesktopView.trends,
          ])
            _item(v, enabled: true),
          const SizedBox(height: 14),
          _group('PERFORMANCE', locked: !connected),
          for (final v in const [DesktopView.traces, DesktopView.frames])
            _item(v, enabled: connected),
          const SizedBox(height: 14),
          _group('STABILITY', locked: !connected),
          for (final v in const [DesktopView.errors, DesktopView.stalls])
            _item(v, enabled: connected),
        ],
      ),
    );
  }

  Widget _group(String title, {bool locked = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: Row(
          children: [
            Text(
              title,
              style: RadarTypography.monoLabel.copyWith(
                color: RadarColors.text25,
                letterSpacing: 1,
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_outline, size: 11, color: RadarColors.text15),
            ],
          ],
        ),
      );

  Widget _item(DesktopView v, {required bool enabled}) {
    final active = v == current;
    final color = !enabled
        ? RadarColors.text15
        : active
            ? RadarColors.accent
            : RadarColors.text60;
    return InkWell(
      onTap: enabled ? () => onSelect(v) : null,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: active ? RadarColors.accentSubtle : null,
        alignment: Alignment.centerLeft,
        child: Text(v.label, style: RadarTypography.monoBody.copyWith(color: color)),
      ),
    );
  }
}
```

- [ ] **Step 7: Implement `desktop_shell.dart`**

`packages/radar_desktop/lib/src/shell/desktop_shell.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../app/desktop_view.dart';
import 'desktop_rail.dart';
import 'desktop_window_chrome.dart';

/// The window scaffold: custom title bar on top, rail on the left, content on
/// the right. Content is a placeholder per view in Phase 2a — Phase 2b swaps in
/// the real workspace + screens.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  DesktopView _view = DesktopView.dumps;

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
                  DesktopRail(
                    current: _view,
                    connected: false,
                    onSelect: (v) => setState(() => _view = v),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: RadarColors.bgPage,
                      child: Center(
                        child: Text(
                          '${_view.label} — coming in Phase 2b',
                          style: RadarTypography.body,
                        ),
                      ),
                    ),
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

- [ ] **Step 8: Wire `main.dart` to the shell**

Overwrite `packages/radar_desktop/lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import 'src/app/bootstrap.dart';
import 'src/shell/desktop_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapWindow();
  runApp(const RadarDesktopApp());
}

class RadarDesktopApp extends StatelessWidget {
  const RadarDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Radar Desktop',
      theme: radarDarkTheme(),
      home: const DesktopShell(),
    );
  }
}
```
Update `test/widget_test.dart` (from Task 5) — the placeholder now shows the shell, so replace its assertion:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/main.dart';
import 'package:radar_desktop/src/shell/desktop_rail.dart';

void main() {
  testWidgets('app boots into the desktop shell', (tester) async {
    await tester.pumpWidget(const RadarDesktopApp());
    expect(find.byType(DesktopRail), findsOneWidget);
  });
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `cd packages/radar_desktop && flutter test`
Expected: PASS (shell_test + widget_test + seams_test).

- [ ] **Step 10: Analyze + format + commit**

```bash
cd packages/radar_desktop && dart analyze --fatal-infos .
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add packages/radar_desktop && git commit -m "feat(radar_desktop): custom radar-dark window shell + rail + routing"
```

---

## Task 8: Foundations gate

**Files:** none (verification + commit only).

- [ ] **Step 1: Verify each package analyzes clean and tests green**

```bash
cd packages/radar_ui && dart analyze --fatal-infos . && flutter test
cd ../radar_workbench && dart analyze --fatal-infos . && flutter test
cd ../radar_desktop && dart analyze --fatal-infos . && flutter test
```
Expected: all three analyze clean; `radar_ui` tests green (incl. the two new widgets), `radar_workbench` green (incl. addBundle + trend), `radar_desktop` green (seams + shell).

- [ ] **Step 2: Confirm no forbidden imports leaked into radar_workbench**

Run: `cd packages/radar_workbench && ! rg -n "devtools_extensions|package:web|dart:js_interop|dart:io|package:dtd" lib`
Expected: no matches (exit non-zero from `rg` inverted by `!` → command succeeds).

- [ ] **Step 3: (Optional, manual) smoke-run the app**

`cd packages/radar_desktop && flutter run -d macos` — confirm the frameless window opens with traffic lights, the custom title bar drags the window, and the rail switches placeholder panels. (Not automatable in CI; note the result.)

- [ ] **Step 4: Final commit if anything was formatted**

```bash
cd /Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar && dart format .
git add -A && git commit -m "chore(radar_desktop): Phase 2a foundations complete" || echo "nothing to commit"
```

---

## Self-Review Notes (for the executor)

- **Reuse boundary:** the desktop deliberately does NOT reuse `LeftRail`/`LeakRadarMainScaffold` (DevTools-specific, hardcoded nav). It reuses only the individual workbench VIEWS in Phase 2b, driven by a `MemoryController` populated via the new `addBundle`.
- **`window_manager` isolation:** all plugin calls are in `bootstrap.dart` (guarded by platform check) — the shell/rail/chrome widgets are pure and tested on the VM without a window. Do not call `windowManager` from any widget.
- **`radar_ui` 0.2.0 constraint:** downstream packages still declare `radar_ui: ^0.1.1`; the workspace resolves by path so this is fine locally. Publishing/constraint-sync is out of scope for Phase 2a.
- **Trends math:** `computeTrend` reads `ClassCount` straight from each `SnapshotBundle.histogram` (0 when absent) — NOT `computeDiff` (which drops classes missing from `after`).
- **Phase 2b** builds on this: `WorkspaceController` (dump list + multi-select + recent + `.radarworkspace`) wrapping the `MemoryController`, file import (drag-drop + browse → `SnapshotAnalyzer.fromBytes` → `addBundle` + `RadarLinearProgress`), and the five real screens (Dumps, Histogram, Retaining paths, Compare, Trends) replacing the placeholders.
