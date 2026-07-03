import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_session_screen.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';

/// Canned "before" checkpoint: one app callsite, matching the shape used by
/// `android_native_screen_test.dart`'s fixtures.
NativeHeapProfile _beforeProfile() => NativeHeapProfile(
  capturedAt: DateTime(2026, 1, 1),
  label: 'before',
  meta: const NativeProfileMeta(),
  callsites: [
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0xdeadbeef',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libapp.so',
          buildId: 'BUILD_APP',
        ),
      ],
      allocBytes: 1000,
      allocCount: 10,
      freeBytes: 200,
      freeCount: 2,
    ),
  ],
);

/// Canned "after" checkpoint: the same app callsite grew, giving the growth
/// tile a non-'—' value to assert against.
NativeHeapProfile _afterProfile() => NativeHeapProfile(
  capturedAt: DateTime(2026, 1, 2),
  label: 'after',
  meta: const NativeProfileMeta(),
  callsites: [
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0xdeadbeef',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libapp.so',
          buildId: 'BUILD_APP',
        ),
      ],
      allocBytes: 1500,
      allocCount: 15,
      freeBytes: 200,
      freeCount: 2,
    ),
  ],
);

/// Mirrors the more flexible `_FakeImporter` used in
/// `test/android/native_profiling_controller_test.dart`: canned profiles by
/// label, plus an optional [traceError] to exercise the error state.
class _FakeImporter implements NativeTraceImporter {
  _FakeImporter({
    Map<String, NativeHeapProfile> profilesByLabel = const {},
    this.symbolStore,
    this.traceError,
    this.pending,
  }) : _profilesByLabel = profilesByLabel;

  final Map<String, NativeHeapProfile> _profilesByLabel;
  final SymbolStore? symbolStore;
  final Object? traceError;

  /// When set, [importTrace] never resolves on its own — the caller
  /// completes it manually. Used to hold the controller in `loading` for as
  /// long as a test needs, rather than racing a same-microtask resolution.
  final Completer<NativeHeapProfile>? pending;

  @override
  Future<NativeHeapProfile> importTrace(String path, {required String label}) {
    final wait = pending;
    if (wait != null) return wait.future;
    if (traceError != null) throw traceError!;
    final profile = _profilesByLabel[label];
    if (profile == null) {
      throw StateError('_FakeImporter has no canned profile for "$label"');
    }
    return Future.value(profile);
  }

  @override
  Future<SymbolStore> importSymbolStore(String path) async {
    final store = symbolStore;
    if (store == null) throw StateError('_FakeImporter has no symbol store');
    return store;
  }

  @override
  Future<FfiAllocationLog> importFfiLog(String path) async =>
      throw UnimplementedError('not needed by these tests');
}

Future<void> _pump(WidgetTester tester, NativeProfilingController controller) {
  return tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: AndroidSessionScreen(controller: controller)),
    ),
  );
}

void main() {
  testWidgets('empty controller shows a CTA pointing at Capture/import', (
    tester,
  ) async {
    final controller = NativeProfilingController(_FakeImporter());

    await _pump(tester, controller);

    expect(find.textContaining('Capture'), findsWidgets);
  });

  testWidgets('ready with one checkpoint and no symbol store renders the amber '
      'fidelity banner and the honest GPU n/a tile', (tester) async {
    final controller = NativeProfilingController(
      _FakeImporter(profilesByLabel: {'before': _beforeProfile()}),
    );
    await controller.importTrace('before.pftrace', label: 'before');

    await _pump(tester, controller);

    final banner = tester.widget<RadarBanner>(find.byType(RadarBanner));
    expect(banner.severity, RadarSeverity.warning);
    expect(banner.message, contains('Module-only'));

    // The load-bearing honesty rule: GPU total is never a silent 0.
    const gpuText = 'not reported · n/a on this device';
    expect(find.text(gpuText), findsOneWidget);
    final gpuTile = tester.widget<RadarMetricTile>(
      find.widgetWithText(RadarMetricTile, gpuText),
    );
    expect(gpuTile.color, RadarColors.text25);
  });

  testWidgets('loading state shows the indeterminate bar and a caption', (
    tester,
  ) async {
    // A never-resolving-until-told importer holds the controller in
    // `loading` deliberately, rather than racing a same-microtask
    // resolution against `pumpWidget`.
    final pending = Completer<NativeHeapProfile>();
    final controller = NativeProfilingController(
      _FakeImporter(pending: pending),
    );
    final future = controller.importTrace('slow.pftrace', label: 'before');

    await _pump(tester, controller);

    expect(find.byType(RadarLinearProgress), findsOneWidget);
    expect(find.textContaining('Analyzing'), findsOneWidget);

    // Settle the pending import so the test doesn't leak a dangling future.
    pending.complete(_beforeProfile());
    await future;
  });

  testWidgets('error state surfaces the specific errorMessage', (tester) async {
    final controller = NativeProfilingController(
      _FakeImporter(traceError: Exception('no heapprofd stream')),
    );
    await controller.importTrace('cpu_only.pftrace', label: 'before');

    await _pump(tester, controller);

    expect(find.textContaining('no heapprofd stream'), findsOneWidget);
  });

  testWidgets('ready with a single checkpoint shows "—" for growth', (
    tester,
  ) async {
    final controller = NativeProfilingController(
      _FakeImporter(profilesByLabel: {'before': _beforeProfile()}),
    );
    await controller.importTrace('before.pftrace', label: 'before');

    await _pump(tester, controller);

    expect(find.text('—'), findsOneWidget);
  });

  testWidgets(
    'ready with two checkpoints computes growth first-to-latest and lists '
    'both imported artifacts',
    (tester) async {
      final controller = NativeProfilingController(
        _FakeImporter(
          profilesByLabel: {
            'before': _beforeProfile(),
            'after': _afterProfile(),
          },
        ),
      );
      await controller.importTrace('before.pftrace', label: 'before');
      await controller.importTrace('after.pftrace', label: 'after');

      await _pump(tester, controller);

      // Grew from 800 B to 1300 B still-live: +500 B.
      expect(find.textContaining('+500 B'), findsOneWidget);
      expect(find.text('before'), findsOneWidget);
      expect(find.text('after'), findsOneWidget);
    },
  );

  testWidgets('a fully symbolized session shows the healthy banner', (
    tester,
  ) async {
    final store = SymbolStore({
      'BUILD_APP': {'0xdeadbeef': 'MyApp::allocateBuffer'},
    });
    final controller = NativeProfilingController(
      _FakeImporter(
        profilesByLabel: {'before': _beforeProfile()},
        symbolStore: store,
      ),
    );
    await controller.importTrace('before.pftrace', label: 'before');
    await controller.importSymbolStore('symbols.json');

    await _pump(tester, controller);

    final banner = tester.widget<RadarBanner>(find.byType(RadarBanner));
    expect(banner.severity, RadarSeverity.healthy);
    expect(banner.message, contains('Fully symbolized'));
  });
}
