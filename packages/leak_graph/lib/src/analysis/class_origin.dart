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
    if (libraryUri.scheme != 'package') return ClassOrigin.unknown;

    final package = libraryUri.pathSegments.first;
    if (kFlutterFrameworkPackages.contains(package)) {
      return ClassOrigin.flutterFramework;
    }
    if (_projectPackages.contains(package)) return ClassOrigin.project;
    return ClassOrigin.dependency;
  }

  /// Package name for `package:` URIs, `dart:<lib>` for SDK, null otherwise.
  String? packageOf(Uri libraryUri) {
    return switch (libraryUri.scheme) {
      'package' => libraryUri.pathSegments.first,
      'dart' => 'dart:${libraryUri.path}',
      _ => null,
    };
  }
}
