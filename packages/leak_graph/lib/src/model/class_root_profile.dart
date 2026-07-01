import 'graph_retaining_path.dart';
import 'root_kind.dart';

/// Per-class breakdown of which [RootKind] retains each instance.
///
/// Unlike [GraphLeakCluster] (which only ever reports leak-prone-rooted
/// classes), a [ClassRootProfile] exists for EVERY class reachable from the
/// GC root — including classes that are entirely retained by the live
/// Flutter UI tree. That is the point of this model: it lets a UI render a
/// full "who retains what" breakdown and visually separate live objects from
/// leaked ones, instead of only ever seeing the leak candidates.
final class ClassRootProfile {
  final String className;

  /// Library that declared [className], e.g. `package:app/src/foo.dart`.
  ///
  /// Null only when no reachable instance's library could be resolved.
  final Uri? libraryUri;

  /// Number of reachable instances of [className] across the whole graph.
  final int totalInstances;

  /// Summed SHALLOW (own) bytes across every reachable instance of
  /// [className].
  ///
  /// This is NOT a true retained-graph size (that would require a
  /// dominator-tree pass, which this library does not compute). It is named
  /// to match [GraphLeakCluster.retainedShallowBytes], which uses the same
  /// best-effort "sum of shallow sizes" definition — kept honest here rather
  /// than fabricating a number this library cannot cheaply back up.
  final int retainedShallowBytes;

  /// Count of [className] instances whose CLOSEST retaining root classifies
  /// as each [RootKind]. Values sum to [totalInstances].
  final Map<RootKind, int> byRoot;

  /// Shortest retaining path for one representative instance of
  /// [className].
  ///
  /// Null when this class fell outside the bounded set of classes for which
  /// `GraphLeakAnalyzer.analyze` materializes a path (see
  /// `kMaxClassRootProfilePaths`) — reconstructing a path for every distinct
  /// class in a large heap is unnecessary work the UI does not need for
  /// every row.
  final GraphRetainingPath? representativePath;

  const ClassRootProfile({
    required this.className,
    required this.libraryUri,
    required this.totalInstances,
    required this.retainedShallowBytes,
    required this.byRoot,
    this.representativePath,
  });

  /// Heuristic: true when a strict majority of [className]'s instances are
  /// retained through the live Flutter UI tree ([RootKind.liveTree]) rather
  /// than a leak-prone root.
  ///
  /// A single class can straddle both cases (e.g. some instances disposed
  /// but still timer-retained) — this only reports which case dominates by
  /// instance count, it does not mean every instance is safe.
  bool get looksLive {
    if (totalInstances == 0) return false;
    final liveCount = byRoot[RootKind.liveTree] ?? 0;
    return liveCount * 2 > totalInstances;
  }

  factory ClassRootProfile.fromJson(Map<String, Object?> json) {
    final rawByRoot = (json['byRoot'] as Map).cast<String, Object?>();
    final rawPath = json['representativePath'];
    return ClassRootProfile(
      className: json['className'] as String,
      libraryUri: json['libraryUri'] == null
          ? null
          : Uri.parse(json['libraryUri'] as String),
      totalInstances: json['totalInstances'] as int,
      retainedShallowBytes: json['retainedShallowBytes'] as int,
      byRoot: {
        for (final entry in rawByRoot.entries)
          RootKind.values.byName(entry.key): entry.value as int,
      },
      representativePath: rawPath == null
          ? null
          : GraphRetainingPath.fromJson(
              (rawPath as Map).cast<String, Object?>(),
            ),
    );
  }

  Map<String, Object?> toJson() => {
    'className': className,
    if (libraryUri != null) 'libraryUri': libraryUri.toString(),
    'totalInstances': totalInstances,
    'retainedShallowBytes': retainedShallowBytes,
    'byRoot': {for (final entry in byRoot.entries) entry.key.name: entry.value},
    if (representativePath != null)
      'representativePath': representativePath!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassRootProfile &&
          className == other.className &&
          libraryUri == other.libraryUri &&
          totalInstances == other.totalInstances &&
          retainedShallowBytes == other.retainedShallowBytes &&
          _mapEquals(byRoot, other.byRoot) &&
          representativePath == other.representativePath;

  @override
  int get hashCode => Object.hash(
    className,
    libraryUri,
    totalInstances,
    retainedShallowBytes,
    Object.hashAllUnordered(
      byRoot.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    representativePath,
  );
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
