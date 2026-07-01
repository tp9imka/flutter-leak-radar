import 'graph_retaining_path.dart';

/// One distinct shortest-path "shape" retaining some instances of a class,
/// with how many instances share it and their summed shallow bytes.
///
/// Instances are grouped by path signature, so paths that differ only beyond
/// the signature depth or in array indices fall into the same bucket and share
/// one representative [path].
final class PathBucket {
  /// A representative shortest path (root → object) for this bucket's instances.
  final GraphRetainingPath path;

  /// Number of (sampled) instances retained through this path shape.
  final int instanceCount;

  /// Summed SHALLOW (own) bytes of those instances. Not a true retained size —
  /// see [ClassPathDistribution].
  final int shallowBytes;

  const PathBucket({
    required this.path,
    required this.instanceCount,
    required this.shallowBytes,
  });

  factory PathBucket.fromJson(Map<String, Object?> json) => PathBucket(
    path: GraphRetainingPath.fromJson(
      (json['path'] as Map).cast<String, Object?>(),
    ),
    instanceCount: json['instanceCount'] as int,
    shallowBytes: json['shallowBytes'] as int,
  );

  Map<String, Object?> toJson() => {
    'path': path.toJson(),
    'instanceCount': instanceCount,
    'shallowBytes': shallowBytes,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathBucket &&
          path == other.path &&
          instanceCount == other.instanceCount &&
          shallowBytes == other.shallowBytes;

  @override
  int get hashCode => Object.hash(path, instanceCount, shallowBytes);
}

/// Distribution of a class's reachable instances across their distinct shortest
/// retaining paths — the data behind a "144 instances → 24 via path A, 20 via
/// path B…" breakdown.
///
/// Materialized only for a bounded set of classes and, per class, over at most
/// a capped number of instances. [sampledInstances] records how many instances
/// were actually attributed, so a partial breakdown is never presented as
/// complete (see [isSampled]).
final class ClassPathDistribution {
  final String className;

  /// Total reachable instances of the class (matches the class root profile).
  final int totalInstances;

  /// Instances walked and attributed to a bucket. Equals the sum of every
  /// bucket's [PathBucket.instanceCount] plus [otherPathCount]. Less than
  /// [totalInstances] when the per-class sample cap was hit.
  final int sampledInstances;

  /// Top path buckets by instance count, most-shared first.
  final List<PathBucket> paths;

  /// Sampled instances whose paths fell outside the retained top [paths].
  final int otherPathCount;

  const ClassPathDistribution({
    required this.className,
    required this.totalInstances,
    required this.sampledInstances,
    required this.paths,
    this.otherPathCount = 0,
  });

  /// True when not every instance was attributed to a path (sample cap hit).
  bool get isSampled => sampledInstances < totalInstances;

  factory ClassPathDistribution.fromJson(Map<String, Object?> json) =>
      ClassPathDistribution(
        className: json['className'] as String,
        totalInstances: json['totalInstances'] as int,
        sampledInstances: json['sampledInstances'] as int,
        paths: [
          for (final p in (json['paths'] as List? ?? const []))
            PathBucket.fromJson((p as Map).cast<String, Object?>()),
        ],
        otherPathCount: json['otherPathCount'] as int? ?? 0,
      );

  Map<String, Object?> toJson() => {
    'className': className,
    'totalInstances': totalInstances,
    'sampledInstances': sampledInstances,
    'paths': [for (final p in paths) p.toJson()],
    if (otherPathCount > 0) 'otherPathCount': otherPathCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassPathDistribution &&
          className == other.className &&
          totalInstances == other.totalInstances &&
          sampledInstances == other.sampledInstances &&
          otherPathCount == other.otherPathCount &&
          _listEquals(paths, other.paths);

  @override
  int get hashCode => Object.hash(
    className,
    totalInstances,
    sampledInstances,
    otherPathCount,
    Object.hashAll(paths),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
