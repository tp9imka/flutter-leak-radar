// lib/src/analysis/leak_analyzer.dart
import '../config/leak_rule.dart';
import '../config/suspect_set.dart';
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import 'sample_history.dart';
import 'severity.dart';

/// Pure, deterministic detection core. No I/O, no vm_service.
class LeakAnalyzer {
  const LeakAnalyzer(this.suspects);

  final SuspectSet suspects;

  LeakReport analyze(
    SampleHistory history, {
    required String trigger,
    required LeakRadarStatus status,
    List<LeakFinding> preciseFindings = const <LeakFinding>[],
  }) {
    final findings = <LeakFinding>[...preciseFindings];

    for (final className in history.classNames) {
      final rule = suspects.ruleFor(className);
      if (rule == null || rule.mode == LeakDetectionMode.ignore) continue;

      final series = history.seriesFor(className);
      if (series.isEmpty) continue;
      final liveCount = series.last;
      final monotonic = _isMonotonic(series);

      bool tripped;
      int growth;
      if (rule.mode == LeakDetectionMode.growth) {
        // Warm-up guard: class must have been live in at least 2 snapshots.
        final nonZero = series.where((v) => v > 0).toList();
        if (nonZero.length < 2) continue;
        final baseline = nonZero.reduce((a, b) => a < b ? a : b);
        growth = liveCount - baseline;
        tripped = growth >= rule.minGrowth;
      } else {
        final baseline = series.reduce((a, b) => a < b ? a : b);
        growth = liveCount - baseline;
        tripped = switch (rule.mode) {
          LeakDetectionMode.maxLive => rule.maxLive != null && liveCount > rule.maxLive!,
          LeakDetectionMode.ignore => false,
          LeakDetectionMode.growth => false, // handled above
        };
      }
      if (!tripped) continue;

      findings.add(LeakFinding(
        className: className,
        kind: LeakKind.growth,
        severity: computeSeverity(
          mode: rule.mode,
          growth: growth,
          liveCount: liveCount,
          maxLive: rule.maxLive,
          monotonic: monotonic,
          hint: rule.severityHint,
        ),
        liveCount: liveCount,
        growth: growth,
        series: series,
        captureTimes: history.captureTimestamps,
      ));
    }

    findings.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return LeakReport(findings: findings, capturedAt: DateTime.now(), trigger: trigger, status: status);
  }

  static bool _isMonotonic(List<int> series) {
    for (var i = 1; i < series.length; i++) {
      if (series[i] < series[i - 1]) return false;
    }
    return series.length >= 2 && series.last > series.first;
  }
}
