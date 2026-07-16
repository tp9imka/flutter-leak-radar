import 'dart:convert';
import 'dart:io';

import 'package:leak_graph/leak_graph.dart';
import 'package:leak_graph/src/cli/analyze_command.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

HeapNode _node(
  int id,
  String cls,
  String lib,
  int size,
  List<HeapEdge> edges,
) => HeapNode(
  id: id,
  className: cls,
  libraryUri: Uri.parse(lib),
  shallowSize: size,
  edges: edges,
);

/// Two timers each retaining a `LeakyState`, so `--package my_app` yields one
/// cluster of two instances at the default min-cluster of 2.
InMemoryHeapGraph _leakGraph() => InMemoryHeapGraph.of({
  0: _node(0, 'Root', 'dart:core', 0, const [
    HeapEdge(targetId: 1),
    HeapEdge(targetId: 3),
  ]),
  1: _node(1, '_Timer', 'dart:async', 64, const [
    HeapEdge(targetId: 2, field: '_callback'),
  ]),
  2: _node(2, 'LeakyState', 'package:my_app/leaky.dart', 128, const []),
  3: _node(3, '_Timer', 'dart:async', 64, const [
    HeapEdge(targetId: 4, field: '_callback'),
  ]),
  4: _node(4, 'LeakyState', 'package:my_app/leaky.dart', 128, const []),
});

/// An in-memory file system for readText/writeText injection.
final class _FakeFiles {
  final Map<String, String> _files = {};

  Future<void> write(String path, String contents) async =>
      _files[path] = contents;

  Future<String> read(String path) async {
    final value = _files[path];
    if (value == null) {
      throw FileSystemException('No such file', path);
    }
    return value;
  }

  String? operator [](String path) => _files[path];
}

Future<int> _run(
  List<String> argv, {
  required StringSink out,
  required StringSink err,
  HeapGraphLoader? loadGraph,
  _FakeFiles? files,
}) {
  final fs = files ?? _FakeFiles();
  return runAnalyze(
    argv,
    out: out,
    err: err,
    loadGraph: loadGraph ?? (_) async => _leakGraph(),
    readText: fs.read,
    writeText: fs.write,
    now: () => DateTime.utc(2026, 7, 17),
  );
}

void main() {
  group('exit-code mapping', () {
    test('bad flag value → usage error (1)', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await _run(
        ['dump.data', '--min-cluster', 'notanint'],
        out: out,
        err: err,
      );
      expect(code, AnalyzeExit.usage);
    });

    test('unknown --min-confidence tier → usage error (1)', () async {
      final code = await _run(
        [
          'dump.data',
          '--min-confidence',
          'probable',
          '--max-total-clusters',
          '0',
        ],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, AnalyzeExit.usage);
    });

    test('missing dump path → usage error (1)', () async {
      final code = await _run(
        ['--all'],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, AnalyzeExit.usage);
    });

    test('unreadable snapshot → tool failure (2)', () async {
      final code = await _run(
        ['missing.data'],
        out: StringBuffer(),
        err: StringBuffer(),
        loadGraph: (_) async =>
            throw FileSystemException('No such file', 'missing.data'),
      );
      expect(code, AnalyzeExit.toolFailure);
    });

    test('successful analysis with no gate → ok (0)', () async {
      final code = await _run(
        ['dump.data', '--package', 'my_app'],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, AnalyzeExit.ok);
    });
  });

  group('byte-stable report on stdout', () {
    test('no new flags emits exactly the rendered report + newline', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      await _run(['dump.data', '--package', 'my_app'], out: out, err: err);

      final result = const GraphLeakAnalyzer().analyze(
        _leakGraph(),
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );
      expect(out.toString(), '${renderReport(result, top: 50)}\n');
      // Gate/baseline diagnostics must never leak into the stdout report.
      expect(out.toString(), isNot(contains('Gate')));
      expect(out.toString(), isNot(contains('baseline')));
    });

    test('stdout is unchanged when gate flags are present', () async {
      final noGate = StringBuffer();
      final withGate = StringBuffer();
      await _run(
        ['dump.data', '--package', 'my_app'],
        out: noGate,
        err: StringBuffer(),
      );
      await _run(
        ['dump.data', '--package', 'my_app', '--max-total-clusters', '99'],
        out: withGate,
        err: StringBuffer(),
      );
      expect(withGate.toString(), noGate.toString());
    });
  });

  group('write-baseline', () {
    test('persists a parseable baseline and reports on stderr', () async {
      final files = _FakeFiles();
      final err = StringBuffer();
      final code = await _run(
        ['dump.data', '--package', 'my_app', '--write-baseline', 'base.json'],
        out: StringBuffer(),
        err: err,
        files: files,
      );
      expect(code, AnalyzeExit.ok);
      final written = files['base.json'];
      expect(written, isNotNull);
      final baseline = LeakBaseline.fromJson(
        jsonDecode(written!) as Map<String, Object?>,
      );
      expect(baseline.schemaVersion, kLeakBaselineSchemaVersion);
      expect(baseline.clustersBySignature, isNotEmpty);
      expect(err.toString(), contains('Wrote baseline'));
    });
  });

  group('baseline gating', () {
    test(
      'write then compare against itself passes --fail-on-new-clusters',
      () async {
        final files = _FakeFiles();
        await _run(
          ['dump.data', '--package', 'my_app', '--write-baseline', 'base.json'],
          out: StringBuffer(),
          err: StringBuffer(),
          files: files,
        );
        final code = await _run(
          [
            'dump.data',
            '--package',
            'my_app',
            '--baseline',
            'base.json',
            '--fail-on-new-clusters',
          ],
          out: StringBuffer(),
          err: StringBuffer(),
          files: files,
        );
        expect(code, AnalyzeExit.ok);
      },
    );

    test('new cluster vs empty baseline fails the gate (3)', () async {
      final files = _FakeFiles();
      await files.write(
        'empty.json',
        jsonEncode({
          'schemaVersion': 1,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'clusters': <Object?>[],
        }),
      );
      final err = StringBuffer();
      final code = await _run(
        [
          'dump.data',
          '--package',
          'my_app',
          '--baseline',
          'empty.json',
          '--fail-on-new-clusters',
        ],
        out: StringBuffer(),
        err: err,
        files: files,
      );
      expect(code, AnalyzeExit.gateFailed);
      expect(err.toString(), contains('Gate FAILED'));
    });

    test('generous --max-new-clusters passes despite new clusters', () async {
      final files = _FakeFiles();
      await files.write(
        'empty.json',
        jsonEncode({
          'schemaVersion': 1,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'clusters': <Object?>[],
        }),
      );
      final code = await _run(
        [
          'dump.data',
          '--package',
          'my_app',
          '--baseline',
          'empty.json',
          '--max-new-clusters',
          '5',
        ],
        out: StringBuffer(),
        err: StringBuffer(),
        files: files,
      );
      expect(code, AnalyzeExit.ok);
    });

    test('max-total-clusters gates without any baseline (fail → 3)', () async {
      final code = await _run(
        ['dump.data', '--package', 'my_app', '--max-total-clusters', '0'],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, AnalyzeExit.gateFailed);
    });

    test('max-total-clusters within limit passes (0)', () async {
      final code = await _run(
        ['dump.data', '--package', 'my_app', '--max-total-clusters', '10'],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, AnalyzeExit.ok);
    });
  });

  group('honest degradation on absent / incomparable baselines', () {
    test(
      'baseline-dependent gate without --baseline → usage error (1)',
      () async {
        final err = StringBuffer();
        final code = await _run(
          ['dump.data', '--package', 'my_app', '--fail-on-new-clusters'],
          out: StringBuffer(),
          err: err,
          files: _FakeFiles(),
        );
        expect(code, AnalyzeExit.usage);
        expect(err.toString(), contains('no --baseline'));
      },
    );

    test('unreadable baseline file with a gate → tool failure (2)', () async {
      final code = await _run(
        [
          'dump.data',
          '--package',
          'my_app',
          '--baseline',
          'missing.json',
          '--fail-on-new-clusters',
        ],
        out: StringBuffer(),
        err: StringBuffer(),
        files: _FakeFiles(),
      );
      expect(code, AnalyzeExit.toolFailure);
    });

    test('incomparable baseline + baseline-dependent gate → tool failure (2), '
        'never all-NEW', () async {
      final files = _FakeFiles();
      await files.write(
        'future.json',
        jsonEncode({
          'schemaVersion': 2,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'clusters': <Object?>[],
        }),
      );
      final err = StringBuffer();
      final code = await _run(
        [
          'dump.data',
          '--package',
          'my_app',
          '--baseline',
          'future.json',
          '--fail-on-new-clusters',
        ],
        out: StringBuffer(),
        err: err,
        files: files,
      );
      expect(code, AnalyzeExit.toolFailure);
      expect(
        err.toString(),
        contains('baseline not comparable (schemaVersion 2)'),
      );
      // Must NOT have run the gate and failed it as if everything were new.
      expect(err.toString(), isNot(contains('Gate FAILED')));
    });

    test(
      'incomparable baseline with only a total gate degrades to absent',
      () async {
        final files = _FakeFiles();
        await files.write(
          'future.json',
          jsonEncode({
            'schemaVersion': 2,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'clusters': <Object?>[],
          }),
        );
        final err = StringBuffer();
        final code = await _run(
          [
            'dump.data',
            '--package',
            'my_app',
            '--baseline',
            'future.json',
            '--max-total-clusters',
            '10',
          ],
          out: StringBuffer(),
          err: err,
          files: files,
        );
        expect(code, AnalyzeExit.ok);
        expect(err.toString(), contains('baseline not comparable'));
      },
    );
  });

  group('--format', () {
    test('defaults to text: identical to the byte-stable report', () async {
      final defaultOut = StringBuffer();
      final explicitOut = StringBuffer();
      await _run(
        ['dump.data', '--package', 'my_app'],
        out: defaultOut,
        err: StringBuffer(),
      );
      await _run(
        ['dump.data', '--package', 'my_app', '--format', 'text'],
        out: explicitOut,
        err: StringBuffer(),
      );
      expect(explicitOut.toString(), defaultOut.toString());
    });

    test('--format json prints the JSON envelope to stdout', () async {
      final out = StringBuffer();
      final code = await _run(
        ['dump.data', '--package', 'my_app', '--format', 'json'],
        out: out,
        err: StringBuffer(),
      );
      expect(code, AnalyzeExit.ok);
      final decoded = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(decoded['clusters'], isA<List<Object?>>());

      final result = const GraphLeakAnalyzer().analyze(
        _leakGraph(),
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );
      expect(out.toString(), '${renderJson(result)}\n');
    });

    test('--format md prints the 30-second markdown report', () async {
      final out = StringBuffer();
      final code = await _run(
        ['dump.data', '--package', 'my_app', '--format', 'md'],
        out: out,
        err: StringBuffer(),
      );
      expect(code, AnalyzeExit.ok);
      expect(out.toString(), contains('clusters (no gate)'));
      expect(out.toString(), isNot(contains('[!CAUTION]')));
    });

    test(
      '--format github renders a GitHub admonition when the gate fails',
      () async {
        final files = _FakeFiles();
        await files.write(
          'empty.json',
          jsonEncode({
            'schemaVersion': 1,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'clusters': <Object?>[],
          }),
        );
        final out = StringBuffer();
        final err = StringBuffer();
        final code = await _run(
          [
            'dump.data',
            '--package',
            'my_app',
            '--format',
            'github',
            '--baseline',
            'empty.json',
            '--fail-on-new-clusters',
          ],
          out: out,
          err: err,
          files: files,
        );
        expect(code, AnalyzeExit.gateFailed);
        expect(out.toString(), contains('❌ gate failed'));
        expect(out.toString(), contains('[!CAUTION]'));
        expect(err.toString(), contains('Gate FAILED'));
      },
    );

    test('unknown --format value is a usage error (1)', () async {
      final code = await _run(
        ['dump.data', '--format', 'yaml'],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, AnalyzeExit.usage);
    });
  });

  group('--json output', () {
    test('writes the analysis JSON to the given path', () async {
      final files = _FakeFiles();
      await _run(
        ['dump.data', '--package', 'my_app', '--json', 'out.json'],
        out: StringBuffer(),
        err: StringBuffer(),
        files: files,
      );
      final written = files['out.json'];
      expect(written, isNotNull);
      final decoded = jsonDecode(written!) as Map<String, Object?>;
      expect(decoded['clusters'], isA<List<Object?>>());
    });
  });
}
