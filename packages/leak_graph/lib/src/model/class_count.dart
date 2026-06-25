/// Per-class instance tally derived from a heap snapshot — a class histogram.
///
/// This is the standalone, VM-service-free source for heap-growth detection:
/// the same NativeRuntime heap snapshot used for retaining-path analysis yields
/// these counts, so growth can be measured on a physical device without an
/// `getAllocationProfile` (VM service) call.
final class ClassCount {
  final String className;

  /// Library that declared the class, e.g. `package:app/src/foo.dart`.
  final Uri libraryUri;

  /// Number of live instances of the class in the snapshot.
  final int instanceCount;

  /// Summed shallow (own) bytes across those instances.
  final int shallowBytes;

  const ClassCount({
    required this.className,
    required this.libraryUri,
    required this.instanceCount,
    required this.shallowBytes,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassCount &&
          className == other.className &&
          libraryUri == other.libraryUri &&
          instanceCount == other.instanceCount &&
          shallowBytes == other.shallowBytes;

  @override
  int get hashCode =>
      Object.hash(className, libraryUri, instanceCount, shallowBytes);
}
