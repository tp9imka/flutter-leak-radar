import 'package:radar_native/radar_native.dart';

import 'build_id_reader.dart';
import 'symbolizer.dart';

/// Builds a [SymbolStore] for a [NativeHeapProfile] by build-id-matching a
/// set of unstripped `.so` files and symbolizing every module-only (`0x…`)
/// frame address found in the profile.
///
/// Build-ids with no matching `.so` are left out of the store, so those
/// frames stay module-only — an honest degradation rather than a guess.
/// Deterministic for a given [profile] and `soPaths`; no I/O beyond the
/// injected [buildIdReader] / [symbolizer] seams.
final class SymbolStoreBuilder {
  const SymbolStoreBuilder({
    required this.buildIdReader,
    required this.symbolizer,
  });

  final BuildIdReader buildIdReader;
  final Symbolizer symbolizer;

  /// Builds the [SymbolStore] alone; see [buildWithReport] for match/resolve
  /// counts.
  Future<SymbolStore> build(
    NativeHeapProfile profile, {
    required List<String> soPaths,
  }) async => (await buildWithReport(profile, soPaths: soPaths)).store;

  /// Builds the [SymbolStore] plus a [SymbolStoreBuildReport] summarizing how
  /// many of the profile's build-ids matched a `.so` and how many addresses
  /// resolved to a name.
  Future<SymbolStoreBuildReport> buildWithReport(
    NativeHeapProfile profile, {
    required List<String> soPaths,
  }) async {
    final soPathByBuildId = await _readBuildIds(soPaths);
    final hexesByBuildId = _unsymbolizedAddresses(profile);

    final byBuildId = <String, Map<String, String>>{};
    var matchedBuildIds = 0;
    var unmatchedBuildIds = 0;
    var resolvedAddresses = 0;
    var unresolvedAddresses = 0;

    for (final entry in hexesByBuildId.entries) {
      final soPath = soPathByBuildId[entry.key];
      if (soPath == null) {
        unmatchedBuildIds++;
        continue;
      }
      matchedBuildIds++;
      for (final hex in entry.value) {
        final address = int.parse(hex.substring(2), radix: 16);
        final name = await symbolizer.symbolize(
          soPath: soPath,
          address: address,
        );
        if (name == null) {
          unresolvedAddresses++;
          continue;
        }
        (byBuildId[entry.key] ??= {})[hex] = name;
        resolvedAddresses++;
      }
    }

    return SymbolStoreBuildReport(
      store: SymbolStore(byBuildId),
      matchedBuildIds: matchedBuildIds,
      unmatchedBuildIds: unmatchedBuildIds,
      resolvedAddresses: resolvedAddresses,
      unresolvedAddresses: unresolvedAddresses,
    );
  }

  /// Reads each `.so`'s build-id; first file wins on a duplicate build-id.
  /// A file with no build-id (a readable file with none present) is skipped;
  /// a genuine tool failure (`SymbolizeToolException`) propagates.
  Future<Map<String, String>> _readBuildIds(List<String> soPaths) async {
    final soPathByBuildId = <String, String>{};
    for (final soPath in soPaths) {
      final buildId = await buildIdReader.readBuildId(soPath);
      if (buildId == null) continue;
      soPathByBuildId.putIfAbsent(buildId, () => soPath);
    }
    return soPathByBuildId;
  }
}

/// Collects, per build-id, the set of `0x…` frame addresses seen across
/// [profile]'s callsites. Frames with no build-id or an already-symbolized
/// `function` are ignored.
Map<String, Set<String>> _unsymbolizedAddresses(NativeHeapProfile profile) {
  final hexesByBuildId = <String, Set<String>>{};
  for (final callsite in profile.callsites) {
    for (final frame in callsite.frames) {
      final buildId = frame.buildId;
      if (buildId == null || !frame.function.startsWith('0x')) continue;
      (hexesByBuildId[buildId] ??= {}).add(frame.function);
    }
  }
  return hexesByBuildId;
}

/// Summary of a [SymbolStoreBuilder.buildWithReport] run: how many of the
/// profile's build-ids matched a `.so`, and how many `0x…` addresses
/// resolved to a symbol name.
final class SymbolStoreBuildReport {
  const SymbolStoreBuildReport({
    required this.store,
    required this.matchedBuildIds,
    required this.unmatchedBuildIds,
    required this.resolvedAddresses,
    required this.unresolvedAddresses,
  });

  final SymbolStore store;

  /// Distinct build-ids referenced by an unsymbolized frame that matched one
  /// of the supplied `.so` files.
  final int matchedBuildIds;

  /// Distinct build-ids referenced by an unsymbolized frame with no matching
  /// `.so` — those frames stay module-only.
  final int unmatchedBuildIds;

  /// `0x…` addresses that `symbolizer` resolved to a non-null name.
  final int resolvedAddresses;

  /// `0x…` addresses under a matched build-id that `symbolizer` could not
  /// resolve (returned null) — those frames stay module-only.
  final int unresolvedAddresses;
}
