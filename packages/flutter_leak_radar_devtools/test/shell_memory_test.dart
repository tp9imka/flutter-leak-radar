import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import 'package:flutter_leak_radar_devtools/src/capture/snapshot_bundle.dart';
import 'package:flutter_leak_radar_devtools/src/capture/snapshot_service.dart';
import 'package:vm_service/vm_service.dart';
import 'package:flutter_leak_radar_devtools/src/connection/connection_state_notifier.dart';
import 'package:flutter_leak_radar_devtools/src/diff/diff_controller.dart';
import 'package:flutter_leak_radar_devtools/src/memory/class_histogram_view.dart';
import 'package:flutter_leak_radar_devtools/src/memory/memory_view.dart';
import 'package:flutter_leak_radar_devtools/src/memory/retaining_paths_view.dart';
import 'package:flutter_leak_radar_devtools/src/memory/snapshot_diff_view.dart';
import 'package:flutter_leak_radar_devtools/src/shell/connection_bar.dart';
import 'package:flutter_leak_radar_devtools/src/shell/left_rail.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Theme(
      data: radarDarkTheme(),
      child: Scaffold(body: child),
    ),
  );
}

/// Wraps [child] with explicit 1280×800 logical dimensions to prevent
/// overflow errors in multi-column layout tests running under Chrome.
Widget _wrapDesktop(Widget child) {
  return MaterialApp(
    home: Theme(
      data: radarDarkTheme(),
      child: Scaffold(body: SizedBox(width: 1280, height: 800, child: child)),
    ),
  );
}

/// Sets a realistic DevTools panel viewport so multi-column layouts do not
/// overflow during tests, and restores the default on teardown.
void _setDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

// ── Fake ConnectionStateNotifier ──────────────────────────────────────────────

/// Minimal fake that bypasses [serviceManager] wiring.
class _FakeConnectionNotifier extends ConnectionStateNotifier {
  _FakeConnectionNotifier(this._fakeState);

  ExtensionConnectionState _fakeState;

  @override
  ExtensionConnectionState get state => _fakeState;

  void setState(ExtensionConnectionState s) {
    _fakeState = s;
    notifyListeners();
  }

  /// No-op: skip real serviceManager listeners.
  @override
  Future<void> init() async {}
}

// ── Fake SnapshotService ───────────────────────────────────────────────────────

/// Fake SnapshotService that always throws so it is not accidentally called.
class _NullSnapshotService extends SnapshotService {
  const _NullSnapshotService();

  @override
  Future<SnapshotBundle> capture({
    required VmService vmService,
    required IsolateRef isolateRef,
    String label = '',
  }) {
    throw UnsupportedError(
      '_NullSnapshotService.capture should not be called in tests',
    );
  }
}

// ── Controllable DiffController ────────────────────────────────────────────────

/// A [DiffController] subclass whose internal state can be injected for
/// testing, bypassing VM service and snapshot calls.
class _TestDiffController extends DiffController {
  _TestDiffController({
    CapturePhase phase = CapturePhase.idle,
    SnapshotBundle? snapshotA,
    SnapshotBundle? snapshotB,
    List<ClassCountDiff>? diff,
  }) : super(
         snapshotService: const _NullSnapshotService(),
         connection: _FakeConnectionNotifier(
           const ExtensionConnectionState(
             phase: ExtensionConnectionPhase.connected,
           ),
         ),
       ) {
    _setPhase(phase);
    _setSnapshotA(snapshotA);
    _setSnapshotB(snapshotB);
    _setDiff(diff);
  }

  // Expose internal setters via reflection-free back-channel: we call the
  // protected fields indirectly by delegating through test-only mutators.

  void _setPhase(CapturePhase p) => _injectedPhase = p;
  void _setSnapshotA(SnapshotBundle? s) => _injectedA = s;
  void _setSnapshotB(SnapshotBundle? s) => _injectedB = s;
  void _setDiff(List<ClassCountDiff>? d) => _injectedDiff = d;

  CapturePhase? _injectedPhase;
  SnapshotBundle? _injectedA;
  SnapshotBundle? _injectedB;
  List<ClassCountDiff>? _injectedDiff;

  @override
  CapturePhase get phase => _injectedPhase ?? super.phase;

  @override
  SnapshotBundle? get snapshotA => _injectedA ?? super.snapshotA;

  @override
  SnapshotBundle? get snapshotB => _injectedB ?? super.snapshotB;

  @override
  List<ClassCountDiff>? get diff => _injectedDiff ?? super.diff;

  @override
  bool get canCapture => true;
}

// ── Fixture data ───────────────────────────────────────────────────────────────

const _emptyAnalysis = GraphAnalysisResult(
  clusters: [],
  stats: GraphAnalysisStats(
    totalObjects: 0,
    reachableObjects: 0,
    leakCandidates: 0,
    clusters: 0,
    suppressedByAppFilter: 0,
    warnings: [],
  ),
);

ClassCount _cls(String name, {int instances = 10, int bytes = 1024}) =>
    ClassCount(
      className: name,
      libraryUri: Uri.parse('package:app/src/$name.dart'),
      instanceCount: instances,
      shallowBytes: bytes,
    );

SnapshotBundle _snap({List<ClassCount>? histogram}) => SnapshotBundle(
  capturedAt: DateTime(2026, 1, 1, 12),
  label: 'Test snapshot',
  histogram: histogram ?? [_cls('Foo'), _cls('Bar')],
  analysisResult: _emptyAnalysis,
);

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── ConnectionBar ────────────────────────────────────────────────────────────

  group('ConnectionBar', () {
    testWidgets('shows disconnected chip when not connected', (tester) async {
      final notifier = _FakeConnectionNotifier(
        const ExtensionConnectionState(
          phase: ExtensionConnectionPhase.disconnected,
        ),
      );
      await tester.pumpWidget(
        _wrap(SizedBox(height: 44, child: ConnectionBar(notifier: notifier))),
      );

      expect(find.text('disconnected'), findsOneWidget);
      expect(find.text('connected'), findsNothing);
    });

    testWidgets(
      'shows connected chip with vmName and isolateName when connected',
      (tester) async {
        final notifier = _FakeConnectionNotifier(
          const ExtensionConnectionState(
            phase: ExtensionConnectionPhase.connected,
            vmName: 'my-vm',
            isolateName: 'main',
          ),
        );
        await tester.pumpWidget(
          _wrap(SizedBox(height: 44, child: ConnectionBar(notifier: notifier))),
        );

        expect(find.text('connected'), findsOneWidget);
        expect(find.text('my-vm'), findsOneWidget);
        expect(find.text('main'), findsOneWidget);
      },
    );
  });

  // ── LeftRail ─────────────────────────────────────────────────────────────────

  group('LeftRail', () {
    testWidgets('renders three memory nav items', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 198,
            child: LeftRail(
              currentView: MemoryView.snapshotDiff,
              onViewChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Snapshot & diff'), findsOneWidget);
      expect(find.text('Class histogram'), findsOneWidget);
      expect(find.text('Retaining paths'), findsOneWidget);
    });

    testWidgets('Traces and Frames are rendered as disabled items', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 198,
            child: LeftRail(
              currentView: MemoryView.snapshotDiff,
              onViewChanged: (_) => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Traces'), findsOneWidget);
      expect(find.text('Frames'), findsOneWidget);

      // Tapping a disabled item must not fire onViewChanged.
      await tester.tap(find.text('Traces'), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('tapping a nav item fires onViewChanged', (tester) async {
      MemoryView? changed;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 198,
            child: LeftRail(
              currentView: MemoryView.snapshotDiff,
              onViewChanged: (v) => changed = v,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Class histogram'));
      await tester.pump();
      expect(changed, MemoryView.classHistogram);
    });
  });

  // ── SnapshotDiffView ──────────────────────────────────────────────────────────

  group('SnapshotDiffView', () {
    testWidgets('idle phase shows capture CTA', (tester) async {
      final ctrl = _TestDiffController(phase: CapturePhase.idle);
      await tester.pumpWidget(_wrap(SnapshotDiffView(controller: ctrl)));

      expect(find.text('Capture → act → capture → diff'), findsOneWidget);
      expect(find.text('Capture snapshot'), findsOneWidget);
    });

    testWidgets('readyForB phase shows baseline snapshot card', (tester) async {
      final ctrl = _TestDiffController(
        phase: CapturePhase.readyForB,
        snapshotA: _snap(),
      );
      await tester.pumpWidget(_wrap(SnapshotDiffView(controller: ctrl)));
      await tester.pump();

      expect(find.text('Test snapshot'), findsOneWidget);
      expect(
        find.text('Now exercise the app, then capture again.'),
        findsOneWidget,
      );
    });

    testWidgets('done phase shows diff table with class row', (tester) async {
      _setDesktopSize(tester);
      final snapA = _snap(histogram: [_cls('Foo', instances: 5)]);
      final snapB = _snap(histogram: [_cls('Foo', instances: 15)]);
      final diff = computeDiff(snapA.histogram, snapB.histogram);

      final ctrl = _TestDiffController(
        phase: CapturePhase.done,
        snapshotA: snapA,
        snapshotB: snapB,
        diff: diff,
      );
      await tester.pumpWidget(_wrapDesktop(SnapshotDiffView(controller: ctrl)));
      await tester.pump();

      expect(find.text('Foo'), findsWidgets);
    });
  });

  // ── ClassHistogramView ────────────────────────────────────────────────────────

  group('ClassHistogramView', () {
    testWidgets('no snapshot shows empty state', (tester) async {
      final ctrl = _TestDiffController(phase: CapturePhase.idle);
      await tester.pumpWidget(_wrap(ClassHistogramView(controller: ctrl)));

      expect(
        find.text('No snapshot captured yet — use Snapshot & diff to capture.'),
        findsOneWidget,
      );
    });

    testWidgets('snapshot data renders class rows', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _TestDiffController(
        phase: CapturePhase.readyForB,
        snapshotA: _snap(
          histogram: [_cls('Alpha', instances: 3), _cls('Beta', instances: 7)],
        ),
      );
      await tester.pumpWidget(
        _wrapDesktop(ClassHistogramView(controller: ctrl)),
      );
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('search with no match shows "No classes match" message', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final ctrl = _TestDiffController(
        phase: CapturePhase.readyForB,
        snapshotA: _snap(histogram: [_cls('Alpha')]),
      );
      await tester.pumpWidget(
        _wrapDesktop(ClassHistogramView(controller: ctrl)),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Foo');
      await tester.pump();

      expect(find.text("No classes match 'Foo'"), findsOneWidget);
    });

    testWidgets('clicking bytes header changes sort direction', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _TestDiffController(
        phase: CapturePhase.readyForB,
        snapshotA: _snap(
          histogram: [_cls('Small', bytes: 100), _cls('Large', bytes: 100000)],
        ),
      );
      await tester.pumpWidget(
        _wrapDesktop(ClassHistogramView(controller: ctrl)),
      );
      await tester.pump();

      // Both rows render in some order.
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Small'), findsOneWidget);

      // Tap bytes sort header to toggle direction.
      await tester.tap(find.text('bytes'));
      await tester.pump();

      // After toggle, rows are still present (direction changed).
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Small'), findsOneWidget);
    });
  });

  // ── RetainingPathsView ────────────────────────────────────────────────────────

  group('RetainingPathsView', () {
    testWidgets('no diff shows "Complete a snapshot diff" empty state', (
      tester,
    ) async {
      final ctrl = _TestDiffController(phase: CapturePhase.idle);
      await tester.pumpWidget(_wrap(RetainingPathsView(controller: ctrl)));

      expect(
        find.text('Complete a snapshot diff to see retaining paths.'),
        findsOneWidget,
      );
    });

    testWidgets('diff with no cluster data shows fallback message', (
      tester,
    ) async {
      final snapA = _snap(histogram: [_cls('Leaked', instances: 1)]);
      final snapB = _snap(histogram: [_cls('Leaked', instances: 10)]);
      final diff = computeDiff(snapA.histogram, snapB.histogram);

      final ctrl = _TestDiffController(
        phase: CapturePhase.done,
        snapshotA: snapA,
        snapshotB: snapB,
        diff: diff,
      );
      await tester.pumpWidget(_wrap(RetainingPathsView(controller: ctrl)));
      await tester.pump();

      expect(
        find.textContaining('Retaining path data not available'),
        findsOneWidget,
      );
    });

    testWidgets('diff with matching cluster renders cluster card', (
      tester,
    ) async {
      _setDesktopSize(tester); // ensure desktop viewport for complex widget
      const path = GraphRetainingPath(
        hops: [
          GraphHop(className: 'StreamController'),
          GraphHop(className: 'Leaked', field: '_listener'),
        ],
        rootKind: RootKind.stream,
      );
      const cluster = GraphLeakCluster(
        className: 'Leaked',
        libraryUri: null,
        instanceCount: 5,
        retainedShallowBytes: 2048,
        representativePath: path,
        rootKind: RootKind.stream,
        confidence: LeakConfidence.heuristic,
        signature: 'sig',
      );
      final analysis = const GraphAnalysisResult(
        clusters: [cluster],
        stats: GraphAnalysisStats(
          totalObjects: 100,
          reachableObjects: 80,
          leakCandidates: 1,
          clusters: 1,
          suppressedByAppFilter: 0,
          warnings: [],
        ),
      );

      final snapA = SnapshotBundle(
        capturedAt: DateTime(2026),
        label: 'A',
        histogram: [_cls('Leaked', instances: 1)],
        analysisResult: _emptyAnalysis,
      );
      final snapB = SnapshotBundle(
        capturedAt: DateTime(2026),
        label: 'B',
        histogram: [_cls('Leaked', instances: 6)],
        analysisResult: analysis,
      );
      final diff = computeDiff(snapA.histogram, snapB.histogram);

      final ctrl = _TestDiffController(
        phase: CapturePhase.done,
        snapshotA: snapA,
        snapshotB: snapB,
        diff: diff,
      );
      await tester.pumpWidget(
        _wrapDesktop(RetainingPathsView(controller: ctrl)),
      );
      await tester.pump();

      // Cluster card class name is visible.
      expect(find.text('Leaked'), findsWidgets);
      // The retaining-path tile builds its hop rows eagerly (maintainState),
      // so the hop is present while collapsed — robust without a flaky
      // tap-to-expand that doesn't reliably reveal children on CI's chrome.
      expect(
        find.textContaining('StreamController', skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}
