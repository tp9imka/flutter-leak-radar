/// BFS-based live Flutter UI-tree reachability pass.
///
/// Anchors the traversal at well-known Flutter binding class names so that
/// downstream passes can distinguish genuinely leaked objects from objects
/// that are still in use by the running UI tree.
library;

import '../graph/heap_graph_view.dart';

/// Default class names that serve as live-tree anchor points.
///
/// These are the root binding and element types that Flutter itself keeps
/// alive for the duration of the application. Any object reachable from one
/// of these nodes is considered part of the live UI tree.
const Set<String> kDefaultLiveAnchorClassNames = {
  'WidgetsFlutterBinding',
  'WidgetsBinding',
  'RenderView',
  '_ReusableRenderView',
  'RootWidget',
  'RootElement',
  'RenderObjectToWidgetElement',
};

/// Marks heap objects reachable from the live Flutter UI-tree anchor.
///
/// Call [LiveTreeReachability.compute] once per snapshot. The result is
/// immutable and cheap to query — pass it to leak-classification passes so
/// they can suppress in-use objects before reporting leaks.
final class LiveTreeReachability {
  final bool hasAnchor;
  final Set<int> _reachable;

  LiveTreeReachability._(this.hasAnchor, this._reachable);

  /// Computes reachability from all anchor nodes in [graph].
  ///
  /// Scans every node (ids `0..nodeCount-1`) for class names that appear in
  /// [anchorClassNames] (defaults to [kDefaultLiveAnchorClassNames]). If none
  /// are found, [hasAnchor] is `false` and [isReachable] always returns
  /// `false`. Otherwise performs an iterative BFS from every anchor.
  factory LiveTreeReachability.compute(
    HeapGraphView graph, {
    Set<String>? anchorClassNames,
  }) {
    final anchors = anchorClassNames ?? kDefaultLiveAnchorClassNames;

    final seeds = <int>[];
    for (var i = 0; i < graph.nodeCount; i++) {
      final n = graph.node(i);
      if (anchors.contains(n.className)) seeds.add(n.id);
    }

    if (seeds.isEmpty) {
      return LiveTreeReachability._(false, const {});
    }

    final reachable = <int>{};
    final queue = [...seeds];
    var head = 0;
    while (head < queue.length) {
      final id = queue[head++];
      if (!reachable.add(id)) continue;
      for (final edge in graph.node(id).edges) {
        if (!reachable.contains(edge.targetId)) {
          queue.add(edge.targetId);
        }
      }
    }

    return LiveTreeReachability._(true, reachable);
  }

  /// Returns `true` if [nodeId] is reachable from any live-tree anchor.
  bool isReachable(int nodeId) => _reachable.contains(nodeId);
}
