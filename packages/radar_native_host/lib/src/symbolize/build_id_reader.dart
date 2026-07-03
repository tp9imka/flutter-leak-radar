import 'dart:io';

/// Thrown when an external symbolization tool (`llvm-readelf`,
/// `llvm-symbolizer`) exits with a non-zero code.
///
/// A process failure is not the same as "no build-id" / "address did not
/// resolve" — those are honest `null` results, not exceptions.
final class SymbolizeToolException implements Exception {
  const SymbolizeToolException(this.message, {required this.stderr});

  final String message;
  final String stderr;

  @override
  String toString() => 'SymbolizeToolException: $message\n$stderr';
}

/// Reads the GNU build-id of an unstripped ELF `.so`, to match it against a
/// frame's `buildId` before symbolizing. Null when the file has no build-id.
abstract interface class BuildIdReader {
  Future<String?> readBuildId(String soPath);
}

/// [BuildIdReader] backed by `llvm-readelf`/`readelf -n`.
///
/// Resolves the binary via [binaryPath] → `RADAR_READELF` env → the bare
/// `llvm-readelf` name on `PATH` (see [resolveReadelfBinary]).
final class LlvmReadelfBuildIdReader implements BuildIdReader {
  const LlvmReadelfBuildIdReader({this.binaryPath = 'llvm-readelf'});

  /// Path to the `llvm-readelf`/`readelf` executable, or a bare name
  /// resolved via `PATH`.
  final String binaryPath;

  @override
  Future<String?> readBuildId(String soPath) async {
    final result = await Process.run(binaryPath, ['-n', soPath]);
    if (result.exitCode != 0) {
      throw SymbolizeToolException(
        '$binaryPath exited with code ${result.exitCode}',
        stderr: result.stderr as String,
      );
    }
    return parseBuildId(result.stdout as String);
  }
}

/// Resolves the `readelf` binary to invoke: [explicit] path, then the
/// `RADAR_READELF` entry of [env], then the bare `llvm-readelf` name
/// resolved via `PATH`.
String resolveReadelfBinary({String? explicit, Map<String, String>? env}) =>
    explicit ?? env?['RADAR_READELF'] ?? 'llvm-readelf';

/// Matches a `Build ID: <hex>` line in `readelf -n` notes output, allowing
/// embedded whitespace in the hex value and case-insensitive labelling.
final _buildIdPattern = RegExp(
  r'build\s*id\s*:\s*([0-9a-fA-F\s]+)',
  caseSensitive: false,
);

/// Pure parse of `llvm-readelf -n` / `readelf -n` stdout into the GNU
/// build-id hex string, lowercased with no embedded whitespace.
///
/// Returns null when the notes output has no `NT_GNU_BUILD_ID` entry (a
/// readable file with no build-id, not a tool failure).
String? parseBuildId(String readelfStdout) {
  final match = _buildIdPattern.firstMatch(readelfStdout);
  if (match == null) return null;
  final hex = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
  return hex.isEmpty ? null : hex.toLowerCase();
}
