import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_capture_screen.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';

/// No file-pick platform-channel calls are driven by these tests (matching
/// `dumps_screen.dart`'s untested `_browse` pattern) — this fake is never
/// actually invoked.
class _FakeImporter implements NativeTraceImporter {
  @override
  Future<NativeHeapProfile> importTrace(
    String path, {
    required String label,
  }) async => throw UnimplementedError('not needed by these tests');

  @override
  Future<SymbolStore> importSymbolStore(String path) async =>
      throw UnimplementedError('not needed by these tests');

  @override
  Future<FfiAllocationLog> importFfiLog(String path) async =>
      throw UnimplementedError('not needed by these tests');
}

Future<void> _pump(WidgetTester tester) {
  final controller = NativeProfilingController(_FakeImporter());
  return tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: AndroidCaptureScreen(controller: controller)),
    ),
  );
}

/// The [FilledButton] labeled [label]. `FilledButton.icon` returns the
/// private subtype `_FilledButtonWithIcon`, which `find.byType` (an exact
/// runtimeType match) never finds — `bySubtype` matches it correctly.
Finder _buttonLabeled(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<FilledButton>(),
);

void main() {
  testWidgets('renders the three enabled import actions', (tester) async {
    await _pump(tester);

    for (final label in [
      'Import Perfetto trace',
      'Attach symbol store',
      'Import ffi log',
    ]) {
      final button = tester.widget<FilledButton>(_buttonLabeled(label));
      expect(button.onPressed, isNotNull, reason: '$label should be enabled');
    }
  });

  testWidgets('renders the disabled Run device capture action', (tester) async {
    await _pump(tester);

    final button = tester.widget<FilledButton>(
      _buttonLabeled('Run device capture'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('Phase 4'), findsOneWidget);
  });

  testWidgets('states the prerequisites plainly', (tester) async {
    await _pump(tester);

    expect(find.textContaining('Android only'), findsOneWidget);
    expect(find.textContaining('iOS not supported'), findsOneWidget);
    expect(
      find.textContaining('profile the profile/release build'),
      findsOneWidget,
    );
    expect(find.textContaining('RADAR_TP_BIN'), findsOneWidget);
  });
}
