import 'dart:io';

import 'build_id_reader.dart' show SymbolizeToolException;

/// Resolves one relative-PC address inside an unstripped `.so` to a function
/// name. Null when the address does not resolve (`llvm-symbolizer` prints
/// `??`).
abstract interface class Symbolizer {
  Future<String?> symbolize({required String soPath, required int address});
}

/// [Symbolizer] backed by `llvm-symbolizer --obj=<so> <0xhex>`.
///
/// Resolves the binary via [binaryPath] → `RADAR_LLVM_SYMBOLIZER` env → the
/// bare `llvm-symbolizer` name on `PATH` (see [resolveSymbolizerBinary]).
final class LlvmSymbolizer implements Symbolizer {
  const LlvmSymbolizer({this.binaryPath = 'llvm-symbolizer'});

  /// Path to the `llvm-symbolizer` executable, or a bare name resolved via
  /// `PATH`.
  final String binaryPath;

  @override
  Future<String?> symbolize({
    required String soPath,
    required int address,
  }) async {
    final result = await Process.run(binaryPath, [
      '--obj=$soPath',
      '0x${address.toRadixString(16)}',
    ]);
    if (result.exitCode != 0) {
      throw SymbolizeToolException(
        '$binaryPath exited with code ${result.exitCode}',
        stderr: result.stderr as String,
      );
    }
    return parseSymbolizerOutput(result.stdout as String);
  }
}

/// Resolves the `llvm-symbolizer` binary to invoke: [explicit] path, then the
/// `RADAR_LLVM_SYMBOLIZER` entry of [env], then the bare `llvm-symbolizer`
/// name resolved via `PATH`.
String resolveSymbolizerBinary({String? explicit, Map<String, String>? env}) =>
    explicit ?? env?['RADAR_LLVM_SYMBOLIZER'] ?? 'llvm-symbolizer';

/// Pure parse of `llvm-symbolizer` stdout into the function name — the first
/// non-empty line, trimmed. Returns null when that line is `??` or there is
/// no non-empty line (the address did not resolve).
String? parseSymbolizerOutput(String stdout) {
  for (final line in stdout.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    return trimmed == '??' ? null : trimmed;
  }
  return null;
}
