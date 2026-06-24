/// Identifies which library URIs belong to the app under analysis.
final class AppPackageSet {
  AppPackageSet._(this._names);

  final Set<String> _names;

  /// Package names excluded from auto-detection (SDK, framework, infra).
  static const Set<String> sdkDenylist = {
    'flutter',
    'sky_engine',
    'leak_graph',
    'flutter_leak_radar',
    'flutter_leak_radar_lint',
    'vm_service',
    'meta',
    'collection',
    'async',
    'path',
    'args',
  };

  /// Creates a set from an explicit list of package names.
  factory AppPackageSet.from(Iterable<String> packageNames) =>
      AppPackageSet._(Set.unmodifiable(packageNames.toSet()));

  /// Derives the app package set from all library URIs in a heap snapshot,
  /// dropping SDK and framework packages via [sdkDenylist].
  factory AppPackageSet.autoDetect(Iterable<Uri> allLibraryUris) {
    final names = <String>{};
    for (final uri in allLibraryUris) {
      if (uri.scheme != 'package') continue;
      final name = uri.pathSegments.first;
      if (!sdkDenylist.contains(name)) names.add(name);
    }
    return AppPackageSet._(Set.unmodifiable(names));
  }

  /// Returns true when [libraryUri] is a `package:` URI belonging to this set.
  bool contains(Uri libraryUri) =>
      libraryUri.scheme == 'package' &&
      _names.contains(libraryUri.pathSegments.first);
}
