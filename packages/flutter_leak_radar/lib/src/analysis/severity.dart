// lib/src/analysis/severity.dart
import '../config/leak_rule.dart';
import '../model/leak_kind.dart';

/// Computed severity floor for a heap finding. A [hint] can only raise it.
LeakSeverity computeSeverity({
  required LeakDetectionMode mode,
  required int growth,
  required int liveCount,
  int? maxLive,
  required bool monotonic,
  LeakSeverity? hint,
}) {
  var sev = LeakSeverity.info;
  if (mode == LeakDetectionMode.maxLive && maxLive != null) {
    if (liveCount > 2 * maxLive) {
      sev = LeakSeverity.critical;
    } else if (liveCount > maxLive) {
      sev = LeakSeverity.warning;
    }
  } else if (mode == LeakDetectionMode.growth) {
    if (monotonic && growth >= 2) {
      sev = LeakSeverity.critical;
    } else if (growth >= 1) {
      sev = LeakSeverity.warning;
    }
  }
  if (hint != null && hint.index > sev.index) sev = hint;
  return sev;
}
