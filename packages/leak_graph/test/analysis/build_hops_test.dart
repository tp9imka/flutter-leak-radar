import 'package:leak_graph/src/analysis/graph_leak_analyzer.dart';
import 'package:leak_graph/src/analysis/shortest_retaining_paths.dart';
import 'package:test/test.dart';

void main() {
  group('buildHops', () {
    test('pairs class names positionally with value-equal hops', () {
      // Two value-equal array-index hops (same nodeId/field/index) — common for
      // repeated container/array slots. The same PathLink instance appears twice
      // to model identical hops. With indexOf both would alias to the first
      // class name, corrupting the path.
      const repeated = PathLink(nodeId: 2, index: 0);
      final links = <PathLink>[
        repeated,
        repeated,
        const PathLink(nodeId: 3, field: '_callback'),
      ];
      final classNames = <String>['List', 'Map', 'HomeState'];

      final hops = buildHops(links, classNames);

      expect(
        hops.map((h) => h.className).toList(),
        ['List', 'Map', 'HomeState'],
        reason: 'each hop must take the class name at its own position',
      );
      expect(hops[1].index, 0);
      expect(hops[2].field, '_callback');
    });

    test('preserves order for all-distinct hops', () {
      final links = <PathLink>[
        const PathLink(nodeId: 1),
        const PathLink(nodeId: 2, field: '_list'),
        const PathLink(nodeId: 3, index: 0),
      ];
      final classNames = <String>['_Timer', 'List', 'HomeState'];

      final hops = buildHops(links, classNames);

      expect(hops.map((h) => h.className).toList(), classNames);
    });
  });
}
