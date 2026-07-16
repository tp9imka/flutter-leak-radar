import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves a `package:` library uri to an absolute source path using a
/// workspace's `.dart_tool/package_config.json`.
///
/// This is how a hop's declaring library becomes something an editor can open.
/// Pure I/O + JSON and dependency-light: never throws — a missing or malformed
/// config, or a package the config doesn't list, all resolve to `null` (the
/// honest "can't map this" answer) rather than an error.
final class PackageConfigResolver {
  const PackageConfigResolver(this.projectRoot);

  /// The workspace root that contains `.dart_tool/package_config.json`.
  final String projectRoot;

  /// The absolute file path for [libraryUri], or `null` when it cannot be
  /// resolved (non-`package:` uri, missing/broken config, unknown package).
  Future<String?> resolve(Uri libraryUri) async {
    if (libraryUri.scheme != 'package') return null;
    final segments = libraryUri.pathSegments;
    if (segments.isEmpty) return null;
    final packageName = segments.first;
    final relative = segments.skip(1).join('/');

    final entry = await _packageEntry(packageName);
    if (entry == null) return null;

    final rootUri = entry['rootUri'];
    if (rootUri is! String) return null;
    final packageUri = entry['packageUri'] is String
        ? entry['packageUri'] as String
        : 'lib/';

    // rootUri is relative to the directory holding package_config.json.
    final base = Uri.directory(p.join(projectRoot, '.dart_tool'));
    final packageRoot = base.resolve(_asDir(rootUri));
    final libRoot = packageRoot.resolve(_asDir(packageUri));
    final fileUri = relative.isEmpty ? libRoot : libRoot.resolve(relative);
    try {
      return fileUri.toFilePath();
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>?> _packageEntry(String packageName) async {
    final file = File(p.join(projectRoot, '.dart_tool', 'package_config.json'));
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      final packages = decoded['packages'];
      if (packages is! List) return null;
      for (final entry in packages) {
        if (entry is Map<String, Object?> && entry['name'] == packageName) {
          return entry;
        }
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// Ensures a trailing slash so [Uri.resolve] treats [value] as a directory.
  String _asDir(String value) => value.endsWith('/') ? value : '$value/';
}
