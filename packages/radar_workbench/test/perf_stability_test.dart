import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

import 'package:radar_workbench/src/perf/perf_data_controller.dart';
import 'package:radar_workbench/src/perf/perf_snapshot_dto.dart';
import 'package:radar_workbench/src/perf/traces_view.dart';
import 'package:radar_workbench/src/perf/frames_view.dart';
import 'package:radar_workbench/src/stability/errors_view.dart';
import 'package:radar_workbench/src/stability/stalls_view.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Theme(
      data: radarDarkTheme(),
      child: Scaffold(body: child),
    ),
  );
}

Widget _wrapDesktop(Widget child) {
  return MaterialApp(
    home: Theme(
      data: radarDarkTheme(),
      child: Scaffold(body: SizedBox(width: 1280, height: 800, child: child)),
    ),
  );
}

void _setDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

// ── Fake PerfDataController ────────────────────────────────────────────────────

/// Fake [PerfDataController] that bypasses any VM service calls.
/// Inject [state] and [snapshot] directly.
class _FakePerfController extends PerfDataController {
  _FakePerfController({
    PerfLoadState initialState = PerfLoadState.idle,
    PerfSnapshotDto? initialSnapshot,
  }) : _fakeState = initialState,
       _fakeSnapshot = initialSnapshot,
       super(callExtension: (_) async => {});

  PerfLoadState _fakeState;
  PerfSnapshotDto? _fakeSnapshot;
  String? _fakeError;

  @override
  PerfLoadState get loadState => _fakeState;

  @override
  PerfSnapshotDto? get snapshot => _fakeSnapshot;

  @override
  String? get errorMessage => _fakeError;

  void inject({
    required PerfLoadState state,
    PerfSnapshotDto? snapshot,
    String? errorMessage,
  }) {
    _fakeState = state;
    _fakeSnapshot = snapshot;
    _fakeError = errorMessage;
    notifyListeners();
  }

  @override
  Future<void> refresh() async {}

  /// Number of times [resetFrames] has been called — lets tests verify
  /// the reset button is wired to the controller without touching the
  /// real VM service extension machinery.
  int resetFramesCallCount = 0;

  @override
  Future<void> resetFrames() async {
    resetFramesCallCount++;
  }
}

// ── Fixture builders ───────────────────────────────────────────────────────────

TraceKeyDto _traceKey({
  String name = 'db.query',
  String? category = 'db',
  int count = 10,
  int mean = 1200,
  int max = 8000,
  int total = 12000,
  int? p50,
  int? p95,
  int? p99,
  int? interval,
  double? rate,
  int errors = 0,
}) => TraceKeyDto(
  name: name,
  category: category,
  count: count,
  meanMicros: mean,
  maxMicros: max,
  totalMicros: total,
  p50: p50,
  p95: p95,
  p99: p99,
  avgInterCallIntervalMicros: interval,
  callsPerSecond: rate,
  errorCount: errors,
  firstStartMicros: 1000000,
  lastStartMicros: 2000000,
);

TracesDto _traces({List<TraceKeyDto>? keys, int drops = 0}) =>
    TracesDto(totalDropCount: drops, keys: keys ?? []);

FramesDto _frames({
  int frameCount = 300,
  int jankCount = 4,
  int? buildP50 = 800,
  int? buildP95 = 3000,
  int? buildP99 = 6000,
  int? rasterP50 = 900,
  int? rasterP95 = 3200,
  int? rasterP99 = 6500,
  int? totalP50 = 1800,
  int? totalP95 = 6000,
  int? totalP99 = 12000,
  List<RecentFrameDto>? recent,
}) => FramesDto(
  frameCount: frameCount,
  jankCount: jankCount,
  buildP50: buildP50,
  buildP95: buildP95,
  buildP99: buildP99,
  rasterP50: rasterP50,
  rasterP95: rasterP95,
  rasterP99: rasterP99,
  totalP50: totalP50,
  totalP95: totalP95,
  totalP99: totalP99,
  recentFrames: recent ?? [],
);

StabilityDto _stability({
  int errors = 0,
  int stalls = 0,
  List<ErrorRecordDto>? recentErrors,
  List<StallRecordDto>? recentStalls,
}) => StabilityDto(
  errorCount: errors,
  stallCount: stalls,
  recentErrors: recentErrors ?? [],
  recentStalls: recentStalls ?? [],
);

PerfSnapshotDto _snapshot({
  TracesDto? traces,
  FramesDto? frames,
  StabilityDto? stability,
}) => PerfSnapshotDto(
  traces: traces ?? _traces(),
  frames: frames ?? _frames(),
  stability: stability ?? _stability(),
);

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── PerfSnapshotDto parsing ──────────────────────────────────────────────────

  group('PerfSnapshotDto.tryFromJson', () {
    test('parses a complete snapshot correctly', () {
      final json = {
        'traces': {
          'totalDropCount': 0,
          'keys': [
            {
              'name': 'db.query',
              'category': 'db',
              'count': 42,
              'meanMicros': 1200,
              'maxMicros': 8000,
              'totalMicros': 50400,
              'p50': 1100,
              'p95': 4000,
              'p99': 7000,
              'avgInterCallIntervalMicros': 500,
              'callsPerSecond': 2.0,
              'errorCount': 1,
              'firstStartMicros': 1000000,
              'lastStartMicros': 22000000,
            },
          ],
        },
        'frames': {
          'frameCount': 300,
          'jankCount': 4,
          'buildP50': 800,
          'buildP95': 3000,
          'buildP99': 6000,
          'rasterP50': 900,
          'rasterP95': 3200,
          'rasterP99': 6500,
          'totalP50': 1800,
          'totalP95': 6000,
          'totalP99': 12000,
          'recentFrames': [
            {'totalMicros': 16200, 'buildMicros': 800, 'rasterMicros': 900},
          ],
        },
        'stability': {
          'errorCount': 2,
          'stallCount': 1,
          'recentErrors': [
            {
              'message': 'Connection refused',
              'context': 'FlutterError',
              'clockMicros': 123456789,
              'stackTraceString': '#0 main()',
            },
          ],
          'recentStalls': [
            {'durationMicros': 320000, 'clockMicros': 987654321},
          ],
        },
      };

      final dto = PerfSnapshotDto.tryFromJson(json);
      expect(dto, isNotNull);
      expect(dto!.traces.keys.length, 1);
      expect(dto.traces.keys.first.name, 'db.query');
      expect(dto.traces.keys.first.p50, 1100);
      expect(dto.frames.frameCount, 300);
      expect(dto.frames.jankCount, 4);
      expect(dto.frames.recentFrames.length, 1);
      expect(dto.stability.errorCount, 2);
      expect(dto.stability.recentErrors.first.message, 'Connection refused');
      expect(dto.stability.recentStalls.first.durationMicros, 320000);
    });

    test('returns null for malformed input without throwing', () {
      final dto = PerfSnapshotDto.tryFromJson({'bad': 'data'});
      expect(dto, isNull);
    });

    test('nullable percentile fields parse as null correctly', () {
      final json = {
        'traces': {
          'totalDropCount': 0,
          'keys': [
            {
              'name': 'op',
              'category': null,
              'count': 1,
              'meanMicros': 100,
              'maxMicros': 100,
              'totalMicros': 100,
              'p50': null,
              'p95': null,
              'p99': null,
              'avgInterCallIntervalMicros': null,
              'callsPerSecond': null,
              'errorCount': 0,
              'firstStartMicros': 0,
              'lastStartMicros': 0,
            },
          ],
        },
        'frames': {
          'frameCount': 0,
          'jankCount': 0,
          'buildP50': null,
          'buildP95': null,
          'buildP99': null,
          'rasterP50': null,
          'rasterP95': null,
          'rasterP99': null,
          'totalP50': null,
          'totalP95': null,
          'totalP99': null,
          'recentFrames': <Object?>[],
        },
        'stability': {
          'errorCount': 0,
          'stallCount': 0,
          'recentErrors': <Object?>[],
          'recentStalls': <Object?>[],
        },
      };
      final dto = PerfSnapshotDto.tryFromJson(json);
      expect(dto, isNotNull);
      final key = dto!.traces.keys.first;
      expect(key.p50, isNull);
      expect(key.callsPerSecond, isNull);
      expect(dto.frames.buildP50, isNull);
    });
  });

  // ── TraceKeyDto.isHot ─────────────────────────────────────────────────────────

  group('TraceKeyDto.isHot', () {
    test('isHot when callsPerSecond >= 5', () {
      final k = _traceKey(rate: 5.0);
      expect(k.isHot, isTrue);
    });

    test('not hot when low rate and loose interval', () {
      final k = _traceKey(rate: 1.0, interval: 500000);
      expect(k.isHot, isFalse);
    });

    test('isHot when count >= 20 and interval <= 200ms', () {
      final k = _traceKey(count: 20, interval: 150000);
      expect(k.isHot, isTrue);
    });

    test('not hot when count high but interval loose', () {
      final k = _traceKey(count: 20, interval: 300000);
      expect(k.isHot, isFalse);
    });
  });

  // ── TracesView ────────────────────────────────────────────────────────────────

  group('TracesView', () {
    testWidgets('not-available state shows PerfRadarNotDetectedView', (
      tester,
    ) async {
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.notAvailable,
      );
      await tester.pumpWidget(_wrap(TracesView(controller: ctrl)));
      await tester.pump();

      expect(
        find.text('PerfRadar not detected in the connected app'),
        findsOneWidget,
      );
      // Must not render any numeric table data.
      expect(find.text('count'), findsNothing);
    });

    testWidgets('loaded state renders trace rows', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          traces: _traces(
            keys: [
              _traceKey(name: 'db.query.rooms', category: 'db'),
              _traceKey(name: 'json.decode', category: 'json'),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(TracesView(controller: ctrl)));
      await tester.pump();

      expect(find.text('db.query.rooms'), findsOneWidget);
      expect(find.text('json.decode'), findsOneWidget);
    });

    testWidgets('search to empty shows empty state', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          traces: _traces(keys: [_traceKey(name: 'db.query')]),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(TracesView(controller: ctrl)));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'nomatch_xyz');
      await tester.pump();

      expect(find.textContaining("No results match"), findsOneWidget);
      expect(find.text('db.query'), findsNothing);
    });

    testWidgets('HOT tag appears for high-rate operation', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          traces: _traces(keys: [_traceKey(name: 'scroll.layout', rate: 10.0)]),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(TracesView(controller: ctrl)));
      await tester.pump();

      expect(find.text('HOT'), findsOneWidget);
    });

    testWidgets('non-hot operation has no HOT tag', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          traces: _traces(
            keys: [_traceKey(name: 'slow.op', count: 1, rate: 0.1)],
          ),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(TracesView(controller: ctrl)));
      await tester.pump();

      expect(find.text('HOT'), findsNothing);
    });

    testWidgets('null p50 renders as em dash', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          traces: _traces(keys: [_traceKey(name: 'op', p50: null)]),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(TracesView(controller: ctrl)));
      await tester.pump();

      // The "—" em-dash appears for null metrics (multiple nulls → multiple dashes).
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('no ExpansionTile in traces view', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(traces: _traces(keys: [_traceKey()])),
      );
      await tester.pumpWidget(_wrapDesktop(TracesView(controller: ctrl)));
      await tester.pump();

      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('hot filter shows only hot operations', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          traces: _traces(
            keys: [
              _traceKey(name: 'hot.op', rate: 10.0),
              _traceKey(name: 'cold.op', rate: 0.1, count: 1),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(TracesView(controller: ctrl)));
      await tester.pump();

      // Tap the "hot / dup" filter chip.
      await tester.tap(find.text('hot / dup'));
      await tester.pump();

      expect(find.text('hot.op'), findsOneWidget);
      expect(find.text('cold.op'), findsNothing);
    });

    testWidgets('errors filter shows only operations with errors', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          traces: _traces(
            keys: [
              _traceKey(name: 'err.op', errors: 3),
              _traceKey(name: 'ok.op', errors: 0),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(TracesView(controller: ctrl)));
      await tester.pump();

      await tester.tap(find.text('errors'));
      await tester.pump();

      expect(find.text('err.op'), findsOneWidget);
      expect(find.text('ok.op'), findsNothing);
    });
  });

  // ── FramesView ────────────────────────────────────────────────────────────────

  group('FramesView', () {
    testWidgets('not-available state shows PerfRadarNotDetectedView', (
      tester,
    ) async {
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.notAvailable,
      );
      await tester.pumpWidget(_wrap(FramesView(controller: ctrl)));
      await tester.pump();

      expect(
        find.text('PerfRadar not detected in the connected app'),
        findsOneWidget,
      );
    });

    testWidgets('loaded state renders jank stat tiles', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          frames: _frames(frameCount: 300, jankCount: 4),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(FramesView(controller: ctrl)));
      await tester.pump();

      expect(find.text('Total frames'), findsOneWidget);
      expect(find.text('Jank frames'), findsOneWidget);
      expect(find.text('Jank %'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('null percentiles render as em dash', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          frames: _frames(buildP50: null, buildP95: null, buildP99: null),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(FramesView(controller: ctrl)));
      await tester.pump();

      expect(find.text('—'), findsWidgets);
    });

    testWidgets('no ExpansionTile in frames view', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(),
      );
      await tester.pumpWidget(_wrapDesktop(FramesView(controller: ctrl)));
      await tester.pump();

      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('recent frames render in timeline', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          frames: _frames(
            recent: [
              const RecentFrameDto(
                totalMicros: 20000,
                buildMicros: 10000,
                rasterMicros: 10000,
              ),
              const RecentFrameDto(
                totalMicros: 8000,
                buildMicros: 4000,
                rasterMicros: 4000,
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(FramesView(controller: ctrl)));
      await tester.pump();

      expect(find.text('RECENT FRAMES'), findsOneWidget);
      expect(find.text('WORST FRAMES (TOP 5)'), findsOneWidget);
    });

    testWidgets('shows a reset-counters button in the toolbar', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(),
      );
      await tester.pumpWidget(_wrapDesktop(FramesView(controller: ctrl)));
      await tester.pump();

      expect(find.byIcon(Icons.restart_alt), findsOneWidget);
    });

    testWidgets('tapping reset invokes PerfDataController.resetFrames', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(),
      );
      await tester.pumpWidget(_wrapDesktop(FramesView(controller: ctrl)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.restart_alt));
      await tester.pump();

      expect(ctrl.resetFramesCallCount, equals(1));
    });
  });

  // ── ErrorsView ────────────────────────────────────────────────────────────────

  group('ErrorsView', () {
    testWidgets('not-available state shows PerfRadarNotDetectedView', (
      tester,
    ) async {
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.notAvailable,
      );
      await tester.pumpWidget(_wrap(ErrorsView(controller: ctrl)));
      await tester.pump();

      expect(
        find.text('PerfRadar not detected in the connected app'),
        findsOneWidget,
      );
    });

    testWidgets('empty errors shows "No errors recorded"', (tester) async {
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(stability: _stability()),
      );
      await tester.pumpWidget(_wrap(ErrorsView(controller: ctrl)));
      await tester.pump();

      expect(find.text('No errors recorded.'), findsOneWidget);
    });

    testWidgets('renders error message in table', (tester) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          stability: _stability(
            errors: 1,
            recentErrors: [
              const ErrorRecordDto(
                message: 'Connection refused',
                context: 'SocketException',
                clockMicros: 5000000,
                stackTraceString: '#0 main()',
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(ErrorsView(controller: ctrl)));
      await tester.pump();

      expect(find.text('Connection refused'), findsOneWidget);
      expect(find.text('SocketException'), findsOneWidget);
    });

    testWidgets('stack trace detail visible after tap (no ExpansionTile)', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          stability: _stability(
            errors: 1,
            recentErrors: [
              const ErrorRecordDto(
                message: 'Bad state',
                context: null,
                clockMicros: 1000000,
                stackTraceString: '#0 boom()\n#1 main()',
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(ErrorsView(controller: ctrl)));
      await tester.pump();

      // Stack trace must not be visible before tap.
      expect(find.text('#0 boom()\n#1 main()'), findsNothing);

      // Tap the row to expand the always-visible detail section.
      await tester.tap(find.text('Bad state'));
      await tester.pump();

      expect(find.text('#0 boom()\n#1 main()'), findsOneWidget);
      // No ExpansionTile anywhere in tree.
      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('no ExpansionTile in errors view', (tester) async {
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(stability: _stability()),
      );
      await tester.pumpWidget(_wrap(ErrorsView(controller: ctrl)));
      await tester.pump();

      expect(find.byType(ExpansionTile), findsNothing);
    });
  });

  // ── StallsView ────────────────────────────────────────────────────────────────

  group('StallsView', () {
    testWidgets('not-available state shows PerfRadarNotDetectedView', (
      tester,
    ) async {
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.notAvailable,
      );
      await tester.pumpWidget(_wrap(StallsView(controller: ctrl)));
      await tester.pump();

      expect(
        find.text('PerfRadar not detected in the connected app'),
        findsOneWidget,
      );
    });

    testWidgets('empty stalls shows "No stalls recorded"', (tester) async {
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(stability: _stability()),
      );
      await tester.pumpWidget(_wrap(StallsView(controller: ctrl)));
      await tester.pump();

      expect(find.text('No stalls recorded.'), findsOneWidget);
    });

    testWidgets('stall duration renders with colour grading info', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(
          stability: _stability(
            stalls: 2,
            recentStalls: [
              const StallRecordDto(
                durationMicros: 1200000,
                clockMicros: 5000000,
              ),
              const StallRecordDto(
                durationMicros: 650000,
                clockMicros: 6000000,
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrapDesktop(StallsView(controller: ctrl)));
      await tester.pump();

      // 1.20s and 650ms should both render.
      expect(find.text('1.20s'), findsOneWidget);
      expect(find.text('650ms'), findsOneWidget);
    });

    testWidgets('no ExpansionTile in stalls view', (tester) async {
      final ctrl = _FakePerfController(
        initialState: PerfLoadState.loaded,
        initialSnapshot: _snapshot(stability: _stability()),
      );
      await tester.pumpWidget(_wrap(StallsView(controller: ctrl)));
      await tester.pump();

      expect(find.byType(ExpansionTile), findsNothing);
    });
  });

  // ── PerfDataController state machine ──────────────────────────────────────────

  group('PerfDataController', () {
    test('starts in idle state', () {
      final ctrl = _FakePerfController();
      expect(ctrl.loadState, PerfLoadState.idle);
      expect(ctrl.snapshot, isNull);
    });

    test('injecting loaded state exposes snapshot', () {
      final ctrl = _FakePerfController();
      final snap = _snapshot();
      ctrl.inject(state: PerfLoadState.loaded, snapshot: snap);
      expect(ctrl.loadState, PerfLoadState.loaded);
      expect(ctrl.snapshot, same(snap));
    });

    test('injecting notAvailable has null snapshot', () {
      final ctrl = _FakePerfController();
      ctrl.inject(state: PerfLoadState.notAvailable);
      expect(ctrl.loadState, PerfLoadState.notAvailable);
      expect(ctrl.snapshot, isNull);
    });

    test('injecting error state exposes message', () {
      final ctrl = _FakePerfController();
      ctrl.inject(state: PerfLoadState.error, errorMessage: 'timeout');
      expect(ctrl.loadState, PerfLoadState.error);
      expect(ctrl.errorMessage, 'timeout');
    });

    test('real controller with fake extension transitions to loaded', () async {
      final snap = _snapshot(
        traces: _traces(keys: [_traceKey(name: 'net.fetch')]),
      );
      // The injected callExtension returns the raw snapshot map directly —
      // the controller passes it to PerfSnapshotDto.tryFromJson as-is.
      final ctrl = PerfDataController(
        callExtension: (_) async => _encodeSnapshot(snap),
      );
      await ctrl.refresh();
      // The controller should decode and expose the snapshot.
      expect(ctrl.loadState, PerfLoadState.loaded);
      expect(ctrl.snapshot, isNotNull);
      expect(ctrl.snapshot!.traces.keys.first.name, 'net.fetch');
    });

    test('real controller handles ExtensionNotAvailableException', () async {
      final ctrl = PerfDataController(
        callExtension: (_) async =>
            throw const ExtensionNotAvailableException(),
      );
      await ctrl.refresh();
      expect(ctrl.loadState, PerfLoadState.notAvailable);
      expect(ctrl.snapshot, isNull);
    });

    test('real controller handles generic error', () async {
      final ctrl = PerfDataController(
        callExtension: (_) async => throw Exception('boom'),
      );
      await ctrl.refresh();
      expect(ctrl.loadState, PerfLoadState.error);
      expect(ctrl.errorMessage, isNotNull);
    });

    // ── resetFrames ──────────────────────────────────────────────────────

    test(
      'resetFrames calls ext.perf_radar.resetFrames then refreshes',
      () async {
        final calledMethods = <String>[];
        final snap = _snapshot(frames: _frames(frameCount: 0, jankCount: 0));
        final ctrl = PerfDataController(
          callExtension: (method) async {
            calledMethods.add(method);
            if (method == 'ext.perf_radar.resetFrames') return {'reset': true};
            return _encodeSnapshot(snap);
          },
        );

        await ctrl.resetFrames();

        expect(
          calledMethods,
          equals(['ext.perf_radar.resetFrames', 'ext.perf_radar.snapshot']),
        );
        expect(ctrl.loadState, PerfLoadState.loaded);
        expect(ctrl.snapshot!.frames.frameCount, equals(0));
      },
    );

    test('resetFrames does not throw and leaves state untouched when '
        'extension is unavailable', () async {
      final ctrl = PerfDataController(
        callExtension: (_) async =>
            throw const ExtensionNotAvailableException(),
      );

      await ctrl.resetFrames();

      expect(ctrl.loadState, PerfLoadState.idle);
      expect(ctrl.snapshot, isNull);
    });

    test('resetFrames does not throw on a generic connection error', () async {
      final ctrl = PerfDataController(
        callExtension: (_) async => throw Exception('disconnected'),
      );

      await ctrl.resetFrames();

      expect(ctrl.loadState, PerfLoadState.idle);
    });
  });
}

// ── Encode helper: mirrors what the VM extension returns ──────────────────────

/// Encodes [dto] into the JSON map shape returned by the VM service extension.
Map<String, Object?> _encodeSnapshot(PerfSnapshotDto dto) {
  final traces = dto.traces;
  final frames = dto.frames;
  final stab = dto.stability;
  return {
    'traces': {
      'totalDropCount': traces.totalDropCount,
      'keys': [
        for (final k in traces.keys)
          {
            'name': k.name,
            'category': k.category,
            'count': k.count,
            'meanMicros': k.meanMicros,
            'maxMicros': k.maxMicros,
            'totalMicros': k.totalMicros,
            'p50': k.p50,
            'p95': k.p95,
            'p99': k.p99,
            'avgInterCallIntervalMicros': k.avgInterCallIntervalMicros,
            'callsPerSecond': k.callsPerSecond,
            'errorCount': k.errorCount,
            'firstStartMicros': k.firstStartMicros,
            'lastStartMicros': k.lastStartMicros,
          },
      ],
    },
    'frames': {
      'frameCount': frames.frameCount,
      'jankCount': frames.jankCount,
      'buildP50': frames.buildP50,
      'buildP95': frames.buildP95,
      'buildP99': frames.buildP99,
      'rasterP50': frames.rasterP50,
      'rasterP95': frames.rasterP95,
      'rasterP99': frames.rasterP99,
      'totalP50': frames.totalP50,
      'totalP95': frames.totalP95,
      'totalP99': frames.totalP99,
      'recentFrames': [
        for (final f in frames.recentFrames)
          {
            'totalMicros': f.totalMicros,
            'buildMicros': f.buildMicros,
            'rasterMicros': f.rasterMicros,
          },
      ],
    },
    'stability': {
      'errorCount': stab.errorCount,
      'stallCount': stab.stallCount,
      'recentErrors': [
        for (final e in stab.recentErrors)
          {
            'message': e.message,
            'context': e.context,
            'clockMicros': e.clockMicros,
            'stackTraceString': e.stackTraceString,
          },
      ],
      'recentStalls': [
        for (final s in stab.recentStalls)
          {'durationMicros': s.durationMicros, 'clockMicros': s.clockMicros},
      ],
    },
  };
}
