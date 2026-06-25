import '../model/graph_leak_cluster.dart';
import '../model/graph_retaining_path.dart';
import '../model/root_kind.dart';

/// A single heap instance suspected of being leaked.
final class LeakRecord {
  final int nodeId;
  final String className;
  final Uri libraryUri;
  final int shallowSize;
  final GraphRetainingPath path;
  final List<Uri> pathLibraries;
  final RootKind rootKind;
  final String signature;

  /// The deepest app-owned object on this record's retaining path — the leaked
  /// "owner" an internal SDK leaf is attributed to (e.g. a `_LeakyScreenState`
  /// that transitively retains a `_ControllerSubscription`). Null when no app
  /// object is on the path or the app filter is disabled. When set, clustering
  /// headlines and dedupes by this owner instead of the internal-leaf [nodeId].
  final int? attributionAnchorNodeId;
  final String? attributionClassName;
  final Uri? attributionLibraryUri;

  const LeakRecord({
    required this.nodeId,
    required this.className,
    required this.libraryUri,
    required this.shallowSize,
    required this.path,
    required this.pathLibraries,
    required this.rootKind,
    required this.signature,
    this.attributionAnchorNodeId,
    this.attributionClassName,
    this.attributionLibraryUri,
  });
}

/// Converts a list of hops into a stable string signature.
///
/// Takes the last [maxDepth] hops and joins them as `Class[.field]`,
/// collapsing numeric array indices to `[]`.
String pathSignature(List<GraphHop> hops, {int maxDepth = 12}) {
  final tail = hops.length > maxDepth
      ? hops.sublist(hops.length - maxDepth)
      : hops;
  final parts = tail.map((h) {
    if (h.index != null) return '${h.className}[]';
    if (h.field != null) return '${h.className}.${h.field}';
    return h.className;
  });
  return parts.join('>');
}

/// Groups [leaks] by signature and returns one [GraphLeakCluster] per group.
///
/// Groups smaller than [minClusterSize] are dropped. Results are ranked by
/// [GraphLeakCluster.instanceCount] descending, then
/// [GraphLeakCluster.retainedShallowBytes] descending.
List<GraphLeakCluster> clusterLeaks(
  List<LeakRecord> leaks, {
  int minClusterSize = 2,
  LeakConfidence confidence = LeakConfidence.heuristic,
}) {
  final groups = <String, List<LeakRecord>>{};
  for (final r in leaks) {
    (groups[r.signature] ??= []).add(r);
  }

  final clusters = <GraphLeakCluster>[];
  for (final entry in groups.entries) {
    final group = entry.value;
    // Count DISTINCT leaked owners (attribution anchor), so several internal
    // leaves retained by one app object fold into a single instance instead of
    // inflating the count. Falls back to the record's own node when there is no
    // anchor (Phase-1 / app-filter-disabled behaviour).
    final ownerIds = <int>{
      for (final r in group) r.attributionAnchorNodeId ?? r.nodeId,
    };
    if (ownerIds.length < minClusterSize) continue;
    final first = group.first;
    final totalBytes = group.fold(0, (sum, r) => sum + r.shallowSize);
    clusters.add(
      GraphLeakCluster(
        // Headline the leaked app owner, not the internal leaf.
        className: first.attributionClassName ?? first.className,
        libraryUri: first.attributionLibraryUri ?? first.libraryUri,
        instanceCount: ownerIds.length,
        retainedShallowBytes: totalBytes,
        representativePath: first.path,
        rootKind: first.rootKind,
        confidence: confidence,
        signature: entry.key,
      ),
    );
  }

  clusters.sort((a, b) {
    final byCount = b.instanceCount.compareTo(a.instanceCount);
    if (byCount != 0) return byCount;
    return b.retainedShallowBytes.compareTo(a.retainedShallowBytes);
  });

  return clusters;
}
