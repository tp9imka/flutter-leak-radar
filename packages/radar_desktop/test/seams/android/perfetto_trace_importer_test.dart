import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/android/perfetto_trace_importer.dart';
import 'package:radar_desktop/src/tools/tools_controller.dart';
import 'package:radar_native_host/radar_native_host.dart';

/// In-memory [ToolConfigStore] fake — no real fs/path_provider.
class _InMemoryToolConfigStore implements ToolConfigStore {
  ToolConfig config = const ToolConfig({});

  @override
  Future<ToolConfig> read() async => config;

  @override
  Future<void> write(ToolConfig next) async => config = next;
}

void main() {
  group('resolveTraceProcessorBinary', () {
    test('explicit wins over env', () {
      expect(
        resolveTraceProcessorBinary(
          explicit: '/opt/explicit/trace_processor_shell',
          env: const {'RADAR_TP_BIN': '/opt/env/trace_processor_shell'},
        ),
        '/opt/explicit/trace_processor_shell',
      );
    });

    test('falls back to RADAR_TP_BIN when no explicit path', () {
      expect(
        resolveTraceProcessorBinary(
          env: const {'RADAR_TP_BIN': '/opt/env/trace_processor_shell'},
        ),
        '/opt/env/trace_processor_shell',
      );
    });

    test('ignores a null or empty explicit path and falls back to env', () {
      expect(
        resolveTraceProcessorBinary(
          explicit: '',
          env: const {'RADAR_TP_BIN': '/opt/env/trace_processor_shell'},
        ),
        '/opt/env/trace_processor_shell',
      );
    });

    test('throws StateError naming both options when neither is set', () {
      expect(
        () => resolveTraceProcessorBinary(env: const {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('RADAR_TP_BIN'), contains('trace_processor')),
          ),
        ),
      );
    });

    test('treats an empty RADAR_TP_BIN as unset', () {
      expect(
        () => resolveTraceProcessorBinary(env: const {'RADAR_TP_BIN': ''}),
        throwsStateError,
      );
    });
  });

  group('PerfettoTraceImporter.traceProcessorPath resolver', () {
    // These never reach a real trace_processor invocation: the resolved
    // path doesn't exist, so Process.run throws a ProcessException naming
    // it — proof enough that the right path was actually used, without
    // needing a real binary or a fake process seam on this importer.
    test('a non-null resolver result wins as the explicit path', () async {
      final importer = PerfettoTraceImporter(traceProcessorPath: () => '/x/tp');

      await expectLater(
        importer.importTrace('irrelevant.pftrace', label: 'x'),
        throwsA(
          isA<ProcessException>().having(
            (e) => e.executable,
            'executable',
            '/x/tp',
          ),
        ),
      );
    });

    test(
      'a null resolver result falls back to env/throw exactly as before',
      () async {
        final importer = PerfettoTraceImporter(traceProcessorPath: () => null);
        final envBin = Platform.environment['RADAR_TP_BIN'];

        final future = importer.importTrace('irrelevant.pftrace', label: 'x');
        if (envBin == null || envBin.isEmpty) {
          await expectLater(future, throwsStateError);
        } else {
          await expectLater(
            future,
            throwsA(
              isA<ProcessException>().having(
                (e) => e.executable,
                'executable',
                envBin,
              ),
            ),
          );
        }
      },
    );

    test('no resolver at all keeps today\'s env/throw behavior', () async {
      const importer = PerfettoTraceImporter();
      final envBin = Platform.environment['RADAR_TP_BIN'];

      final future = importer.importTrace('irrelevant.pftrace', label: 'x');
      if (envBin == null || envBin.isEmpty) {
        await expectLater(future, throwsStateError);
      } else {
        await expectLater(
          future,
          throwsA(
            isA<ProcessException>().having(
              (e) => e.executable,
              'executable',
              envBin,
            ),
          ),
        );
      }
    });

    test('a ToolsController.locate() call is reflected on the very next '
        'import — lazily, with no importer rebuild', () async {
      final probe = ToolProbe(
        exists: (path) => path == '/located/tp',
        run: (exe, args) async => exe == '/located/tp'
            ? (exitCode: 0, stdout: 'tp v1', stderr: '')
            : (exitCode: 1, stdout: '', stderr: 'not found'),
        commonLocations: (_) => const [],
      );
      final tools = ToolsController(
        probe: probe,
        store: _InMemoryToolConfigStore(),
        env: const {},
      );
      await tools.load();
      expect(tools.resolvedPath(ExternalTool.traceProcessor), isNull);

      final importer = PerfettoTraceImporter(
        traceProcessorPath: () =>
            tools.resolvedPath(ExternalTool.traceProcessor),
      );

      await tools.locate(ExternalTool.traceProcessor, '/located/tp');

      await expectLater(
        importer.importTrace('irrelevant.pftrace', label: 'x'),
        throwsA(
          isA<ProcessException>().having(
            (e) => e.executable,
            'executable',
            '/located/tp',
          ),
        ),
      );
    });
  });
}
