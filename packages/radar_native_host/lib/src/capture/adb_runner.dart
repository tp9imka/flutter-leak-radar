import 'dart:convert';
import 'dart:io';

/// Result of running a single `adb` command.
class AdbResult {
  const AdbResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Whether the command exited successfully.
  bool get ok => exitCode == 0;
}

/// Runs `adb` commands, optionally scoped to a device [serial].
abstract interface class AdbRunner {
  /// Runs `adb [-s serial] <args>`; [stdin] is piped if non-null.
  Future<AdbResult> run(List<String> args, {String? serial, String? stdin});
}

/// Thrown by [ProcessAdbRunner.runOrThrow] when `adb` exits non-zero.
class AdbException implements Exception {
  AdbException(this.args, this.exitCode, this.stderr);

  final List<String> args;
  final int exitCode;
  final String stderr;

  @override
  String toString() =>
      'AdbException: adb ${args.join(' ')} exited $exitCode\n$stderr';
}

/// [AdbRunner] backed by an external `adb` binary, invoked via
/// [Process.run]/[Process.start].
final class ProcessAdbRunner implements AdbRunner {
  const ProcessAdbRunner({this.adbPath = 'adb'});

  /// Path to the `adb` executable, or a bare name resolved via `PATH`.
  final String adbPath;

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    final full = [
      if (serial != null) ...['-s', serial],
      ...args,
    ];
    if (stdin == null) {
      final result = await Process.run(adbPath, full);
      return AdbResult(
        result.exitCode,
        result.stdout as String,
        result.stderr as String,
      );
    }
    final process = await Process.start(adbPath, full);
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(stdin);
    await process.stdin.close();
    final exitCode = await process.exitCode;
    return AdbResult(exitCode, await stdoutFuture, await stderrFuture);
  }

  /// Runs [run] and throws [AdbException] on a non-zero exit code.
  Future<AdbResult> runOrThrow(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    final result = await run(args, serial: serial, stdin: stdin);
    if (!result.ok) {
      throw AdbException(args, result.exitCode, result.stderr);
    }
    return result;
  }
}
