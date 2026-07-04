import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

/// Canned successful `--version` result.
Future<({int exitCode, String stdout, String stderr})> _ok(
  String exe,
  List<String> args,
) async => (exitCode: 0, stdout: 'v1', stderr: '');

void main() {
  group('ExternalToolInfo', () {
    test('trace_processor is id/env/required for import', () {
      expect(ExternalTool.traceProcessor.id, 'trace_processor');
      expect(ExternalTool.traceProcessor.envVar, 'RADAR_TP_BIN');
      expect(ExternalTool.traceProcessor.isRequiredForImport, isTrue);
    });

    test('adb has no dedicated env var and is not import-required', () {
      expect(ExternalTool.adb.id, 'adb');
      expect(ExternalTool.adb.envVar, isEmpty);
      expect(ExternalTool.adb.isRequiredForImport, isFalse);
    });

    test('llvm-symbolizer id and env var', () {
      expect(ExternalTool.llvmSymbolizer.id, 'llvm-symbolizer');
      expect(ExternalTool.llvmSymbolizer.envVar, 'RADAR_LLVM_SYMBOLIZER');
    });

    test('llvm-readelf id and env var', () {
      expect(ExternalTool.llvmReadelf.id, 'llvm-readelf');
      expect(ExternalTool.llvmReadelf.envVar, 'RADAR_READELF');
    });

    test('every tool has a label, purpose and non-empty versionArgs', () {
      for (final tool in ExternalTool.values) {
        expect(tool.label, isNotEmpty);
        expect(tool.purpose, isNotEmpty);
        expect(tool.versionArgs, isNotEmpty);
      }
    });
  });

  group('ToolProbe.probe', () {
    test('a configuredPath that exists and verifies is found, '
        'source config, version parsed', () async {
      const configured = '/configured/trace_processor';
      final probe = ToolProbe(
        exists: (path) => path == configured,
        run: (exe, args) async {
          expect(exe, configured);
          expect(args, ExternalTool.traceProcessor.versionArgs);
          return (exitCode: 0, stdout: 'trace_processor v42\n', stderr: '');
        },
      );

      final status = await probe.probe(
        ExternalTool.traceProcessor,
        configuredPath: configured,
      );

      expect(status.tool, ExternalTool.traceProcessor);
      expect(status.found, isTrue);
      expect(status.source, ToolSource.config);
      expect(status.path, configured);
      expect(status.version, 'trace_processor v42');
    });

    test('a missing configuredPath falls through to a verifying env path, '
        'source env', () async {
      const envPath = '/env/trace_processor';
      final probe = ToolProbe(exists: (path) => path == envPath, run: _ok);

      final status = await probe.probe(
        ExternalTool.traceProcessor,
        configuredPath: '/missing/trace_processor',
        env: {'RADAR_TP_BIN': envPath},
      );

      expect(status.found, isTrue);
      expect(status.source, ToolSource.env);
      expect(status.path, envPath);
    });

    test('nothing configured or in env but a homebrew common location '
        'verifies, source homebrew', () async {
      const homebrewPath = '/opt/homebrew/bin/trace_processor';
      final probe = ToolProbe(
        exists: (path) => path == homebrewPath,
        run: _ok,
        commonLocations: (tool) => ['/opt/homebrew/bin/${tool.id}'],
      );

      final status = await probe.probe(ExternalTool.traceProcessor);

      expect(status.found, isTrue);
      expect(status.source, ToolSource.homebrew);
      expect(status.path, homebrewPath);
    });

    test('a candidate that exists but whose --version exits non-zero '
        'falls through to the next candidate', () async {
      final probe = ToolProbe(
        exists: (path) => true,
        run: (exe, args) async {
          if (exe == '/broken/trace_processor') {
            return (exitCode: 1, stdout: '', stderr: 'boom');
          }
          return (exitCode: 0, stdout: 'v2', stderr: '');
        },
        commonLocations: (tool) => ['/broken/${tool.id}', '/good/${tool.id}'],
      );

      final status = await probe.probe(ExternalTool.traceProcessor);

      expect(status.found, isTrue);
      expect(status.path, '/good/trace_processor');
    });

    test('nothing found anywhere yields found=false, source=none', () async {
      final probe = ToolProbe(
        exists: (path) => false,
        run: (exe, args) async =>
            (exitCode: 1, stdout: '', stderr: 'not found'),
        commonLocations: (tool) => const [],
      );

      final status = await probe.probe(ExternalTool.adb);

      expect(status.found, isFalse);
      expect(status.source, ToolSource.none);
      expect(status.path, isNull);
      expect(status.version, isNull);
    });

    test('adb has no env var so an unrelated env entry is ignored', () async {
      final existsCalls = <String>[];
      final probe = ToolProbe(
        exists: (path) {
          existsCalls.add(path);
          return false;
        },
        run: (exe, args) async => (exitCode: 1, stdout: '', stderr: ''),
        commonLocations: (tool) => const [],
      );

      await probe.probe(ExternalTool.adb, env: {'SOME_OTHER_VAR': '/x/adb'});

      expect(existsCalls, isNot(contains('/x/adb')));
    });

    test(
      'the bare tool id is attempted last, without an exists check',
      () async {
        final existsCalls = <String>[];
        final runExes = <String>[];
        final probe = ToolProbe(
          exists: (path) {
            existsCalls.add(path);
            return false;
          },
          run: (exe, args) async {
            runExes.add(exe);
            if (exe == 'adb') {
              return (
                exitCode: 0,
                stdout: 'Android Debug Bridge 1.0.41',
                stderr: '',
              );
            }
            return (exitCode: 1, stdout: '', stderr: '');
          },
          commonLocations: (tool) => const [],
        );

        final status = await probe.probe(ExternalTool.adb);

        expect(status.found, isTrue);
        expect(status.source, ToolSource.path);
        expect(status.path, 'adb');
        expect(runExes.last, 'adb');
        expect(existsCalls, isNot(contains('adb')));
      },
    );

    test(
      'a common location under the Android SDK is source androidSdk',
      () async {
        const sdkPath = '/home/Library/Android/sdk/platform-tools/adb';
        final probe = ToolProbe(
          exists: (path) => path == sdkPath,
          run: _ok,
          commonLocations: (tool) => [sdkPath],
        );

        final status = await probe.probe(ExternalTool.adb);

        expect(status.source, ToolSource.androidSdk);
      },
    );

    test('a common location under an NDK toolchain is source ndk', () async {
      const ndkPath =
          '/home/Library/Android/sdk/ndk/27.0.1/toolchains/llvm/'
          'prebuilt/darwin-x86_64/bin/llvm-symbolizer';
      final probe = ToolProbe(
        exists: (path) => path == ndkPath,
        run: _ok,
        commonLocations: (tool) => [ndkPath],
      );

      final status = await probe.probe(ExternalTool.llvmSymbolizer);

      expect(status.source, ToolSource.ndk);
    });

    test('the reported version is the first non-empty stdout line', () async {
      final probe = ToolProbe(
        exists: (path) => true,
        run: (exe, args) async => (
          exitCode: 0,
          stdout: '\n  trace_processor 42  \nother',
          stderr: '',
        ),
      );

      final status = await probe.probe(
        ExternalTool.traceProcessor,
        configuredPath: '/x/trace_processor',
      );

      expect(status.version, 'trace_processor 42');
    });

    test('falls back to stderr when stdout is empty', () async {
      final probe = ToolProbe(
        exists: (path) => true,
        run: (exe, args) async => (exitCode: 0, stdout: '', stderr: 'v7'),
      );

      final status = await probe.probe(
        ExternalTool.traceProcessor,
        configuredPath: '/x/trace_processor',
      );

      expect(status.version, 'v7');
    });

    test('the app-managed common location (from the real default locations) '
        'is existence-checked, unlike the bare-name PATH candidate', () async {
      final existsCalls = <String>[];
      final runExes = <String>[];
      const fakeHome = '/fake/home/for/tool-probe-test';
      const appManagedPath =
          '$fakeHome/Library/Application Support/radar_desktop/bin/'
          'trace_processor';
      final probe = ToolProbe(
        homeDir: fakeHome,
        exists: (path) {
          existsCalls.add(path);
          return false;
        },
        run: (exe, args) async {
          runExes.add(exe);
          return (exitCode: 1, stdout: '', stderr: '');
        },
      );

      final status = await probe.probe(ExternalTool.traceProcessor);

      expect(existsCalls, contains(appManagedPath));
      expect(runExes, isNot(contains(appManagedPath)));
      expect(status.found, isFalse);
    });

    test('an app-managed common location that exists and verifies is source '
        'appManaged, not path', () async {
      const fakeHome = '/fake/home/for/tool-probe-test';
      const appManagedPath =
          '$fakeHome/Library/Application Support/radar_desktop/bin/'
          'trace_processor';
      final probe = ToolProbe(
        homeDir: fakeHome,
        exists: (path) => path == appManagedPath,
        run: _ok,
      );

      final status = await probe.probe(ExternalTool.traceProcessor);

      expect(status.found, isTrue);
      expect(status.source, ToolSource.appManaged);
      expect(status.path, appManagedPath);
    });
  });
}
