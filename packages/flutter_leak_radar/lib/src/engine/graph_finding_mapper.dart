import 'package:leak_graph/leak_graph.dart';

import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/retaining_path.dart';

/// Maps a [GraphLeakCluster] produced by the graph analyser into a
/// [LeakFinding] for consumption by the runtime UI and report layer.
///
/// [classifier] resolves the finding's [LeakFinding.origin]; when omitted, the
/// library classifies against an empty project set (project vs dependency is
/// then indistinguishable, so app-owned classes read as `dependency`).
LeakFinding mapGraphCluster(
  GraphLeakCluster c, {
  OriginClassifier? classifier,
}) {
  final origin = c.libraryUri == null
      ? ClassOrigin.unknown
      : (classifier ?? const OriginClassifier(projectPackages: <String>{}))
            .classify(c.libraryUri!);
  return LeakFinding(
    className: c.className,
    kind: LeakKind.retainedByNonLiveRoot,
    severity: _severity(c),
    liveCount: c.instanceCount,
    growth: 0,
    library: c.libraryUri?.toString(),
    tag: c.rootKind.label,
    origin: origin,
    bytes: c.retainedShallowBytes > 0 ? c.retainedShallowBytes : null,
    retainingPath: mapGraphPath(c.representativePath),
  );
}

LeakSeverity _severity(GraphLeakCluster c) =>
    c.confidence == LeakConfidence.confirmed && c.instanceCount >= 2
    ? LeakSeverity.critical
    : LeakSeverity.warning;

/// Maps a leak_graph [GraphRetainingPath] to the runtime UI's
/// [RetainingPathView]. Shared by graph-cluster findings and the standalone
/// (snapshot-based) retaining-path lookup.
RetainingPathView mapGraphPath(GraphRetainingPath path) => RetainingPathView(
  gcRootType: path.rootKind.label,
  elements: [
    for (final h in path.hops)
      RetainingHop(objectType: h.className, field: h.field, index: h.index),
  ],
);
