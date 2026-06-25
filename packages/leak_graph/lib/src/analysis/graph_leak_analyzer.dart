import '../graph/heap_graph_view.dart';
import '../model/graph_analysis_result.dart';
import '../model/graph_retaining_path.dart';
import '../model/root_kind.dart';
import 'app_package_set.dart';
import 'clustering.dart';
import 'live_tree.dart';
import 'shortest_retaining_paths.dart';

/// Pairs each retaining-path [links] entry with its class name from
/// [classNames] by POSITION.
///
/// [classNames] is parallel to [links] (same order, same length). Positional
/// pairing is required because two hops can be value-equal (repeated container
/// or array-index slots); a value-based lookup would alias them to the first
/// match and corrupt the path and its cluster signature.
List<GraphHop> buildHops(List<PathLink> links, List<String> classNames) {
  return [
    for (final entry in links.asMap().entries)
      GraphHop(
        className: entry.key < classNames.length ? classNames[entry.key] : '',
        field: entry.value.field,
        index: entry.value.index,
      ),
  ];
}

/// Configuration for a single [GraphLeakAnalyzer.analyze] run.
final class GraphAnalysisOptions {
  /// Explicit package names that belong to the app under analysis.
  ///
  /// When empty, [AppPackageSet.autoDetect] derives the set from the graph's
  /// library URIs, excluding SDK and framework packages.
  final List<String> appPackages;

  /// When true, every leak candidate passes regardless of its library.
  final bool disableAppFilter;

  /// Minimum number of instances required to form a cluster.
  final int minClusterSize;

  /// Maximum number of path hops included in a signature.
  final int maxSignatureDepth;

  /// When true, runs [LiveTreeReachability] after candidate collection.
  ///
  /// If a live-tree anchor is found, candidates reachable from it are
  /// suppressed and survivors are clustered with [LeakConfidence.confirmed].
  /// If no anchor is found, falls back to [LeakConfidence.heuristic] with no
  /// suppression. When false (default), Phase 1 behaviour is unchanged.
  final bool confirmWithReachability;

  /// Class names used as live-tree anchors when [confirmWithReachability] is
  /// true. Defaults to [kDefaultLiveAnchorClassNames] when null.
  final Set<String>? liveAnchorClassNames;

  const GraphAnalysisOptions({
    this.appPackages = const [],
    this.disableAppFilter = false,
    this.minClusterSize = 2,
    this.maxSignatureDepth = 12,
    this.confirmWithReachability = false,
    this.liveAnchorClassNames,
  });
}

/// End-to-end heap leak analysis pipeline.
///
/// Wires together BFS shortest paths, root classification, app-relevance
/// filtering, and clustering to produce a [GraphAnalysisResult].
final class GraphLeakAnalyzer {
  const GraphLeakAnalyzer();

  /// Analyzes [graph] and returns detected leak clusters with run statistics.
  ///
  /// Never throws on a malformed graph; instead appends diagnostics to
  /// [GraphAnalysisStats.warnings] and returns partial results.
  GraphAnalysisResult analyze(
    HeapGraphView graph, [
    GraphAnalysisOptions options = const GraphAnalysisOptions(),
  ]) {
    final warnings = <String>[];
    final paths = ShortestRetainingPaths.compute(graph);

    final allLibraryUris = <Uri>[];
    for (var id = 0; id < graph.nodeCount; id++) {
      try {
        allLibraryUris.add(graph.node(id).libraryUri);
      } catch (_) {
        warnings.add('Node id $id missing from graph; skipped.');
      }
    }

    final appSet = options.disableAppFilter
        ? null
        : (options.appPackages.isEmpty
              ? AppPackageSet.autoDetect(allLibraryUris)
              : AppPackageSet.from(options.appPackages));

    var reachableObjects = 0;
    final leakRecords = <LeakRecord>[];

    for (var id = 0; id < graph.nodeCount; id++) {
      if (id == graph.rootId) continue;

      HeapNode node;
      try {
        node = graph.node(id);
      } catch (_) {
        warnings.add('Node id $id missing; skipped.');
        continue;
      }

      if (!paths.isReachable(id)) continue;
      reachableObjects++;

      // O(1) root classification (propagated during BFS). Skip the ~99% of
      // reachable nodes that are not leak candidates BEFORE reconstructing any
      // retaining path — the expensive path materialisation below runs only for
      // the few thousand actual candidates, not all reachable objects.
      final rootKind = paths.rootKindOf(id);
      if (!rootKind.isLeakProne) continue;

      final pathLinks = paths.pathTo(id);
      if (pathLinks == null || pathLinks.isEmpty) continue;

      final pathClassNames = pathLinks.map((l) {
        try {
          return graph.node(l.nodeId).className;
        } catch (_) {
          warnings.add('PathLink node ${l.nodeId} missing; using empty name.');
          return '';
        }
      }).toList();

      final pathLibraries = pathLinks.map((l) {
        try {
          return graph.node(l.nodeId).libraryUri;
        } catch (_) {
          return Uri();
        }
      }).toList();

      // Attribution: the DEEPEST app-owned object on the path is the leaked
      // "owner" this finding is reported under; the internal SDK leaf below it
      // (e.g. a _ControllerSubscription/_Closure) is demoted to retaining-path
      // detail. Walk leaf->root; the first app hop is the anchor.
      int? anchorIndex;
      if (appSet != null) {
        for (var i = pathLibraries.length - 1; i >= 0; i--) {
          if (appSet.contains(pathLibraries[i])) {
            anchorIndex = i;
            break;
          }
        }
      }

      final hops = buildHops(pathLinks, pathClassNames);
      final path = GraphRetainingPath(hops: hops, rootKind: rootKind);
      // Signature anchored at the owner (root -> anchor) so two owners with the
      // same owner+root path cluster regardless of which internal leaf BFS
      // reached first. Falls back to the full path when there is no anchor.
      final signature = pathSignature(
        anchorIndex != null ? hops.sublist(0, anchorIndex + 1) : hops,
        maxDepth: options.maxSignatureDepth,
      );

      leakRecords.add(
        LeakRecord(
          nodeId: id,
          className: node.className,
          libraryUri: node.libraryUri,
          shallowSize: node.shallowSize,
          path: path,
          pathLibraries: pathLibraries,
          rootKind: rootKind,
          signature: signature,
          attributionAnchorNodeId: anchorIndex != null
              ? pathLinks[anchorIndex].nodeId
              : null,
          attributionClassName: anchorIndex != null
              ? pathClassNames[anchorIndex]
              : null,
          attributionLibraryUri: anchorIndex != null
              ? pathLibraries[anchorIndex]
              : null,
        ),
      );
    }

    final leakCandidates = leakRecords.length;

    final kept = <LeakRecord>[];
    var suppressedByAppFilter = 0;

    for (final record in leakRecords) {
      if (appSet == null) {
        kept.add(record);
        continue;
      }
      // Keep a record iff it has an app owner on its path (attribution anchor)
      // OR its own leaf class is app code. The old bare `pathLibraries.any`
      // rule let pure-SDK leaves survive under their SDK names just because an
      // app object sat somewhere on their path; attribution now folds those
      // into the app owner instead.
      final inApp =
          record.attributionAnchorNodeId != null ||
          appSet.contains(record.libraryUri);
      if (inApp) {
        kept.add(record);
      } else {
        suppressedByAppFilter++;
      }
    }

    var suppressedByLiveTree = 0;
    List<LeakRecord> survivors;
    LeakConfidence clusterConfidence;

    if (options.confirmWithReachability) {
      final liveTree = LiveTreeReachability.compute(
        graph,
        anchorClassNames: options.liveAnchorClassNames,
      );
      if (liveTree.hasAnchor) {
        survivors = <LeakRecord>[];
        for (final record in kept) {
          // A leak-prone-rooted candidate is never suppressed by mere forward-
          // reachability from a live anchor: the anchor reaching it via a stale
          // debug / inactive-element back-reference is NOT retention-for-use —
          // its real keep-alive owner is the leak-prone root. Suppress only a
          // candidate whose root is not leak-prone (a safety net, given the
          // isLeakProne gate above), which is what stopped the real leak from
          // being wrongly hidden.
          if (liveTree.isReachable(record.nodeId) &&
              !record.rootKind.isLeakProne) {
            suppressedByLiveTree++;
          } else {
            survivors.add(record);
          }
        }
        clusterConfidence = LeakConfidence.confirmed;
      } else {
        survivors = kept;
        clusterConfidence = LeakConfidence.heuristic;
      }
    } else {
      survivors = kept;
      clusterConfidence = LeakConfidence.heuristic;
    }

    final clusters = clusterLeaks(
      survivors,
      minClusterSize: options.minClusterSize,
      confidence: clusterConfidence,
    );

    return GraphAnalysisResult(
      clusters: clusters,
      stats: GraphAnalysisStats(
        totalObjects: graph.nodeCount,
        reachableObjects: reachableObjects,
        leakCandidates: leakCandidates,
        clusters: clusters.length,
        suppressedByAppFilter: suppressedByAppFilter,
        suppressedByLiveTree: suppressedByLiveTree,
        warnings: warnings,
      ),
    );
  }
}
