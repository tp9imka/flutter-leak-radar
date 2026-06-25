// test/engine/heap_graph_source_test.dart
import 'package:flutter_leak_radar/src/engine/heap_graph_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';

void main() {
  group('HeapGraphSource interface', () {
    test(
      'FakeHeapGraphSource returns a graph when under the size limit',
      () async {
        final fake = _FakeHeapGraphSource(nodeCount: 10);
        final view = await fake.acquire(maxObjects: 100);
        expect(view, isNotNull);
        expect(view!.nodeCount, 10);
      },
    );

    test(
      'FakeHeapGraphSource returns null when node count exceeds maxObjects',
      () async {
        final fake = _FakeHeapGraphSource(nodeCount: 200);
        final view = await fake.acquire(maxObjects: 100);
        expect(view, isNull);
      },
    );

    test(
      'FakeHeapGraphSource returns null when node count equals maxObjects',
      () async {
        final fake = _FakeHeapGraphSource(nodeCount: 50);
        final view = await fake.acquire(maxObjects: 50);
        expect(view, isNull);
      },
    );
  });
}

/// A fake [HeapGraphSource] backed by an [_InMemoryHeapGraph] for testing
/// the interface contract and the size guard in isolation.
final class _FakeHeapGraphSource implements HeapGraphSource {
  const _FakeHeapGraphSource({required this.nodeCount});

  final int nodeCount;

  @override
  Future<HeapGraphView?> acquire({required int maxObjects}) async {
    if (nodeCount >= maxObjects) return null;
    return _InMemoryHeapGraph(nodeCount);
  }
}

/// Minimal [HeapGraphView] with [nodeCount] sentinel nodes for testing.
final class _InMemoryHeapGraph implements HeapGraphView {
  const _InMemoryHeapGraph(this.nodeCount);

  @override
  final int nodeCount;

  @override
  int get rootId => 0;

  @override
  HeapNode node(int id) {
    if (id < 0 || id >= nodeCount) {
      throw StateError('id $id out of range [0, $nodeCount)');
    }
    return HeapNode(
      id: id,
      className: 'Sentinel',
      libraryUri: Uri.parse('dart:core'),
      shallowSize: 0,
      edges: const [],
    );
  }

  @override
  List<ClassCount> classHistogram() => [
    ClassCount(
      className: 'Sentinel',
      libraryUri: Uri.parse('dart:core'),
      instanceCount: nodeCount,
      shallowBytes: 0,
    ),
  ];
}
