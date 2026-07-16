import '../graph/heap_graph_view.dart';
import '../model/class_path_distribution.dart';
import '../model/class_root_profile.dart';
import '../model/graph_analysis_result.dart';
import '../model/graph_retaining_path.dart';
import '../model/package_rollup.dart';
import '../model/root_kind.dart';
import 'app_package_set.dart';
import 'class_origin.dart';
import 'clustering.dart';
import 'live_tree.dart';
import 'shortest_retaining_paths.dart';

/// Package key used when a library URI resolves to no package (malformed or
/// non-`package:`/`dart:` URI).
const String _unknownPackage = '(unknown)';

/// Pairs each retaining-path [links] entry with its class name from
/// [classNames] and, when supplied, its library uri from [libraryUris] by
/// POSITION.
///
/// [classNames] (and optional [libraryUris]) are parallel to [links] (same
/// order, same length). Positional pairing is required because two hops can be
/// value-equal (repeated container or array-index slots); a value-based lookup
/// would alias them to the first match and corrupt the path and its cluster
/// signature. A shorter or absent [libraryUris] leaves later hops with a null
/// [GraphHop.libraryUri].
List<GraphHop> buildHops(
  List<PathLink> links,
  List<String> classNames, [
  List<Uri>? libraryUris,
]) {
  return [
    for (final entry in links.asMap().entries)
      GraphHop(
        className: entry.key < classNames.length ? classNames[entry.key] : '',
        field: entry.value.field,
        index: entry.value.index,
        libraryUri: libraryUris != null && entry.key < libraryUris.length
            ? libraryUris[entry.key]
            : null,
      ),
  ];
}

/// Finds the shortest retaining path to the first reachable instance of
/// [className] in [graph], or null when no reachable instance exists.
///
/// Standalone (no VM service): lets a growth/precise leak finding show its
/// retaining path on a physical device straight from a heap snapshot, instead
/// of a `getRetainingPath` VM call. Runs a single BFS over the graph.
GraphRetainingPath? retainingPathForClass(
  HeapGraphView graph,
  String className,
) {
  final paths = ShortestRetainingPaths.compute(graph);
  for (var id = 0; id < graph.nodeCount; id++) {
    if (id == graph.rootId) continue;
    HeapNode node;
    try {
      node = graph.node(id);
    } catch (_) {
      continue;
    }
    if (node.className != className) continue;
    if (!paths.isReachable(id)) continue;
    final links = paths.pathTo(id);
    if (links == null || links.isEmpty) continue;
    final classNames = links.map((l) {
      try {
        return graph.node(l.nodeId).className;
      } catch (_) {
        return '';
      }
    }).toList();
    final libraryUris = links.map((l) {
      try {
        return graph.node(l.nodeId).libraryUri;
      } catch (_) {
        return Uri();
      }
    }).toList();
    return GraphRetainingPath(
      hops: buildHops(links, classNames, libraryUris),
      rootKind: paths.rootKindOf(id),
    );
  }
  return null;
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

      final hops = buildHops(pathLinks, pathClassNames, pathLibraries);
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
          anchorHopIndex: anchorIndex,
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

    final classRootProfiles = buildClassRootProfiles(
      graph,
      paths,
      liveAnchorClassNames: options.liveAnchorClassNames,
    );

    final classPathDistributions = buildClassPathDistributions(
      graph,
      paths,
      maxSignatureDepth: options.maxSignatureDepth,
    );

    // Rollups summarize the REPORTED clusters, re-keyed by package: only
    // survivor records whose signature produced an emitted cluster count, so
    // the per-package instance/byte/cluster totals stay consistent with what
    // the run actually reports.
    final classifier = OriginClassifier(
      projectPackages: appSet?.names ?? const {},
    );
    final emittedSignatures = {for (final c in clusters) c.signature};
    final rollupRecords = [
      for (final r in survivors)
        if (emittedSignatures.contains(r.signature)) r,
    ];
    final anchorRollups = _buildRollups(
      rollupRecords,
      classifier,
      (r) => r.attributionLibraryUri ?? r.libraryUri,
    );
    final declaredRollups = _buildRollups(
      rollupRecords,
      classifier,
      (r) => r.libraryUri,
    );

    // Disabled filtering takes precedence: when no package is treated as
    // project-owned, an explicit list did not actually drive filtering, so it
    // would be dishonest to report explicitConfig.
    final appPackageSource = options.disableAppFilter
        ? AppPackageSource.disabled
        : (options.appPackages.isNotEmpty
              ? AppPackageSource.explicitConfig
              : AppPackageSource.autoDetected);

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
      classRootProfiles: classRootProfiles,
      classPathDistributions: classPathDistributions,
      anchorRollups: anchorRollups,
      declaredRollups: declaredRollups,
      appPackageSource: appPackageSource,
    );
  }
}

/// Aggregates [records] into one [PackageRollup] per package, keyed by
/// `packageOf(keyUri(record))` (null → [_unknownPackage]).
///
/// The same leaked set produces the anchor vs declared rollups; only [keyUri]
/// differs (the retaining anchor library vs the record's declaring library).
/// Sorted by shallow bytes then instances descending, package name ascending,
/// for stable output.
List<PackageRollup> _buildRollups(
  List<LeakRecord> records,
  OriginClassifier classifier,
  Uri Function(LeakRecord) keyUri,
) {
  final classNames = <String, Set<String>>{};
  final signatures = <String, Set<String>>{};
  final instances = <String, int>{};
  final bytes = <String, int>{};
  final origins = <String, ClassOrigin>{};

  for (final record in records) {
    final uri = keyUri(record);
    final package = classifier.packageOf(uri) ?? _unknownPackage;
    origins.putIfAbsent(package, () => classifier.classify(uri));
    (classNames[package] ??= <String>{}).add(record.className);
    (signatures[package] ??= <String>{}).add(record.signature);
    instances[package] = (instances[package] ?? 0) + 1;
    bytes[package] = (bytes[package] ?? 0) + record.shallowSize;
  }

  final rollups = [
    for (final package in instances.keys)
      PackageRollup(
        package: package,
        origin: origins[package]!,
        classCount: classNames[package]!.length,
        instanceCount: instances[package]!,
        shallowBytes: bytes[package]!,
        clusterCount: signatures[package]!.length,
      ),
  ];
  rollups.sort((a, b) {
    final byBytes = b.shallowBytes.compareTo(a.shallowBytes);
    if (byBytes != 0) return byBytes;
    final byInstances = b.instanceCount.compareTo(a.instanceCount);
    if (byInstances != 0) return byInstances;
    return a.package.compareTo(b.package);
  });
  return rollups;
}

/// Default cap on how many classes get a materialized
/// [ClassRootProfile.representativePath].
///
/// [buildClassRootProfiles] aggregates EVERY reachable object in a single
/// pass (cheap: O(reachableObjects)), but reconstructing a retaining path is
/// an O(pathLength) walk-back per class, so it is only done for a bounded
/// subset: the [kMaxClassRootProfilePaths] classes with the most instances,
/// UNION every class that has at least one instance rooted by a leak-prone
/// [RootKind] (see [RootKind.isLeakProne]). Leak-prone roots are rare in a
/// typical heap — the existing leak-candidate pass above already
/// reconstructs a path for every SUCH INSTANCE (not merely per class) — so
/// unioning in "one path per leak-prone class" adds strictly less work than
/// the clustering pass already does. This keeps large heaps with many
/// thousands of distinct classes from blowing up while still surfacing a
/// path for anything that could plausibly be a leak.
const int kMaxClassRootProfilePaths = 250;

/// Builds a [ClassRootProfile] for every class reachable from
/// [graph.rootId], reusing the already-computed [paths] instead of running a
/// second BFS.
///
/// Unlike the leak-candidate pass in [GraphLeakAnalyzer.analyze], this does
/// NOT filter by [RootKind.isLeakProne] — every reachable class is included,
/// so a caller can tell live-tree-retained classes apart from leak-prone
/// ones instead of only ever seeing leak candidates.
List<ClassRootProfile> buildClassRootProfiles(
  HeapGraphView graph,
  ShortestRetainingPaths paths, {
  Set<String>? liveAnchorClassNames,
}) {
  final liveTree = LiveTreeReachability.compute(
    graph,
    anchorClassNames: liveAnchorClassNames,
  );

  final totalInstances = <String, int>{};
  final shallowBytes = <String, int>{};
  final libraryUris = <String, Uri?>{};
  final byRoot = <String, Map<RootKind, int>>{};
  final representativeNodeId = <String, int>{};
  final hasLeakProneInstance = <String>{};

  for (var id = 0; id < graph.nodeCount; id++) {
    if (id == graph.rootId) continue;
    if (!paths.isReachable(id)) continue;

    HeapNode node;
    try {
      node = graph.node(id);
    } catch (_) {
      continue;
    }

    // A leak-prone root always wins; only a non-leak-prone root (e.g. a
    // dangling/unclassified `other`) can be promoted to `liveTree` when the
    // live UI tree can also reach it. Mirrors the precedence already used to
    // decide `suppressedByLiveTree` above: the live tree never overrides a
    // genuinely leak-prone retainer.
    var rootKind = paths.rootKindOf(id);
    if (!rootKind.isLeakProne &&
        liveTree.hasAnchor &&
        liveTree.isReachable(id)) {
      rootKind = RootKind.liveTree;
    }

    final className = node.className;
    totalInstances[className] = (totalInstances[className] ?? 0) + 1;
    shallowBytes[className] = (shallowBytes[className] ?? 0) + node.shallowSize;
    libraryUris.putIfAbsent(className, () => node.libraryUri);

    final classByRoot = byRoot.putIfAbsent(className, () => {});
    classByRoot[rootKind] = (classByRoot[rootKind] ?? 0) + 1;

    if (rootKind.isLeakProne) {
      // First leak-prone instance always becomes (or replaces) the
      // representative: it is strictly more useful for leak-hunting than an
      // arbitrary live-tree instance of the same class.
      if (hasLeakProneInstance.add(className)) {
        representativeNodeId[className] = id;
      }
    } else {
      representativeNodeId.putIfAbsent(className, () => id);
    }
  }

  final classNames = totalInstances.keys.toList()
    ..sort((a, b) => totalInstances[b]!.compareTo(totalInstances[a]!));

  final pathTargets = <String>{
    ...classNames.take(kMaxClassRootProfilePaths),
    ...hasLeakProneInstance,
  };

  final profiles = <ClassRootProfile>[
    for (final className in classNames)
      ClassRootProfile(
        className: className,
        libraryUri: libraryUris[className],
        totalInstances: totalInstances[className]!,
        retainedShallowBytes: shallowBytes[className]!,
        byRoot: Map.unmodifiable(byRoot[className]!),
        representativePath: pathTargets.contains(className)
            ? _representativePath(
                graph,
                paths,
                representativeNodeId[className]!,
              )
            : null,
      ),
  ];

  profiles.sort((a, b) {
    final byBytes = b.retainedShallowBytes.compareTo(a.retainedShallowBytes);
    if (byBytes != 0) return byBytes;
    return b.totalInstances.compareTo(a.totalInstances);
  });

  return profiles;
}

GraphRetainingPath _representativePath(
  HeapGraphView graph,
  ShortestRetainingPaths paths,
  int nodeId,
) {
  final links = paths.pathTo(nodeId) ?? const <PathLink>[];
  final classNames = links.map((l) {
    try {
      return graph.node(l.nodeId).className;
    } catch (_) {
      return '';
    }
  }).toList();
  final libraryUris = links.map((l) {
    try {
      return graph.node(l.nodeId).libraryUri;
    } catch (_) {
      return Uri();
    }
  }).toList();
  return GraphRetainingPath(
    hops: buildHops(links, classNames, libraryUris),
    rootKind: paths.rootKindOf(nodeId),
  );
}

/// Upper bound on how many of a class's instances are walked when building its
/// [ClassPathDistribution]. Path reconstruction is O(pathLength) per instance,
/// so a huge class (e.g. `String`) is sampled rather than fully walked; the
/// result records [ClassPathDistribution.sampledInstances] so the UI can flag a
/// partial breakdown instead of presenting it as complete.
const int kMaxInstancesPerPathDistribution = 2000;

/// Upper bound on how many distinct path buckets are retained per class; the
/// rest roll up into [ClassPathDistribution.otherPathCount].
const int kMaxPathBucketsPerClass = 25;

/// Builds, for a bounded set of classes, the distribution of their reachable
/// instances across distinct shortest retaining paths — grouping instances by
/// [pathSignature] so paths differing only beyond the signature depth (or in
/// array indices) share a bucket.
///
/// The target set mirrors [buildClassRootProfiles]' materialized-path set: the
/// [kMaxClassRootProfilePaths] classes with the most instances, UNION every
/// class with at least one leak-prone-rooted instance. Per class, at most
/// [perClassInstanceCap] instances are walked; classes exceeding it are
/// reported as sampled.
List<ClassPathDistribution> buildClassPathDistributions(
  HeapGraphView graph,
  ShortestRetainingPaths paths, {
  int maxSignatureDepth = 12,
  int perClassInstanceCap = kMaxInstancesPerPathDistribution,
  int maxBucketsPerClass = kMaxPathBucketsPerClass,
}) {
  // Pass 1: instance counts + leak-prone classes, to pick target classes.
  final totalInstances = <String, int>{};
  final leakProneClasses = <String>{};
  for (var id = 0; id < graph.nodeCount; id++) {
    if (id == graph.rootId) continue;
    if (!paths.isReachable(id)) continue;
    String className;
    try {
      className = graph.node(id).className;
    } catch (_) {
      continue;
    }
    totalInstances[className] = (totalInstances[className] ?? 0) + 1;
    if (paths.rootKindOf(id).isLeakProne) leakProneClasses.add(className);
  }
  if (totalInstances.isEmpty) return const [];

  final ranked = totalInstances.keys.toList()
    ..sort((a, b) => totalInstances[b]!.compareTo(totalInstances[a]!));
  final targets = <String>{
    ...ranked.take(kMaxClassRootProfilePaths),
    ...leakProneClasses,
  };

  // Pass 2: bucket target-class instances by path signature (capped per class).
  final acc = <String, Map<String, _PathBucketAcc>>{};
  final sampled = <String, int>{};
  for (var id = 0; id < graph.nodeCount; id++) {
    if (id == graph.rootId) continue;
    if (!paths.isReachable(id)) continue;

    HeapNode node;
    try {
      node = graph.node(id);
    } catch (_) {
      continue;
    }
    final className = node.className;
    if (!targets.contains(className)) continue;
    if ((sampled[className] ?? 0) >= perClassInstanceCap) continue;

    final links = paths.pathTo(id);
    if (links == null || links.isEmpty) continue;
    final classNames = links.map((l) {
      try {
        return graph.node(l.nodeId).className;
      } catch (_) {
        return '';
      }
    }).toList();
    final libraryUris = links.map((l) {
      try {
        return graph.node(l.nodeId).libraryUri;
      } catch (_) {
        return Uri();
      }
    }).toList();
    final hops = buildHops(links, classNames, libraryUris);
    final signature = pathSignature(hops, maxDepth: maxSignatureDepth);

    final bySig = acc.putIfAbsent(className, () => {});
    final bucket = bySig.putIfAbsent(
      signature,
      () => _PathBucketAcc(
        GraphRetainingPath(hops: hops, rootKind: paths.rootKindOf(id)),
      ),
    );
    bucket.instanceCount++;
    bucket.shallowBytes += node.shallowSize;
    sampled[className] = (sampled[className] ?? 0) + 1;
  }

  final result = <ClassPathDistribution>[];
  for (final className in acc.keys) {
    final buckets = acc[className]!.values.toList()
      ..sort((a, b) {
        final byCount = b.instanceCount.compareTo(a.instanceCount);
        if (byCount != 0) return byCount;
        return b.shallowBytes.compareTo(a.shallowBytes);
      });
    final top = buckets.take(maxBucketsPerClass);
    final otherPathCount = buckets
        .skip(maxBucketsPerClass)
        .fold(0, (sum, b) => sum + b.instanceCount);
    result.add(
      ClassPathDistribution(
        className: className,
        totalInstances: totalInstances[className]!,
        sampledInstances: sampled[className] ?? 0,
        paths: [
          for (final b in top)
            PathBucket(
              path: b.path,
              instanceCount: b.instanceCount,
              shallowBytes: b.shallowBytes,
            ),
        ],
        otherPathCount: otherPathCount,
      ),
    );
  }

  result.sort((a, b) => b.totalInstances.compareTo(a.totalInstances));
  return result;
}

class _PathBucketAcc {
  _PathBucketAcc(this.path);
  final GraphRetainingPath path;
  int instanceCount = 0;
  int shallowBytes = 0;
}
