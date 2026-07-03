import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_ffi_screen.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';

/// Two still-live ffi allocation sites, each with a short Dart stack.
FfiAllocationLog _twoSiteLog() => FfiAllocationLog(
  capturedAt: DateTime(2026, 1, 1),
  sites: const [
    FfiAllocationSite(
      site: 'ImageCodec.decode',
      file: 'image_codec.dart:88',
      stillLiveBytes: 4096,
      stillLiveBlocks: 4,
      dartStack: [
        'ImageCodec.decode  image_codec.dart:88',
        'ImageCache.load  image_cache.dart:40',
      ],
    ),
    FfiAllocationSite(
      site: 'AudioBuffer.alloc',
      file: 'audio_buffer.dart:12',
      stillLiveBytes: 2048,
      stillLiveBlocks: 2,
      dartStack: [
        'AudioBuffer.alloc  audio_buffer.dart:12',
        'AudioPlayer.play  audio_player.dart:55',
      ],
    ),
  ],
);

/// Only the ffi-log import path is exercised by these tests.
class _FakeImporter implements NativeTraceImporter {
  _FakeImporter(this._log);

  final FfiAllocationLog _log;

  @override
  Future<NativeHeapProfile> importTrace(
    String path, {
    required String label,
  }) async => throw UnimplementedError('not needed by these tests');

  @override
  Future<SymbolStore> importSymbolStore(String path) async =>
      throw UnimplementedError('not needed by these tests');

  @override
  Future<FfiAllocationLog> importFfiLog(String path) async => _log;
}

Future<void> _pump(WidgetTester tester, NativeProfilingController controller) {
  return tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: AndroidFfiScreen(controller: controller)),
    ),
  );
}

void main() {
  testWidgets('no ffi log shows the import-to-unlock note', (tester) async {
    final controller = NativeProfilingController(_FakeImporter(_twoSiteLog()));

    await _pump(tester, controller);

    expect(find.textContaining('Capture / import'), findsOneWidget);
    expect(find.byType(RadarStackList), findsNothing);
  });

  testWidgets('an imported ffi log lists every site', (tester) async {
    final controller = NativeProfilingController(_FakeImporter(_twoSiteLog()));
    await controller.importFfiLog('ffi.json');

    await _pump(tester, controller);

    expect(find.text('ImageCodec.decode'), findsOneWidget);
    expect(find.text('image_codec.dart:88'), findsOneWidget);
    expect(find.text('4.0 KB'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    expect(find.text('AudioBuffer.alloc'), findsOneWidget);
    expect(find.text('audio_buffer.dart:12'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping a site expands its Dart stack', (tester) async {
    final controller = NativeProfilingController(_FakeImporter(_twoSiteLog()));
    await controller.importFfiLog('ffi.json');

    await _pump(tester, controller);

    expect(find.byType(RadarStackList), findsNothing);

    await tester.tap(find.text('ImageCodec.decode'));
    await tester.pump();

    expect(find.byType(RadarStackList), findsOneWidget);
    expect(find.text('ImageCodec.decode  image_codec.dart:88'), findsOneWidget);
    expect(find.text('ImageCache.load  image_cache.dart:40'), findsOneWidget);

    // The second site stays collapsed.
    expect(find.text('AudioBuffer.alloc  audio_buffer.dart:12'), findsNothing);
  });
}
