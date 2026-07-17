import 'dart:convert';
import 'dart:io';

import 'package:leak_graph/leak_graph.dart';
import 'package:leak_graph/src/cli/diff_command.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

HeapNode _node(int id, String cls, int size) => HeapNode(
  id: id,
  className: cls,
  libraryUri: Uri.parse('package:app/$cls.dart'),
  shallowSize: size,
  edges: const [],
);

/// Loader that returns distinct graphs by path: `before` grows `Foo` and adds a
/// brand-new `New`, while `Gone` disappears.
HeapGraphLoader _twoSnapshots() {
  final before = InMemoryHeapGraph.of({
    0: _node(0, 'Foo', 10),
    1: _node(1, 'Foo', 10),
    2: _node(2, 'Gone', 5),
  });
  final after = InMemoryHeapGraph.of({
    0: _node(0, 'Foo', 10),
    1: _node(1, 'Foo', 10),
    2: _node(2, 'Foo', 10),
    3: _node(3, 'New', 7),
  });
  return (path) async => path == 'before.data' ? before : after;
}

void main() {
  group('runDiff exit codes', () {
    test('two valid snapshots → ok (0)', () async {
      final code = await runDiff(
        ['before.data', 'after.data'],
        out: StringBuffer(),
        err: StringBuffer(),
        loadGraph: _twoSnapshots(),
      );
      expect(code, DiffExit.ok);
    });

    test('missing a positional → usage error (1)', () async {
      final code = await runDiff(
        ['before.data'],
        out: StringBuffer(),
        err: StringBuffer(),
        loadGraph: _twoSnapshots(),
      );
      expect(code, DiffExit.usage);
    });

    test('bad --top → usage error (1)', () async {
      final code = await runDiff(
        ['before.data', 'after.data', '--top', 'x'],
        out: StringBuffer(),
        err: StringBuffer(),
        loadGraph: _twoSnapshots(),
      );
      expect(code, DiffExit.usage);
    });

    test('unreadable snapshot → tool failure (2)', () async {
      final code = await runDiff(
        ['before.data', 'after.data'],
        out: StringBuffer(),
        err: StringBuffer(),
        loadGraph: (path) async =>
            throw FileSystemException('No such file', path),
      );
      expect(code, DiffExit.toolFailure);
    });
  });

  group('runDiff text output', () {
    test('lists growers with signed deltas, omits gone class', () async {
      final out = StringBuffer();
      await runDiff(
        ['before.data', 'after.data'],
        out: out,
        err: StringBuffer(),
        loadGraph: _twoSnapshots(),
      );
      final text = out.toString();
      expect(text, contains('+1  Foo')); // 2 -> 3
      expect(text, contains('+1  New')); // 0 -> 1
      expect(text, isNot(contains('Gone'))); // absent from `after`
    });
  });

  group('runDiff JSON output', () {
    test('emits a schema-stamped envelope with per-class deltas', () async {
      final out = StringBuffer();
      await runDiff(
        ['before.data', 'after.data', '--json'],
        out: out,
        err: StringBuffer(),
        loadGraph: _twoSnapshots(),
      );
      final decoded = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(decoded['schemaVersion'], kClassCountDiffReportSchemaVersion);
      final diffs = (decoded['diffs'] as List).cast<Map<String, Object?>>();
      final foo = diffs.firstWhere((d) => d['className'] == 'Foo');
      expect(foo['instanceDelta'], 1);
      expect(foo['bytesDelta'], 10);
      final newClass = diffs.firstWhere((d) => d['className'] == 'New');
      expect(newClass['instanceDelta'], 1);
    });
  });

  group('ClassCountDiff.toJson', () {
    test('serializes before/after plus derived deltas', () {
      final diff = ClassCountDiff(
        before: ClassCount(
          className: 'Foo',
          libraryUri: Uri.parse('package:app/foo.dart'),
          instanceCount: 3,
          shallowBytes: 30,
        ),
        after: ClassCount(
          className: 'Foo',
          libraryUri: Uri.parse('package:app/foo.dart'),
          instanceCount: 10,
          shallowBytes: 100,
        ),
      );
      final json = diff.toJson();
      expect(json['className'], 'Foo');
      expect(json['instanceDelta'], 7);
      expect(json['bytesDelta'], 70);
      expect((json['before'] as Map)['instanceCount'], 3);
      expect((json['after'] as Map)['instanceCount'], 10);
    });

    test('encodeDiffReport stamps the schema version', () {
      final report = encodeDiffReport(const []);
      expect(report['schemaVersion'], kClassCountDiffReportSchemaVersion);
      expect(report['diffs'], isEmpty);
    });
  });
}
