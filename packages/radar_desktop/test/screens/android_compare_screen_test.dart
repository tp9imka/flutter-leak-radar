import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_compare_screen.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';

/// Canned "before" checkpoint: a module that will grow, one that will be
/// removed by "after", and one that stays flat (must be suppressed).
NativeHeapProfile _beforeProfile() => NativeHeapProfile(
  capturedAt: DateTime(2026, 1, 1),
  label: 'before',
  meta: const NativeProfileMeta(),
  callsites: [
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0x1000',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libgrow.so',
          buildId: 'BUILD_GROW',
        ),
      ],
      allocBytes: 1000,
      allocCount: 10,
      freeBytes: 0,
      freeCount: 0,
    ),
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0x2000',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libgone.so',
          buildId: 'BUILD_GONE',
        ),
      ],
      allocBytes: 500,
      allocCount: 5,
      freeBytes: 0,
      freeCount: 0,
    ),
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0x3000',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libflat.so',
          buildId: 'BUILD_FLAT',
        ),
      ],
      allocBytes: 300,
      allocCount: 3,
      freeBytes: 0,
      freeCount: 0,
    ),
  ],
);

/// Canned "after" checkpoint: `libgrow.so` grew, `libgone.so` was freed
/// entirely, `libflat.so` is unchanged.
NativeHeapProfile _afterProfile() => NativeHeapProfile(
  capturedAt: DateTime(2026, 1, 2),
  label: 'after',
  meta: const NativeProfileMeta(),
  callsites: [
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0x1000',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libgrow.so',
          buildId: 'BUILD_GROW',
        ),
      ],
      allocBytes: 1800,
      allocCount: 18,
      freeBytes: 0,
      freeCount: 0,
    ),
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0x2000',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libgone.so',
          buildId: 'BUILD_GONE',
        ),
      ],
      allocBytes: 500,
      allocCount: 5,
      freeBytes: 500,
      freeCount: 5,
    ),
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0x3000',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libflat.so',
          buildId: 'BUILD_FLAT',
        ),
      ],
      allocBytes: 300,
      allocCount: 3,
      freeBytes: 0,
      freeCount: 0,
    ),
  ],
);

/// Mirrors the `_FakeImporter` used in
/// `test/screens/android_native_screen_test.dart` — only the trace import
/// path is exercised here.
class _FakeImporter implements NativeTraceImporter {
  _FakeImporter(this._profilesByLabel);

  final Map<String, NativeHeapProfile> _profilesByLabel;

  @override
  Future<NativeHeapProfile> importTrace(
    String path, {
    required String label,
  }) async {
    final profile = _profilesByLabel[label];
    if (profile == null) {
      throw StateError('_FakeImporter has no canned profile for "$label"');
    }
    return profile;
  }

  @override
  Future<SymbolStore> importSymbolStore(String path) async =>
      throw UnimplementedError('not needed by these tests');

  @override
  Future<FfiAllocationLog> importFfiLog(String path) async =>
      throw UnimplementedError('not needed by these tests');
}

Future<NativeProfilingController> _readyController(WidgetTester tester) async {
  final controller = NativeProfilingController(
    _FakeImporter({'before': _beforeProfile(), 'after': _afterProfile()}),
  );
  await controller.importTrace('before.pftrace', label: 'before');
  await controller.importTrace('after.pftrace', label: 'after');
  return controller;
}

void main() {
  testWidgets('fewer than two checkpoints shows an import-a-second note', (
    tester,
  ) async {
    final controller = NativeProfilingController(_FakeImporter(const {}));

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidCompareScreen(controller: controller)),
      ),
    );

    expect(find.textContaining('second checkpoint'), findsOneWidget);
  });

  testWidgets('renders GREW and GONE badges and suppresses the flat module', (
    tester,
  ) async {
    final controller = await _readyController(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidCompareScreen(controller: controller)),
      ),
    );

    expect(find.textContaining('libgrow.so'), findsOneWidget);
    expect(find.textContaining('libgone.so'), findsOneWidget);
    expect(find.textContaining('libflat.so'), findsNothing);

    expect(find.text('GREW'), findsOneWidget);
    final grewTag = tester.widget<RadarTag>(
      find.ancestor(of: find.text('GREW'), matching: find.byType(RadarTag)),
    );
    expect(grewTag.severity, RadarSeverity.critical);

    expect(find.text('GONE'), findsOneWidget);
    final goneTag = tester.widget<RadarTag>(
      find.ancestor(of: find.text('GONE'), matching: find.byType(RadarTag)),
    );
    expect(goneTag.severity, RadarSeverity.healthy);

    // libgrow.so: 1000 B -> 1800 B (+800 B); libgone.so: 500 B -> 0 B
    // (-500 B); libflat.so contributes 0. Total native delta: +300 B.
    expect(find.textContaining('+800 B'), findsOneWidget);
    expect(find.textContaining('-500 B'), findsOneWidget);
    expect(find.textContaining('+300 B'), findsOneWidget);
  });

  testWidgets('the A picker defaults to the first checkpoint', (tester) async {
    final controller = await _readyController(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidCompareScreen(controller: controller)),
      ),
    );

    final dropdowns = tester.widgetList<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    expect(dropdowns.elementAt(0).value, 0);
    expect(dropdowns.elementAt(1).value, 1);
  });
}
