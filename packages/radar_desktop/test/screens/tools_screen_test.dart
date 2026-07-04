import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/screens/tools_screen.dart';
import 'package:radar_desktop/src/tools/tools_controller.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';

/// In-memory [ToolConfigStore] fake — no real fs/path_provider.
class _FakeToolConfigStore implements ToolConfigStore {
  @override
  Future<ToolConfig> read() async => const ToolConfig({});

  @override
  Future<void> write(ToolConfig config) async {}
}

/// Builds a [ToolProbe] whose bare-name (PATH-tier) candidate verifies
/// only when the candidate id is a member of [workingIds] — a fully
/// controllable fake that never touches the real filesystem or spawns a
/// process. No `configuredPath`/env is exercised here; every status in
/// these tests comes from the trailing bare-name PATH-tier candidate.
ToolProbe _fakeProbe(Set<String> workingIds) => ToolProbe(
  exists: workingIds.contains,
  run: (exe, args) async => workingIds.contains(exe)
      ? (exitCode: 0, stdout: '$exe v1', stderr: '')
      : (exitCode: 1, stdout: '', stderr: 'not found'),
  // Each tool id resolves as an existence-checked location (no bare-name spawn).
  commonLocations: (tool) => [tool.id],
);

/// A [ToolsController] that counts calls to [installTraceProcessor] and
/// [recheck] before delegating to the real implementation — lets a test
/// assert a button tap drove the right controller method without
/// hand-rolling a fake of the controller's probe/persist/install
/// orchestration.
class _SpyToolsController extends ToolsController {
  _SpyToolsController({
    required super.probe,
    required super.store,
    super.installer,
    super.installDir,
  });

  int installCalls = 0;
  int recheckCalls = 0;

  @override
  Future<void> installTraceProcessor() {
    installCalls++;
    return super.installTraceProcessor();
  }

  @override
  Future<void> recheck() {
    recheckCalls++;
    return super.recheck();
  }
}

Future<void> _pump(WidgetTester tester, ToolsController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: ToolsScreen(controller: controller)),
    ),
  );
}

/// The button labeled [label]. `.icon` factories return a private
/// subtype that `find.byType` (an exact runtimeType match) never finds
/// — matching the pattern already used in `android_capture_screen_test
/// .dart`.
Finder _filledButtonLabeled(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<FilledButton>(),
);

Finder _outlinedButtonLabeled(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<OutlinedButton>(),
);

void main() {
  testWidgets("shows a found tool's path+version and a missing tool's Install/"
      'Locate', (tester) async {
    final controller = ToolsController(
      probe: _fakeProbe({'adb', 'llvm-symbolizer', 'llvm-readelf'}),
      store: _FakeToolConfigStore(),
    );
    await controller.load();

    await _pump(tester, controller);

    // adb resolved via the bare-name PATH tier: path == 'adb', version
    // == 'adb v1'.
    expect(find.textContaining('found · adb · adb v1'), findsOneWidget);

    // trace_processor never verifies here → the only missing tool,
    // with both a Locate… and an Install action (Install only ever
    // shows on the trace_processor card).
    expect(find.text('missing'), findsOneWidget);
    expect(_outlinedButtonLabeled('Locate…'), findsNWidgets(4));
    expect(_filledButtonLabeled('Install'), findsOneWidget);
  });

  testWidgets('tapping Install calls installTraceProcessor', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('tools_screen_test_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final destPath = '${tempDir.path}/trace_processor';
    final controller = _SpyToolsController(
      probe: _fakeProbe({destPath}),
      installer: TraceProcessorInstaller(
        download: (url, dest) async => File(dest).writeAsStringSync('stub'),
      ),
      store: _FakeToolConfigStore(),
      installDir: tempDir.path,
    );
    await controller.load();

    await _pump(tester, controller);

    // TraceProcessorInstaller.install always shells out to a real `chmod
    // +x` after the (here fake) download — a genuine subprocess needs
    // the real event loop, not the fake-clock `pump()` alone, so the tap
    // and the wait for it to finish both run inside `runAsync`.
    await tester.runAsync(() async {
      await tester.tap(_filledButtonLabeled('Install'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(controller.installCalls, 1);
  });

  testWidgets('a failed install surfaces installError with a copy action', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('tools_screen_test_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final controller = ToolsController(
      probe: _fakeProbe(const {}),
      installer: TraceProcessorInstaller(
        download: (url, dest) async => throw Exception('network down'),
      ),
      store: _FakeToolConfigStore(),
      installDir: tempDir.path,
    );
    await controller.load();

    await _pump(tester, controller);

    // installTraceProcessor() does a genuine (fast, no-op here) real
    // `Directory.create` before the fake download throws — real dart:io
    // needs the actual event loop, not the fake-clock `pump()` alone, so
    // the tap and the wait for it to finish both run inside `runAsync`.
    await tester.runAsync(() async {
      await tester.tap(_filledButtonLabeled('Install'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.textContaining('network down'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsWidgets);
  });

  testWidgets('Re-check all calls recheck', (tester) async {
    final controller = _SpyToolsController(
      probe: _fakeProbe(const {}),
      store: _FakeToolConfigStore(),
    );
    await controller.load();

    await _pump(tester, controller);

    await tester.tap(_outlinedButtonLabeled('Re-check all'));
    await tester.pump();

    expect(controller.recheckCalls, 1);
  });

  testWidgets('a missing tool without an installer shows a copyable hint', (
    tester,
  ) async {
    final controller = ToolsController(
      probe: _fakeProbe(const {}),
      store: _FakeToolConfigStore(),
    );
    await controller.load();

    await _pump(tester, controller);

    expect(
      find.textContaining('brew install android-platform-tools'),
      findsOneWidget,
    );
    expect(find.textContaining('Checked:'), findsWidgets);
  });
}
