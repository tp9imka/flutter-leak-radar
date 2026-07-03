import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_detail_screen.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';

/// A callsite whose attributed (top, allocator-skipped) frame is symbolized
/// but whose deeper frame is a raw, unsymbolized address — exercises the
/// per-frame module-only tag without the whole callsite counting as
/// unsymbolized (so the add-symbols banner must stay hidden).
NativeCallsite _mixedFidelityCallsite() => NativeCallsite(
  frames: const [
    NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
    NativeFrame(
      function: 'flutter::Foo::bar',
      module: '/data/app/~~abc==/com.example.app-1/base.apk!libapp.so',
      buildId: 'BUILD_APP',
    ),
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
);

/// A callsite whose LEAF frame is a symbolized allocator entry point
/// (`malloc`) but whose attributed (allocator-skipped) caller frame is a raw,
/// unsymbolized address. Regression coverage for a bug where gating the
/// add-symbols banner on "does any frame have a resolved name" let the
/// always-named allocator leaf hide the banner even though the real caller
/// was never resolved — allocator leaves are named by heapprofd itself, with
/// no symbol store involved.
NativeCallsite _unsymbolizedCallerBehindSymbolizedAllocatorCallsite() =>
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0x3000',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libapp.so',
          buildId: 'BUILD_APP',
        ),
      ],
      allocBytes: 400,
      allocCount: 4,
      freeBytes: 0,
      freeCount: 0,
    );

/// A callsite with no resolved function names anywhere in its stack — every
/// frame is a raw `0x…` address, so the add-symbols banner must show.
NativeCallsite _fullyUnsymbolizedCallsite() => NativeCallsite(
  frames: const [
    NativeFrame(
      function: '0x1000',
      module: '/data/app/~~abc==/com.example.app-1/base.apk!libapp.so',
      buildId: 'BUILD_APP',
    ),
    NativeFrame(
      function: '0x2000',
      module: '/data/app/~~abc==/com.example.app-1/base.apk!libapp.so',
      buildId: 'BUILD_APP',
    ),
  ],
  allocBytes: 500,
  allocCount: 5,
  freeBytes: 0,
  freeCount: 0,
);

/// Only the trace-import path is exercised by these tests.
class _FakeImporter implements NativeTraceImporter {
  _FakeImporter(this._profile);

  final NativeHeapProfile _profile;

  @override
  Future<NativeHeapProfile> importTrace(
    String path, {
    required String label,
  }) async => _profile;

  @override
  Future<SymbolStore> importSymbolStore(String path) async =>
      throw UnimplementedError('not needed by these tests');

  @override
  Future<FfiAllocationLog> importFfiLog(String path) async =>
      throw UnimplementedError('not needed by these tests');
}

/// A controller with a single imported checkpoint holding only [callsite],
/// and no symbol store — [NativeProfilingController.isSymbolized] is false.
Future<NativeProfilingController> _controllerWith(
  NativeCallsite callsite,
) async {
  final profile = NativeHeapProfile(
    capturedAt: DateTime(2026, 1, 1),
    label: 'snapshot',
    meta: const NativeProfileMeta(),
    callsites: [callsite],
  );
  final controller = NativeProfilingController(_FakeImporter(profile));
  await controller.importTrace('snapshot.pftrace', label: 'snapshot');
  return controller;
}

Future<void> _pump(WidgetTester tester, AndroidDetailScreen screen) {
  return tester.pumpWidget(MaterialApp(theme: radarDarkTheme(), home: screen));
}

void main() {
  testWidgets('renders the module header, still-live tiles, and call stack', (
    tester,
  ) async {
    final controller = await _controllerWith(_mixedFidelityCallsite());
    final callsite = controller.selectedSymbolized!.callsites.single;

    await _pump(
      tester,
      AndroidDetailScreen(controller: controller, callsite: callsite),
    );

    // Header: attributed module + its kind label. "libapp.so" also renders
    // as the dimmed module label beside each of the two stack frames that
    // share it, hence 3 (1 header + 2 stack rows) rather than 1.
    expect(find.text('libapp.so'), findsNWidgets(3));
    expect(find.text('App'), findsOneWidget);

    // Still-live (800 B) and live-allocation (8) tiles, both measured.
    expect(find.text('800 B'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);

    // The full stack renders, including the symbolized attributed frame.
    expect(find.byType(RadarStackList), findsOneWidget);
    expect(find.text('flutter::Foo::bar'), findsOneWidget);
    expect(find.text('0xdeadbeef'), findsOneWidget);
  });

  testWidgets(
    'a mixed-fidelity stack tags only its unsymbolized frame, and hides '
    'the add-symbols banner',
    (tester) async {
      final controller = await _controllerWith(_mixedFidelityCallsite());
      final callsite = controller.selectedSymbolized!.callsites.single;

      await _pump(
        tester,
        AndroidDetailScreen(controller: controller, callsite: callsite),
      );

      // Only the raw `0xdeadbeef` frame is module-only; the symbolized
      // caller frame carries no tag.
      expect(find.text('MODULE-ONLY'), findsOneWidget);
      expect(find.byType(RadarBanner), findsNothing);
    },
  );

  testWidgets(
    'a symbolized allocator leaf does not hide the add-symbols banner when '
    'the attributed caller frame is unsymbolized',
    (tester) async {
      final controller = await _controllerWith(
        _unsymbolizedCallerBehindSymbolizedAllocatorCallsite(),
      );
      final callsite = controller.selectedSymbolized!.callsites.single;

      await _pump(
        tester,
        AndroidDetailScreen(controller: controller, callsite: callsite),
      );

      // An allocator-blind `any(isFrameSymbolized)` check would see `malloc`
      // and hide the banner; the fix gates on the attributed (allocator-
      // skipped) frame instead, which here is the unresolved `0x3000`.
      expect(find.byType(RadarBanner), findsOneWidget);
      expect(find.textContaining('Add symbols'), findsOneWidget);
    },
  );

  testWidgets('a fully unsymbolized callsite shows the add-symbols banner', (
    tester,
  ) async {
    final controller = await _controllerWith(_fullyUnsymbolizedCallsite());
    final callsite = controller.selectedSymbolized!.callsites.single;

    await _pump(
      tester,
      AndroidDetailScreen(controller: controller, callsite: callsite),
    );

    expect(find.text('MODULE-ONLY'), findsNWidgets(2));
    expect(find.byType(RadarBanner), findsOneWidget);
    expect(find.textContaining('Add symbols'), findsOneWidget);
  });
}
