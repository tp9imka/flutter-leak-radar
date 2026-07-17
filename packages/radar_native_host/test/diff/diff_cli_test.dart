import 'dart:convert';

import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

/// Returns rows keyed by trace path, so `before` and `after` parse to
/// different profiles from the same runner.
class _PathKeyedRunner implements TraceProcessorRunner {
  _PathKeyedRunner(this.byPath);

  final Map<String, List<PerfettoRow>> byPath;

  @override
  Future<List<PerfettoRow>> query(String tracePath) async =>
      byPath[tracePath] ?? const [];
}

/// A runner that always throws — models a trace_processor process failure.
class _ThrowingRunner implements TraceProcessorRunner {
  @override
  Future<List<PerfettoRow>> query(String tracePath) async =>
      throw const TraceProcessorException('boom', stderr: 'bad trace');
}

PerfettoRow _leak(int callsiteId, int allocBytes) => PerfettoRow(
  callsiteId: callsiteId,
  depth: 0,
  function: 'Leaky::grow',
  module: 'libfoo.so',
  allocBytes: allocBytes,
  allocCount: 1,
  freeBytes: 0,
  freeCount: 0,
);

void main() {
  group('runDiff', () {
    final runner = _PathKeyedRunner({
      'before.pftrace': [_leak(1, 4096)],
      'after.pftrace': [_leak(1, 40960)],
    });

    test('json: envelope carries module and callsite diffs', () async {
      final out = StringBuffer();

      final code = await runDiff(
        ['before.pftrace', 'after.pftrace', '--format', 'json'],
        runner: runner,
        out: out,
        err: StringBuffer(),
      );

      expect(code, 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['schemaVersion'], 1);

      final modules = (json['modules'] as List).cast<Map<String, Object?>>();
      final foo = modules.firstWhere((m) => m['module'] == 'libfoo.so');
      expect(foo['beforeStillLiveBytes'], 4096);
      expect(foo['afterStillLiveBytes'], 40960);

      final callsites = (json['callsites'] as List)
          .cast<Map<String, Object?>>();
      expect(callsites, hasLength(1));
      expect(callsites.single['beforeStillLiveBytes'], 4096);
      expect(callsites.single['afterStillLiveBytes'], 40960);
    });

    test('md: renders a module table and the growth', () async {
      final out = StringBuffer();

      final code = await runDiff(
        ['before.pftrace', 'after.pftrace', '--format', 'md'],
        runner: runner,
        out: out,
        err: StringBuffer(),
      );

      expect(code, 0);
      final md = out.toString();
      expect(md, contains('libfoo.so'));
      expect(md, contains('|')); // a table
      // The growth (40960 - 4096 = 36864 bytes = 36 KiB) is surfaced.
      expect(md, contains('4096'));
      expect(md, contains('40960'));
    });

    test('md is the default format', () async {
      final out = StringBuffer();
      final code = await runDiff(
        ['before.pftrace', 'after.pftrace'],
        runner: runner,
        out: out,
        err: StringBuffer(),
      );
      expect(code, 0);
      expect(out.toString(), contains('|'));
    });

    test('missing second trace: exit 2 usage', () async {
      final err = StringBuffer();
      final code = await runDiff(['before.pftrace'], runner: runner, err: err);
      expect(code, 2);
      expect(err.toString(), contains('two'));
    });

    test('unknown --format: exit 2 usage', () async {
      final err = StringBuffer();
      final code = await runDiff(
        ['before.pftrace', 'after.pftrace', '--format', 'yaml'],
        runner: runner,
        err: err,
      );
      expect(code, 2);
      expect(err.toString(), contains('format'));
    });

    test('no trace_processor and no injected runner: exit 2 usage', () async {
      final err = StringBuffer();
      final code = await runDiff(
        ['before.pftrace', 'after.pftrace'],
        env: const {},
        err: err,
      );
      expect(code, 2);
      expect(err.toString(), contains('trace_processor'));
    });

    test('trace_processor failure: exit 1 tool failure', () async {
      final err = StringBuffer();
      final code = await runDiff(
        ['before.pftrace', 'after.pftrace'],
        runner: _ThrowingRunner(),
        err: err,
      );
      expect(code, 1);
      expect(err.toString(), contains('trace_processor'));
    });
  });
}
