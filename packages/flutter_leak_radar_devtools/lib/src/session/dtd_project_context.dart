import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// [ProjectContext] backed by the Dart Tooling Daemon (DTD).
///
/// Resolves the developer's project packages by reading each IDE project
/// root's `pubspec.yaml` over DTD ([DartToolingDaemon.readFileAsString]) and
/// parsing its `name:` — the same durable seam [DtdSnapshotStore] uses. A web
/// extension cannot launch an editor, so this is copy-only: [canOpenSource] is
/// `false` and [openSource] never launches.
///
/// Only a NON-EMPTY detection is cached; [sourceLabel] reads `'workspace'` only
/// after a successful read. An empty result (DTD not ready yet, no roots) is
/// left uncached so a later call retries — the daemon commonly connects after
/// first paint, and caching the early empty would strand attribution at
/// `'none'` for the whole session.
final class DtdProjectContext implements ProjectContext {
  /// Test seam: overrides the DTD-backed detection. Production leaves it null.
  DtdProjectContext({@visibleForTesting Future<Set<String>> Function()? detect})
    : _detectOverride = detect;

  final Future<Set<String>> Function()? _detectOverride;
  Set<String>? _cached;
  String _label = 'none';

  @override
  String get sourceLabel => _label;

  @override
  bool get canOpenSource => false;

  @override
  Future<Set<String>> projectPackages() async {
    final cached = _cached;
    if (cached != null && cached.isNotEmpty) return cached;
    final packages = await (_detectOverride ?? _detect)();
    if (packages.isNotEmpty) {
      _cached = packages;
      _label = 'workspace';
    } else {
      _label = 'none';
    }
    return packages;
  }

  Future<Set<String>> _detect() async {
    try {
      if (!dtdManager.hasConnection) return const {};
      final dtd = dtdManager.connection.value;
      if (dtd == null) return const {};
      final roots = (await dtdManager.projectRoots())?.uris ?? const <Uri>[];
      final names = <String>{};
      for (final root in roots) {
        var dir = root;
        if (!dir.path.endsWith('/')) {
          dir = dir.replace(path: '${dir.path}/');
        }
        final content = (await dtd.readFileAsString(
          dir.resolve('pubspec.yaml'),
        )).content;
        if (content == null) continue;
        final name = packageNameFromPubspec(content);
        if (name != null) names.add(name);
      }
      return Set.unmodifiable(names);
    } on Object {
      // No daemon, no roots, or an unreadable/absent pubspec — degrade to
      // "unknown" rather than surfacing an error into the paths view.
      return const {};
    }
  }

  @override
  Future<bool> openSource(Uri libraryUri) async => false;
}
