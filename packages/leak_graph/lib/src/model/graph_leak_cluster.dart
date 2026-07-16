import 'graph_retaining_path.dart';
import 'root_kind.dart';

/// A group of instances of the same class that share a common retaining root
/// and are suspected of being leaked.
final class GraphLeakCluster {
  final String className;
  final Uri? libraryUri;
  final int instanceCount;
  final int retainedShallowBytes;
  final GraphRetainingPath representativePath;
  final RootKind rootKind;
  final LeakConfidence confidence;
  final String signature;

  /// Internal leaf class when [className] headlines an anchored app owner
  /// (e.g. a `_ControllerSubscription` retained by a `_LeakyScreenState`).
  /// Null when the headline is itself the leaf. Attribution detail carried into
  /// serialized bundles so a drill-down can still name the internal object.
  final String? leafClassName;

  /// Index into [representativePath] `.hops` of the attribution anchor — the
  /// hop app code holds the leak at. Null when there is no app anchor.
  final int? anchorHopIndex;

  const GraphLeakCluster({
    required this.className,
    required this.libraryUri,
    required this.instanceCount,
    required this.retainedShallowBytes,
    required this.representativePath,
    required this.rootKind,
    required this.confidence,
    required this.signature,
    this.leafClassName,
    this.anchorHopIndex,
  });

  factory GraphLeakCluster.fromJson(Map<String, Object?> json) =>
      GraphLeakCluster(
        className: json['className'] as String,
        libraryUri: json['libraryUri'] == null
            ? null
            : Uri.parse(json['libraryUri'] as String),
        instanceCount: json['instanceCount'] as int,
        retainedShallowBytes: json['retainedShallowBytes'] as int,
        representativePath: GraphRetainingPath.fromJson(
          (json['representativePath']! as Map).cast<String, Object?>(),
        ),
        rootKind: RootKind.values.byName(json['rootKind'] as String),
        confidence: LeakConfidence.values.byName(json['confidence'] as String),
        signature: json['signature'] as String,
        leafClassName: json['leafClassName'] as String?,
        anchorHopIndex: json['anchorHopIndex'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphLeakCluster &&
          className == other.className &&
          libraryUri == other.libraryUri &&
          instanceCount == other.instanceCount &&
          retainedShallowBytes == other.retainedShallowBytes &&
          representativePath == other.representativePath &&
          rootKind == other.rootKind &&
          confidence == other.confidence &&
          signature == other.signature &&
          leafClassName == other.leafClassName &&
          anchorHopIndex == other.anchorHopIndex;

  @override
  int get hashCode => Object.hash(
    className,
    libraryUri,
    instanceCount,
    retainedShallowBytes,
    representativePath,
    rootKind,
    confidence,
    signature,
    leafClassName,
    anchorHopIndex,
  );

  Map<String, Object?> toJson() => {
    'className': className,
    if (libraryUri != null) 'libraryUri': libraryUri.toString(),
    'instanceCount': instanceCount,
    'retainedShallowBytes': retainedShallowBytes,
    'representativePath': representativePath.toJson(),
    'rootKind': rootKind.name,
    'confidence': confidence.name,
    'signature': signature,
    if (leafClassName != null) 'leafClassName': leafClassName,
    if (anchorHopIndex != null) 'anchorHopIndex': anchorHopIndex,
  };
}
