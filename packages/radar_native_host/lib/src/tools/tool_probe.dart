import 'dart:io';

import 'external_tool.dart';

/// Checks whether a file exists at [path]. The real implementation is
/// `File(path).existsSync`; tests inject a fake existence map so no real
/// filesystem access happens in unit tests.
typedef FileProbe = bool Function(String path);

/// Runs an external process and reports its outcome. The real
/// implementation wraps [Process.run]; tests inject canned results so no
/// real process is spawned in unit tests.
typedef ProcessProbe =
    Future<({int exitCode, String stdout, String stderr})> Function(
      String exe,
      List<String> args,
    );

/// A single location to try while resolving a tool, tagged with the
/// [ToolSource] tier it belongs to and whether it's the trailing bare
/// `tool.id` candidate left for the OS to resolve via `PATH` — the only
/// candidate not existence-checked, since a bare name isn't a filesystem
/// path. Every other candidate (config, env, and every common location,
/// including ones [_classifyLocation] can't recognize) is an absolute
/// path and must be existence-checked regardless of its [source].
typedef _Candidate = ({String path, ToolSource source, bool isBareName});

/// Resolves an [ExternalTool] to an on-disk path and verifies it
/// actually runs, so a Finder/Dock-launched app (minimal `PATH`, no
/// shell-exported env) can still find its tools.
///
/// Resolution order: [probe]'s `configuredPath` → the tool's env var
/// (`env[tool.envVar]`, skipped when the tool has none) → each entry
/// from `commonLocations(tool)` that exists → the bare `tool.id`, left
/// for the OS to resolve via `PATH` (existence unchecked, since a bare
/// name isn't a filesystem path). The first candidate that both exists
/// and is verified by running it with `tool.versionArgs` wins; a
/// candidate that exists but fails to run falls through to the next
/// one. A tool counts as found only once some candidate both exists and
/// reports a successful version.
final class ToolProbe {
  const ToolProbe({
    FileProbe? exists,
    ProcessProbe? run,
    List<String> Function(ExternalTool)? commonLocations,
    this.homeDir,
  }) : _exists = exists ?? _defaultExists,
       _run = run ?? _defaultRun,
       _commonLocations = commonLocations;

  final FileProbe _exists;
  final ProcessProbe _run;
  final List<String> Function(ExternalTool)? _commonLocations;

  /// Root directory the default common-location scan is resolved
  /// relative to; defaults to the `HOME` environment variable. Ignored
  /// when a custom `commonLocations` is supplied.
  final String? homeDir;

  /// Probes [tool], trying [configuredPath], then its env var in [env],
  /// then well-known install locations, then the bare name on `PATH`.
  Future<ToolStatus> probe(
    ExternalTool tool, {
    String? configuredPath,
    Map<String, String> env = const {},
  }) async {
    for (final candidate in _candidatesFor(tool, configuredPath, env)) {
      if (!candidate.isBareName && !_exists(candidate.path)) continue;

      final result = await _run(candidate.path, tool.versionArgs);
      if (result.exitCode == 0) {
        return ToolStatus(
          tool: tool,
          path: candidate.path,
          version: _firstNonEmptyLine(result.stdout, result.stderr),
          found: true,
          source: candidate.source,
        );
      }
    }
    return ToolStatus(tool: tool, found: false, source: ToolSource.none);
  }

  Iterable<_Candidate> _candidatesFor(
    ExternalTool tool,
    String? configuredPath,
    Map<String, String> env,
  ) sync* {
    if (configuredPath != null) {
      yield (
        path: configuredPath,
        source: ToolSource.config,
        isBareName: false,
      );
    }
    if (tool.envVar.isNotEmpty) {
      final envPath = env[tool.envVar];
      if (envPath != null) {
        yield (path: envPath, source: ToolSource.env, isBareName: false);
      }
    }
    for (final location in _resolveCommonLocations(tool)) {
      yield (
        path: location,
        source: _classifyLocation(location),
        isBareName: false,
      );
    }
    yield (path: tool.id, source: ToolSource.path, isBareName: true);
  }

  List<String> _resolveCommonLocations(ExternalTool tool) {
    final commonLocations = _commonLocations;
    return commonLocations != null
        ? commonLocations(tool)
        : _defaultLocationsFor(tool, homeDir);
  }
}

/// Classifies a well-known install location into the [ToolSource] tier
/// shown in the UI. An NDK toolchain path always contains `/ndk/`; the
/// Android SDK's `platform-tools` directory contains `/Android/sdk/`;
/// anything under a Homebrew prefix is `homebrew`. Anything else —
/// including this app's own managed install directory — is an absolute
/// common-location candidate that isn't `PATH`/env, so it's tagged
/// `appManaged` rather than the bare-name-only [ToolSource.path] tier.
ToolSource _classifyLocation(String path) {
  if (path.contains('/ndk/')) return ToolSource.ndk;
  if (path.contains('/Android/sdk/')) return ToolSource.androidSdk;
  if (path.contains('homebrew') || path.startsWith('/usr/local/')) {
    return ToolSource.homebrew;
  }
  return ToolSource.appManaged;
}

/// The first non-empty, trimmed line from [stdout] or (failing that)
/// [stderr] — the reported version string.
String? _firstNonEmptyLine(String stdout, String stderr) {
  for (final output in [stdout, stderr]) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
  }
  return null;
}

bool _defaultExists(String path) => File(path).existsSync();

Future<({int exitCode, String stdout, String stderr})> _defaultRun(
  String exe,
  List<String> args,
) async {
  try {
    final result = await Process.run(exe, args);
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  } on ProcessException catch (e) {
    return (exitCode: -1, stdout: '', stderr: e.message);
  }
}

/// The default common-location scan for [tool], rooted at [homeDir]
/// (falling back to the `HOME` environment variable when null).
List<String> _defaultLocationsFor(ExternalTool tool, String? homeDir) {
  final home = homeDir ?? Platform.environment['HOME'] ?? '';
  return switch (tool) {
    ExternalTool.traceProcessor => [
      '$home/Library/Application Support/radar_desktop/bin/trace_processor',
      '/opt/homebrew/bin/trace_processor',
      '/usr/local/bin/trace_processor',
    ],
    ExternalTool.adb => [
      '/opt/homebrew/bin/adb',
      '$home/Library/Android/sdk/platform-tools/adb',
      '/usr/local/bin/adb',
    ],
    ExternalTool.llvmSymbolizer || ExternalTool.llvmReadelf => [
      ..._newestNdkLocations(tool.id, home),
      '/opt/homebrew/opt/llvm/bin/${tool.id}',
      '/opt/homebrew/bin/${tool.id}',
    ],
  };
}

/// The `llvm/prebuilt/*/bin/<id>` path(s) under the highest-numbered
/// installed NDK version under `<home>/Library/Android/sdk/ndk`, or an
/// empty list when no NDK is installed.
List<String> _newestNdkLocations(String id, String home) {
  final ndkRoot = Directory('$home/Library/Android/sdk/ndk');
  final versionDirs = _listDirs(ndkRoot);
  if (versionDirs.isEmpty) return const [];

  versionDirs.sort(
    (a, b) => _compareVersions(_basename(a.path), _basename(b.path)),
  );
  final prebuiltRoot = Directory(
    '${versionDirs.last.path}/toolchains/llvm/prebuilt',
  );
  return [
    for (final platformDir in _listDirs(prebuiltRoot))
      '${platformDir.path}/bin/$id',
  ];
}

List<Directory> _listDirs(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir.listSync().whereType<Directory>().toList();
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

/// Numeric, dot-separated version comparison (e.g. `9.0.0` < `21.4.1`) —
/// simpler than a full semver compare, but enough to pick the newest
/// installed NDK.
int _compareVersions(String a, String b) {
  final partsA = a.split('.');
  final partsB = b.split('.');
  final length = partsA.length > partsB.length ? partsA.length : partsB.length;
  for (var i = 0; i < length; i++) {
    final valueA = i < partsA.length ? int.tryParse(partsA[i]) ?? 0 : 0;
    final valueB = i < partsB.length ? int.tryParse(partsB[i]) ?? 0 : 0;
    if (valueA != valueB) return valueA.compareTo(valueB);
  }
  return 0;
}
