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

  const GraphLeakCluster({
    required this.className,
    required this.libraryUri,
    required this.instanceCount,
    required this.retainedShallowBytes,
    required this.representativePath,
    required this.rootKind,
    required this.confidence,
    required this.signature,
  });

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
          signature == other.signature;

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
      };
}
