import 'package:radar_native_host/radar_native_host.dart';

/// [AdbRunner] that re-resolves the `adb` binary path via [adbPath] on
/// every call, instead of pinning one at construction time.
///
/// `radar_native_host`'s [ProcessAdbRunner] takes a fixed path, so a
/// Locate/Install in the Tools screen would otherwise only take effect
/// after rebuilding the capture/device-probe seams — which would lose
/// `NativeProfilingController` state (imported checkpoints, symbol store).
/// Wrapping it here instead lets the *path* change live while the seam
/// instance (and everything built on top of it) stays put.
final class LazyAdbRunner implements AdbRunner {
  const LazyAdbRunner(this.adbPath, {AdbRunner Function(String)? runnerFor})
    : _runnerFor = runnerFor ?? _defaultRunnerFor;

  /// Resolves the current `adb` path — e.g.
  /// `ToolsController.resolvedPath(ExternalTool.adb)`. Null (or a null
  /// return) falls back to the bare `'adb'` name, i.e. today's `PATH`
  /// behavior.
  final String? Function()? adbPath;

  /// Builds the delegate [AdbRunner] for a resolved path; overridden in
  /// tests to avoid spawning a real `adb` process.
  final AdbRunner Function(String path) _runnerFor;

  @override
  Future<AdbResult> run(List<String> args, {String? serial, String? stdin}) =>
      _runnerFor(
        adbPath?.call() ?? 'adb',
      ).run(args, serial: serial, stdin: stdin);
}

AdbRunner _defaultRunnerFor(String path) => ProcessAdbRunner(adbPath: path);

/// [Symbolizer] that re-resolves the `llvm-symbolizer` binary path via
/// [binaryPath] on every call — see [LazyAdbRunner] for why a lazy
/// resolver (rather than a path fixed at construction) matters here.
final class LazySymbolizer implements Symbolizer {
  const LazySymbolizer(
    this.binaryPath, {
    Symbolizer Function(String)? symbolizerFor,
  }) : _symbolizerFor = symbolizerFor ?? _defaultSymbolizerFor;

  /// Resolves the current `llvm-symbolizer` path. Null (or a null return)
  /// falls back to the bare `'llvm-symbolizer'` name.
  final String? Function()? binaryPath;

  /// Builds the delegate [Symbolizer] for a resolved path; overridden in
  /// tests to avoid spawning a real `llvm-symbolizer` process.
  final Symbolizer Function(String path) _symbolizerFor;

  @override
  Future<String?> symbolize({required String soPath, required int address}) =>
      _symbolizerFor(
        binaryPath?.call() ?? 'llvm-symbolizer',
      ).symbolize(soPath: soPath, address: address);
}

Symbolizer _defaultSymbolizerFor(String path) =>
    LlvmSymbolizer(binaryPath: path);

/// [BuildIdReader] that re-resolves the `llvm-readelf` binary path via
/// [binaryPath] on every call — see [LazyAdbRunner] for why a lazy
/// resolver (rather than a path fixed at construction) matters here.
final class LazyBuildIdReader implements BuildIdReader {
  const LazyBuildIdReader(
    this.binaryPath, {
    BuildIdReader Function(String)? readerFor,
  }) : _readerFor = readerFor ?? _defaultReaderFor;

  /// Resolves the current `llvm-readelf` path. Null (or a null return)
  /// falls back to the bare `'llvm-readelf'` name.
  final String? Function()? binaryPath;

  /// Builds the delegate [BuildIdReader] for a resolved path; overridden
  /// in tests to avoid spawning a real `llvm-readelf` process.
  final BuildIdReader Function(String path) _readerFor;

  @override
  Future<String?> readBuildId(String soPath) =>
      _readerFor(binaryPath?.call() ?? 'llvm-readelf').readBuildId(soPath);
}

BuildIdReader _defaultReaderFor(String path) =>
    LlvmReadelfBuildIdReader(binaryPath: path);
