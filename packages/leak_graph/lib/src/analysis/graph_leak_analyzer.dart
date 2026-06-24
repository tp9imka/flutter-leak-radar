import '../graph/heap_graph_view.dart';
import '../model/graph_analysis_result.dart';
import '../model/graph_retaining_path.dart';
import 'app_package_set.dart';
import 'clustering.dart';
import 'root_classifier.dart';
import 'shortest_retaining_paths.dart';

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

  const GraphAnalysisOptions({
    this.appPackages = const [],
    this.disableAppFilter = false,
    this.minClusterSize = 2,
    this.maxSignatureDepth = 12,
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

      final rootKind = classifyRoot(pathClassNames);
      if (!rootKind.isLeakProne) continue;

      final pathLibraries = pathLinks.map((l) {
        try {
          return graph.node(l.nodeId).libraryUri;
        } catch (_) {
          return Uri();
        }
      }).toList();

      final hops = pathLinks.map((l) {
        final className = pathClassNames[pathLinks.indexOf(l)];
        return GraphHop(className: className, field: l.field, index: l.index);
      }).toList();

      final path = GraphRetainingPath(hops: hops, rootKind: rootKind);
      final signature =
          pathSignature(hops, maxDepth: options.maxSignatureDepth);

      leakRecords.add(LeakRecord(
        className: node.className,
        libraryUri: node.libraryUri,
        shallowSize: node.shallowSize,
        path: path,
        pathLibraries: pathLibraries,
        rootKind: rootKind,
        signature: signature,
      ));
    }

    final leakCandidates = leakRecords.length;

    final kept = <LeakRecord>[];
    var suppressedByAppFilter = 0;

    for (final record in leakRecords) {
      if (appSet == null) {
        kept.add(record);
        continue;
      }
      final inApp = appSet.contains(record.libraryUri) ||
          record.pathLibraries.any(appSet.contains);
      if (inApp) {
        kept.add(record);
      } else {
        suppressedByAppFilter++;
      }
    }

    final clusters =
        clusterLeaks(kept, minClusterSize: options.minClusterSize);

    return GraphAnalysisResult(
      clusters: clusters,
      stats: GraphAnalysisStats(
        totalObjects: graph.nodeCount,
        reachableObjects: reachableObjects,
        leakCandidates: leakCandidates,
        clusters: clusters.length,
        suppressedByAppFilter: suppressedByAppFilter,
        warnings: warnings,
      ),
    );
  }
}
