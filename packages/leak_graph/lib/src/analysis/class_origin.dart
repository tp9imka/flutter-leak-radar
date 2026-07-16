/// Where a class's declaring library comes from.
enum ClassOrigin { project, dependency, flutterFramework, dartSdk, unknown }

/// Framework packages (declaring-library classification).
const Set<String> kFlutterFrameworkPackages = {
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_driver',
  'flutter_web_plugins',
  'sky_engine',
};

/// Classifies a class's declaring library into a [ClassOrigin].
final class OriginClassifier {
  /// [projectPackages]: resolved app-owned package names (same semantics as
  /// GraphAnalysisOptions.appPackages after AppPackageSet resolution).
  const OriginClassifier({required Set<String> projectPackages})
    : _projectPackages = projectPackages;

  final Set<String> _projectPackages;

  /// Classifies [libraryUri] by scheme and, for `package:` URIs, by which
  /// package set it falls into.
  ClassOrigin classify(Uri libraryUri) {
    if (libraryUri.scheme == 'dart') return ClassOrigin.dartSdk;

    final package = _packageSegment(libraryUri);
    if (package == null) return ClassOrigin.unknown;
    if (kFlutterFrameworkPackages.contains(package)) {
      return ClassOrigin.flutterFramework;
    }
    if (_projectPackages.contains(package)) return ClassOrigin.project;
    return ClassOrigin.dependency;
  }

  /// Package name for `package:` URIs, `dart:<lib>` for SDK, null otherwise.
  String? packageOf(Uri libraryUri) {
    if (libraryUri.scheme == 'dart') return 'dart:${libraryUri.path}';
    return _packageSegment(libraryUri);
  }

  /// First path segment of a `package:` URI, or null when [libraryUri] isn't
  /// a `package:` URI or is malformed (e.g. `package:` with no segments).
  String? _packageSegment(Uri libraryUri) {
    if (libraryUri.scheme != 'package') return null;
    if (libraryUri.pathSegments.isEmpty) return null;
    return libraryUri.pathSegments.first;
  }
}
