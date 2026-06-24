import 'package:leak_graph/leak_graph.dart';

import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/retaining_path.dart';

/// Maps a [GraphLeakCluster] produced by the graph analyser into a
/// [LeakFinding] for consumption by the runtime UI and report layer.
LeakFinding mapGraphCluster(GraphLeakCluster c) => LeakFinding(
  className: c.className,
  kind: LeakKind.retainedByNonLiveRoot,
  severity: _severity(c),
  liveCount: c.instanceCount,
  growth: 0,
  library: c.libraryUri?.toString(),
  tag: c.rootKind.label,
  retainingPath: _mapPath(c.representativePath),
);

LeakSeverity _severity(GraphLeakCluster c) =>
    c.confidence == LeakConfidence.confirmed && c.instanceCount >= 2
    ? LeakSeverity.critical
    : LeakSeverity.warning;

RetainingPathView _mapPath(GraphRetainingPath path) => RetainingPathView(
  gcRootType: path.rootKind.label,
  elements: [
    for (final h in path.hops)
      RetainingHop(objectType: h.className, field: h.field, index: h.index),
  ],
);
