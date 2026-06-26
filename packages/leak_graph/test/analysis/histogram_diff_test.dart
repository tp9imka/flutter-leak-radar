import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  group('computeDiff', () {
    final uri = Uri.parse('package:app/src/foo.dart');

    ClassCount cc(String name, int count, int bytes) => ClassCount(
      className: name,
      libraryUri: uri,
      instanceCount: count,
      shallowBytes: bytes,
    );

    test('returns empty list when both histograms are empty', () {
      final result = computeDiff([], []);
      expect(result, isEmpty);
    });

    test('detects growth for a class present in both snapshots', () {
      final before = [cc('Foo', 10, 100)];
      final after = [cc('Foo', 25, 250)];

      final result = computeDiff(before, after);

      expect(result, hasLength(1));
      expect(result.first.before.className, 'Foo');
      expect(result.first.instanceDelta, 15);
      expect(result.first.bytesDelta, 150);
    });

    test('treats class absent in before as zero baseline', () {
      final before = <ClassCount>[];
      final after = [cc('Bar', 5, 50)];

      final result = computeDiff(before, after);

      expect(result, hasLength(1));
      expect(result.first.instanceDelta, 5);
    });

    test('omits classes absent from after', () {
      final before = [cc('Gone', 10, 100)];
      final after = <ClassCount>[];

      final result = computeDiff(before, after);

      expect(result, isEmpty);
    });

    test('sorts results by instanceDelta descending', () {
      final before = [cc('A', 10, 0), cc('B', 5, 0), cc('C', 1, 0)];
      final after = [cc('A', 11, 0), cc('B', 20, 0), cc('C', 2, 0)];

      final result = computeDiff(before, after);

      expect(result.map((d) => d.before.className).toList(), ['B', 'A', 'C']);
      expect(result.map((d) => d.instanceDelta).toList(), [15, 1, 1]);
    });

    test('includes zero-delta entries (no growth) in output', () {
      final before = [cc('Stable', 10, 100)];
      final after = [cc('Stable', 10, 100)];

      final result = computeDiff(before, after);

      expect(result, hasLength(1));
      expect(result.first.instanceDelta, 0);
    });

    test('matches by className only, ignores libraryUri differences', () {
      final before = [
        ClassCount(
          className: 'Foo',
          libraryUri: Uri.parse('package:a/foo.dart'),
          instanceCount: 5,
          shallowBytes: 50,
        ),
      ];
      final after = [
        ClassCount(
          className: 'Foo',
          libraryUri: Uri.parse('package:b/foo.dart'),
          instanceCount: 8,
          shallowBytes: 80,
        ),
      ];

      final result = computeDiff(before, after);

      expect(result, hasLength(1));
      expect(result.first.instanceDelta, 3);
    });
  });
}
