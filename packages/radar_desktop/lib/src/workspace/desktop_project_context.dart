import 'dart:io';

import 'package:leak_graph/io.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'package_config_resolver.dart';

/// Launches an editor on [absolutePath], returning whether it started.
typedef SourceLauncher = Future<bool> Function(String absolutePath);

/// Desktop [ProjectContext]: detects project packages from a workspace
/// directory and opens hop sources in the developer's editor.
///
/// [projectRoot] is a real on-disk Flutter/Dart project. Detection reads its
/// pubspec names via `package:leak_graph/io.dart`; [openSource] maps a
/// `package:` uri to a file through the workspace `package_config.json` and
/// hands it to [launcher]. With no [projectRoot] the context is inert (no
/// packages, nothing to open) — honest, never a guess.
final class DesktopProjectContext implements ProjectContext {
  DesktopProjectContext({this.projectRoot, SourceLauncher? launcher})
    : _launcher = launcher ?? _openInDefaultEditor;

  final String? projectRoot;
  final SourceLauncher _launcher;
  String _label = 'none';

  PackageConfigResolver? get _resolver {
    final root = projectRoot;
    return root == null ? null : PackageConfigResolver(root);
  }

  @override
  bool get canOpenSource => projectRoot != null;

  @override
  String get sourceLabel => _label;

  @override
  Future<Set<String>> projectPackages() async {
    final root = projectRoot;
    if (root == null) {
      _label = 'none';
      return const {};
    }
    final packages = await projectPackagesFromDir(root);
    _label = packages.isEmpty ? 'none' : 'workspace';
    return packages;
  }

  @override
  Future<bool> openSource(Uri libraryUri) async {
    final resolver = _resolver;
    if (resolver == null) return false;
    final path = await resolver.resolve(libraryUri);
    if (path == null) return false;
    return _launcher(path);
  }
}

/// Opens [absolutePath] in the OS default editor via `open -t` (macOS). Never
/// throws — a launch failure reads as `false` so the caller can toast honestly.
Future<bool> _openInDefaultEditor(String absolutePath) async {
  try {
    final result = await Process.run('open', ['-t', absolutePath]);
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}
