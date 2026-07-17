@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Exercises `bin/capture.dart`'s process exit codes against the
/// initiative-wide contract (0 ok / 1 usage / 2 tool failure). The bin calls
/// `exit()` directly, so it is driven as a real subprocess.
void main() {
  Future<ProcessResult> runCapture(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/capture.dart', ...args],
  );

  test('--help exits 0', () async {
    final result = await runCapture(['--help']);
    expect(result.exitCode, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'a missing --uri is a usage error (exit 1)',
    () async {
      final result = await runCapture([]);
      expect(result.exitCode, 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an unreachable VM Service is a tool failure (exit 2)',
    () async {
      // Port 1 refuses immediately, so the connect attempt fails fast.
      final result = await runCapture([
        '--uri',
        'http://127.0.0.1:1/AAAA=/',
        '-o',
        '${Directory.systemTemp.path}/leak_graph_capture_test.data',
      ]);
      expect(result.exitCode, 2);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
