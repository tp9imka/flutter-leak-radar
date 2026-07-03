import 'package:meta/meta.dart';

import '../model/native_callsite.dart';
import '../model/native_heap_profile.dart';
import 'native_module.dart';
import 'native_module_kind.dart';

/// A checkpoint's callsites rolled up by attributed module — the rollup the
/// Android still-live table / compare / detail views rest on.
@immutable
final class NativeModuleSummary {
  const NativeModuleSummary({
    required this.module,
    required this.kind,
    required this.stillLiveBytes,
    required this.stillLiveCount,
    required this.callsites,
  });

  /// Short display name (see [moduleShortName]) of the attributed module.
  final String module;

  /// UI color-kind bucket, resolved from the attributed FULL module path.
  final NativeModuleKind kind;

  /// Sum of [NativeCallsite.stillLiveBytes] across this module's callsites.
  final int stillLiveBytes;

  /// Sum of [NativeCallsite.stillLiveCount] across this module's callsites.
  final int stillLiveCount;

  /// Callsites attributed to this module, in first-seen order.
  final List<NativeCallsite> callsites;
}

/// Roll a checkpoint's callsites up by attributed module. Groups by the
/// attributed frame's SHORT module name; kind from its FULL path. Callsites
/// with no frames group under module `''`. Sorted by [stillLiveBytes]
/// descending, tie-broken by module name ascending.
List<NativeModuleSummary> summarizeByModule(NativeHeapProfile profile) {
  final order = <String>[];
  final bytesByModule = <String, int>{};
  final countByModule = <String, int>{};
  final kindByModule = <String, NativeModuleKind>{};
  final callsitesByModule = <String, List<NativeCallsite>>{};

  for (final callsite in profile.callsites) {
    final fullModule = attributedFrame(callsite)?.module ?? '';
    final module = moduleShortName(fullModule);
    if (!bytesByModule.containsKey(module)) {
      order.add(module);
      bytesByModule[module] = 0;
      countByModule[module] = 0;
      kindByModule[module] = moduleKind(fullModule);
      callsitesByModule[module] = [];
    }
    bytesByModule[module] = bytesByModule[module]! + callsite.stillLiveBytes;
    countByModule[module] = countByModule[module]! + callsite.stillLiveCount;
    callsitesByModule[module]!.add(callsite);
  }

  final summaries =
      [
        for (final module in order)
          NativeModuleSummary(
            module: module,
            kind: kindByModule[module]!,
            stillLiveBytes: bytesByModule[module]!,
            stillLiveCount: countByModule[module]!,
            callsites: callsitesByModule[module]!,
          ),
      ]..sort((a, b) {
        final bytes = b.stillLiveBytes.compareTo(a.stillLiveBytes);
        return bytes != 0 ? bytes : a.module.compareTo(b.module);
      });
  return summaries;
}
