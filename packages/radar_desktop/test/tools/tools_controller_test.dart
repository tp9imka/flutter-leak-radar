import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/tools/tools_controller.dart';
import 'package:radar_native_host/radar_native_host.dart';

/// In-memory [ToolConfigStore] fake — no real fs/path_provider.
class _FakeToolConfigStore implements ToolConfigStore {
  ToolConfig config = const ToolConfig({});
  int writeCount = 0;

  @override
  Future<ToolConfig> read() async => config;

  @override
  Future<void> write(ToolConfig next) async {
    config = next;
    writeCount++;
  }
}

/// Builds a [ToolProbe] whose candidates verify only when the candidate
/// path is a member of [workingPaths] — a fully controllable fake that
/// never touches the real filesystem or spawns a process. [workingPaths]
/// is mutable so a test can simulate a tool appearing later (e.g. after
/// an install) without rebuilding the probe.
ToolProbe _fakeProbe(Set<String> workingPaths) => ToolProbe(
  exists: workingPaths.contains,
  run: (exe, args) async => workingPaths.contains(exe)
      ? (exitCode: 0, stdout: '$exe v1', stderr: '')
      : (exitCode: 1, stdout: '', stderr: 'not found'),
  commonLocations: (_) => const [],
);

void main() {
  group('ToolsController.load', () {
    test('probes every ExternalTool and populates statuses', () async {
      final controller = ToolsController(
        probe: _fakeProbe({'adb'}),
        store: _FakeToolConfigStore(),
      );

      await controller.load();

      expect(controller.statuses, hasLength(ExternalTool.values.length));
      expect(controller.statusOf(ExternalTool.adb).found, isTrue);
      expect(controller.statusOf(ExternalTool.traceProcessor).found, isFalse);
      expect(controller.allRequiredPresent, isFalse);
      expect(controller.anyMissing, isTrue);
    });

    test(
      'resolves a tool via its env var when nothing is configured',
      () async {
        final controller = ToolsController(
          probe: _fakeProbe({'/env/trace_processor'}),
          store: _FakeToolConfigStore(),
          env: const {'RADAR_TP_BIN': '/env/trace_processor'},
        );

        await controller.load();

        final status = controller.statusOf(ExternalTool.traceProcessor);
        expect(status.found, isTrue);
        expect(status.source, ToolSource.env);
        expect(status.path, '/env/trace_processor');
        expect(controller.allRequiredPresent, isTrue);
      },
    );

    test('reads a previously persisted config on first load', () async {
      final store = _FakeToolConfigStore()
        ..config = const ToolConfig({'adb': '/persisted/adb'});
      final controller = ToolsController(
        probe: _fakeProbe({'/persisted/adb'}),
        store: store,
      );

      await controller.load();

      expect(controller.resolvedPath(ExternalTool.adb), '/persisted/adb');
      expect(controller.statusOf(ExternalTool.adb).source, ToolSource.config);
    });
  });

  group('ToolsController.locate', () {
    test(
      'writes the config and re-probes so resolvedPath/statusOf update',
      () async {
        final store = _FakeToolConfigStore();
        final controller = ToolsController(
          probe: _fakeProbe({'/set/by/user/trace_processor'}),
          store: store,
        );
        await controller.load();
        expect(controller.resolvedPath(ExternalTool.traceProcessor), isNull);

        await controller.locate(
          ExternalTool.traceProcessor,
          '/set/by/user/trace_processor',
        );

        expect(
          controller.resolvedPath(ExternalTool.traceProcessor),
          '/set/by/user/trace_processor',
        );
        expect(
          controller.statusOf(ExternalTool.traceProcessor).source,
          ToolSource.config,
        );
        expect(store.writeCount, 1);
        expect(
          store.config.pathByToolId['trace_processor'],
          '/set/by/user/trace_processor',
        );
      },
    );

    test('notifies listeners', () async {
      final controller = ToolsController(
        probe: _fakeProbe({'/x/adb'}),
        store: _FakeToolConfigStore(),
      );
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.locate(ExternalTool.adb, '/x/adb');

      expect(notified, 1);
    });

    test('flips allRequiredPresent/anyMissing once trace_processor is '
        'located', () async {
      final workingPaths = <String>{'adb', 'llvm-symbolizer', 'llvm-readelf'};
      final controller = ToolsController(
        probe: _fakeProbe(workingPaths),
        store: _FakeToolConfigStore(),
      );
      await controller.load();
      expect(controller.allRequiredPresent, isFalse);
      expect(controller.anyMissing, isTrue);

      workingPaths.add('/found/trace_processor');
      await controller.locate(
        ExternalTool.traceProcessor,
        '/found/trace_processor',
      );

      expect(controller.allRequiredPresent, isTrue);
      expect(controller.anyMissing, isFalse);
    });
  });

  group('ToolsController.recheck', () {
    test('re-probes without re-reading the store, picking up a tool that '
        'has since appeared at its already-configured location', () async {
      final workingPaths = <String>{};
      final controller = ToolsController(
        probe: _fakeProbe(workingPaths),
        store: _FakeToolConfigStore(),
      );
      await controller.load();
      expect(controller.statusOf(ExternalTool.adb).found, isFalse);

      workingPaths.add('adb');
      await controller.recheck();

      expect(controller.statusOf(ExternalTool.adb).found, isTrue);
    });
  });

  group('ToolsController.installTraceProcessor', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('tools_controller_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('downloads, locates, and marks trace_processor found', () async {
      final destPath = '${tempDir.path}/trace_processor';
      final controller = ToolsController(
        probe: _fakeProbe({destPath}),
        installer: TraceProcessorInstaller(
          download: (url, dest) async => File(dest).writeAsStringSync('stub'),
        ),
        store: _FakeToolConfigStore(),
        installDir: tempDir.path,
      );

      await controller.installTraceProcessor();

      expect(controller.installError, isNull);
      final status = controller.statusOf(ExternalTool.traceProcessor);
      expect(status.found, isTrue);
      expect(status.path, destPath);
      expect(controller.allRequiredPresent, isTrue);
    });

    test('a throwing installer sets installError without throwing', () async {
      final controller = ToolsController(
        probe: _fakeProbe(const {}),
        installer: TraceProcessorInstaller(
          download: (url, dest) async => throw Exception('network down'),
        ),
        store: _FakeToolConfigStore(),
        installDir: tempDir.path,
      );

      await controller.installTraceProcessor();

      expect(controller.installError, isNotNull);
      expect(controller.statusOf(ExternalTool.traceProcessor).found, isFalse);
    });
  });
}
