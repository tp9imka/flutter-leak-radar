import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_detail_screen.dart';
import 'package:radar_desktop/src/screens/android_native_module_row.dart';
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

  testWidgets(
    'tapping a callsite\'s › chevron pushes the detail screen for it',
    (tester) async {
      final controller = await _readyController(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: radarDarkTheme(),
          home: Scaffold(body: AndroidNativeScreen(controller: controller)),
        ),
      );

      await tester.tap(find.byType(RadarExpandableRow).first);
      await tester.pumpAndSettle();

      // `RadarExpandableRow`'s own chevron also renders `Icons.chevron_right`
      // as a plain (non-button) icon, so disambiguate via the callsite row's
      // `IconButton` rather than the icon itself.
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.byType(AndroidDetailScreen), findsOneWidget);
      // The pushed screen is for the tapped callsite's attributed module:
      // once in its header, once more as the dimmed module label beside
      // the stack's `libapp.so` frame (the other frame is `libc.so`).
      expect(find.text('libapp.so'), findsNWidgets(2));
    },
  );

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

  testWidgets('tapping the allocs header re-sorts rows by alloc count', (
    tester,
  ) async {
    // "aaa.so" has more still-live bytes but fewer allocs than "bbb.so", so
    // the default (still-live desc) and allocs-sorted orders differ.
    final profile = NativeHeapProfile(
      capturedAt: DateTime(2026, 1, 1),
      label: 'snapshot',
      meta: const NativeProfileMeta(),
      callsites: [
        NativeCallsite(
          frames: const [
            NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
            NativeFrame(
              function: '0x1000',
              module: '/data/app/~~abc==/com.example.app-1/base.apk!aaa.so',
              buildId: 'BUILD_AAA',
            ),
          ],
          allocBytes: 2000,
          allocCount: 4,
          freeBytes: 0,
          freeCount: 0,
        ),
        NativeCallsite(
          frames: const [
            NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
            NativeFrame(
              function: '0x2000',
              module: '/data/app/~~abc==/com.example.app-1/base.apk!bbb.so',
              buildId: 'BUILD_BBB',
            ),
          ],
          allocBytes: 500,
          allocCount: 50,
          freeBytes: 0,
          freeCount: 0,
        ),
      ],
    );

    final controller = NativeProfilingController(
      _FakeImporter({'snapshot': profile}),
    );
    await controller.importTrace('snapshot.pftrace', label: 'snapshot');

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidNativeScreen(controller: controller)),
      ),
    );

    List<String> moduleOrder() => tester
        .widgetList<AndroidNativeModuleRow>(find.byType(AndroidNativeModuleRow))
        .map((row) => row.summary.module)
        .toList();

    expect(moduleOrder(), ['aaa.so', 'bbb.so']);

    await tester.tap(find.text('allocs'));
    await tester.pumpAndSettle();

    expect(moduleOrder(), ['bbb.so', 'aaa.so']);
  });

  testWidgets('a shrinking module renders a negative accent-colored delta', (
    tester,
  ) async {
    final before = NativeHeapProfile(
      capturedAt: DateTime(2026, 1, 1),
      label: 'before',
      meta: const NativeProfileMeta(),
      callsites: [
        NativeCallsite(
          frames: const [
            NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
            NativeFrame(
              function: '0xfeedface',
              module:
                  '/data/app/~~abc==/com.example.app-1/base.apk!'
                  'libshrink.so',
              buildId: 'BUILD_SHRINK',
            ),
          ],
          allocBytes: 1000,
          allocCount: 10,
          freeBytes: 200,
          freeCount: 2,
        ),
      ],
    );
    final after = NativeHeapProfile(
      capturedAt: DateTime(2026, 1, 2),
      label: 'after',
      meta: const NativeProfileMeta(),
      callsites: [
        NativeCallsite(
          frames: const [
            NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
            NativeFrame(
              function: '0xfeedface',
              module:
                  '/data/app/~~abc==/com.example.app-1/base.apk!'
                  'libshrink.so',
              buildId: 'BUILD_SHRINK',
            ),
          ],
          allocBytes: 1000,
          allocCount: 10,
          freeBytes: 700,
          freeCount: 7,
        ),
      ],
    );

    final controller = NativeProfilingController(
      _FakeImporter({'before': before, 'after': after}),
    );
    await controller.importTrace('before.pftrace', label: 'before');
    await controller.importTrace('after.pftrace', label: 'after');

    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(body: AndroidNativeScreen(controller: controller)),
      ),
    );

    // Shrunk from 800 B still-live to 300 B still-live: delta of -500 B,
    // rendered in the "shrank" (accent) color rather than "grew" (critical).
    expect(find.textContaining('-500 B'), findsOneWidget);
    final deltaText = tester.widget<Text>(find.textContaining('-500 B'));
    expect(deltaText.style?.color, RadarColors.accent);
  });
}
