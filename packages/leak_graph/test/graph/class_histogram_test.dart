import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

void main() {
  test('classHistogram tallies instances, bytes, and library per class', () {
    HeapNode n(int id, String cls, String lib, int size) => HeapNode(
      id: id,
      className: cls,
      libraryUri: Uri.parse(lib),
      shallowSize: size,
      edges: const [],
    );
    final graph = InMemoryHeapGraph.of({
      0: n(0, 'Root', 'dart:core', 0),
      1: n(1, 'Foo', 'package:app/foo.dart', 10),
      2: n(2, 'Foo', 'package:app/foo.dart', 10),
      3: n(3, 'Bar', 'package:app/bar.dart', 5),
    });

    final hist = {for (final c in graph.classHistogram()) c.className: c};

    expect(hist['Foo']!.instanceCount, 2);
    expect(hist['Foo']!.shallowBytes, 20);
    expect(hist['Foo']!.libraryUri.toString(), 'package:app/foo.dart');
    expect(hist['Bar']!.instanceCount, 1);
    expect(hist['Bar']!.shallowBytes, 5);
  });
}
