/// External CLI tools that Radar Desktop shells out to for capture, trace
/// import, and native symbolization.
///
/// A Finder/Dock-launched macOS app sees a minimal `PATH` and none of a
/// user's shell-exported environment, so each tool must be discoverable
/// through more than just `PATH` — see `ToolProbe` for the resolution
/// order this drives.
enum ExternalTool { traceProcessor, adb, llvmSymbolizer, llvmReadelf }

/// Static metadata describing how to identify, resolve, and honestly
/// report on each [ExternalTool].
extension ExternalToolInfo on ExternalTool {
  /// The bare executable name, also used as the last-resort `PATH`
  /// lookup and as the key under which a resolved path is persisted.
  String get id => switch (this) {
    ExternalTool.traceProcessor => 'trace_processor',
    ExternalTool.adb => 'adb',
    ExternalTool.llvmSymbolizer => 'llvm-symbolizer',
    ExternalTool.llvmReadelf => 'llvm-readelf',
  };

  /// A human-readable label for the Tools screen.
  String get label => switch (this) {
    ExternalTool.traceProcessor => 'Perfetto trace_processor',
    ExternalTool.adb => 'Android adb',
    ExternalTool.llvmSymbolizer => 'LLVM llvm-symbolizer',
    ExternalTool.llvmReadelf => 'LLVM llvm-readelf',
  };

  /// One line describing what breaks without this tool, shown next to
  /// its status.
  String get purpose => switch (this) {
    ExternalTool.traceProcessor =>
      'Imports .pftrace heapprofd captures into Radar checkpoints.',
    ExternalTool.adb => 'Drives on-device heapprofd capture sessions.',
    ExternalTool.llvmSymbolizer =>
      'Resolves native addresses to symbol names when symbolizing.',
    ExternalTool.llvmReadelf =>
      "Reads a native .so's build-id to match it to debug symbols.",
  };

  /// The environment variable that can pin an explicit path, or the
  /// empty string for tools with no dedicated variable (`adb`, which is
  /// conventionally resolved via the Android SDK or `PATH` alone).
  String get envVar => switch (this) {
    ExternalTool.traceProcessor => 'RADAR_TP_BIN',
    ExternalTool.adb => '',
    ExternalTool.llvmSymbolizer => 'RADAR_LLVM_SYMBOLIZER',
    ExternalTool.llvmReadelf => 'RADAR_READELF',
  };

  /// Arguments that make the tool print its version and exit `0`.
  List<String> get versionArgs => const ['--version'];

  /// Whether importing a heapprofd trace is impossible without this
  /// tool present.
  bool get isRequiredForImport => this == ExternalTool.traceProcessor;
}

/// Where a resolved [ExternalTool] path came from — shown in the UI so a
/// user can tell "auto-discovered via Homebrew" apart from "you set this
/// explicitly".
enum ToolSource {
  /// An explicit path passed into `ToolProbe.probe` (a persisted user
  /// setting).
  config,

  /// The tool's dedicated environment variable.
  env,

  /// A Homebrew install prefix (`/opt/homebrew` or `/usr/local`).
  homebrew,

  /// The Android SDK's `platform-tools` directory.
  androidSdk,

  /// An Android NDK toolchain's `llvm/prebuilt/*/bin` directory.
  ndk,

  /// A well-known install location this app itself manages (or any
  /// common location that doesn't match a more specific tier above),
  /// as opposed to something resolved via `PATH` or an env var.
  appManaged,

  /// The bare tool name, resolved by the OS via `PATH`. Never used for
  /// an absolute common-location candidate — see [appManaged].
  path,

  /// No candidate both existed and verified.
  none,
}

/// The result of probing for a single [ExternalTool]: whether it was
/// found, where it was found, and what version it reports.
final class ToolStatus {
  const ToolStatus({
    required this.tool,
    this.path,
    this.version,
    required this.found,
    required this.source,
  });

  /// The tool this status describes.
  final ExternalTool tool;

  /// The resolved path, or null when [found] is false.
  final String? path;

  /// The first non-empty line the tool printed for `--version`, or null
  /// when [found] is false.
  final String? version;

  /// Whether some candidate path both existed and ran `--version`
  /// successfully.
  final bool found;

  /// Which resolution tier produced [path].
  final ToolSource source;
}
