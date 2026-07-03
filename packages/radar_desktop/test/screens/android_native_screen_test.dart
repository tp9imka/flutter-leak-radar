import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_native_screen.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';

/// Canned "before" checkpoint: one app callsite (unsymbolized leaf address)
/// behind an allocator frame that attribution should skip.
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

/// Canned "after" checkpoint: the same app callsite grew, enough signal to
/// exercise the Δ-vs-previous column.
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

/// Mirrors the `_FakeImporter` used in
/// `test/android/native_profiling_controller_test.dart` — only the trace
/// import path is exercised here.
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
  testWidgets('empty controller shows a CTA pointing at Capture/import', (
    tester,
  ) async {
    final controller = NativeProfilingController(_FakeImporter(const {}));

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidNativeScreen(controller: controller)),
      ),
    );

    expect(find.textContaining('Capture'), findsWidgets);
  });

  testWidgets('ready state renders ranked module rows with dots and bytes', (
    tester,
  ) async {
    final controller = await _readyController(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidNativeScreen(controller: controller)),
      ),
    );

    expect(find.byType(RadarModuleDot), findsWidgets);
    expect(find.textContaining('libapp.so'), findsOneWidget);
    // Δ vs the previous checkpoint (grew: +500 B) is shown once selected on
    // the newest ("after") checkpoint, which importTrace selects by default.
    expect(find.textContaining('+500 B'), findsOneWidget);
  });

  testWidgets('tapping a module row expands to show its callsites', (
    tester,
  ) async {
    final controller = await _readyController(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidNativeScreen(controller: controller)),
      ),
    );

    expect(find.text('MODULE-ONLY'), findsNothing);

    await tester.tap(find.byType(RadarExpandableRow).first);
    await tester.pumpAndSettle();

    // Unsymbolized leaf ('0xdeadbeef') falls back to module-only fidelity.
    expect(find.text('MODULE-ONLY'), findsOneWidget);
  });

  testWidgets('selecting an earlier checkpoint hides the Δ column value', (
    tester,
  ) async {
    final controller = await _readyController(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidNativeScreen(controller: controller)),
      ),
    );

    // Switch the checkpoint picker to the first ("before") checkpoint.
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('before').last);
    await tester.pumpAndSettle();

    expect(controller.selectedIndex, 0);
    expect(find.textContaining('+500 B'), findsNothing);
  });
}
