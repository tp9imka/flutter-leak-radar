import '../model/native_heap_profile.dart';

/// Converts a captured trace into a [NativeHeapProfile] checkpoint.
///
/// [source] is deliberately typed `Object` rather than a concrete Perfetto
/// query-result type: it's an opaque handle (e.g. query rows) the host
/// provides, and keeping it untyped here means `radar_native` stays free of
/// the host's binary/native-library dependency and remains pure Dart.
///
/// The concrete `PerfettoTraceProcessorParser` (bundled
/// `trace_processor_shell` + `package:sqlite3`, querying
/// `heap_profile_allocation`/`stack_profile_*`) lives in the host/desktop
/// package and is gated on the `.pftrace` round-trip spike — see
/// `docs/specs/2026-07-02-native-gpu-review.md` §5.
abstract interface class NativeProfileParser {
  /// Parses [source] into a [NativeHeapProfile] checkpoint labeled [label].
  NativeHeapProfile parse(Object source, {String label = ''});
}

/// A test/desktop-synthetic [NativeProfileParser] double: wraps a
/// pre-built [NativeHeapProfile] and returns it unchanged, ignoring
/// [source].
///
/// Lets downstream code (diffing, `MemorySession` assembly, desktop UI)
/// be written and tested against the [NativeProfileParser] seam before the
/// real Perfetto-backed parser lands.
final class InMemoryNativeProfileParser implements NativeProfileParser {
  const InMemoryNativeProfileParser(this._profile);

  final NativeHeapProfile _profile;

  @override
  NativeHeapProfile parse(Object source, {String label = ''}) => _profile;
}
