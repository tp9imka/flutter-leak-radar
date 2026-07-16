// lib/src/analysis/leak_analyzer.dart
import 'package:leak_graph/leak_graph.dart';

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

  /// [projectPackages] and [projectPackageSource] are resolved by the engine's
  /// detection chain (see `LeakEngine`); when omitted, origins classify against
  /// an empty project set and the report is labelled `'none'`.
  LeakReport analyze(
    SampleHistory history, {
    required String trigger,
    required LeakRadarStatus status,
    List<LeakFinding> preciseFindings = const <LeakFinding>[],
    Set<String> projectPackages = const <String>{},
    String projectPackageSource = 'none',
  }) {
    final classifier = OriginClassifier(projectPackages: projectPackages);
    final findings = <LeakFinding>[...preciseFindings];

    for (final className in history.classNames) {
      final rule = suspects.ruleFor(className);
      if (rule == null || rule.mode == LeakDetectionMode.ignore) continue;

      // App-relevance: a broad default glob ([LeakRule.appOnly]) only flags
      // app-owned classes — drops framework churn (_FocusState,
      // AnimationController, _Timer, ValueNotifier). Fail OPEN: drop only a
      // class positively known to be framework/SDK-owned; if the library is
      // unknown, keep it rather than silently dropping everything when the
      // allocation profile lacks library info.
      final library = history.libraryFor(className);
      if (rule.appOnly && library != null && !_isAppOwned(library)) continue;

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
          LeakDetectionMode.maxLive =>
            rule.maxLive != null && liveCount > rule.maxLive!,
          LeakDetectionMode.ignore => false,
          LeakDetectionMode.growth => false, // handled above
        };
      }
      if (!tripped) continue;

      findings.add(
        LeakFinding(
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
          library: library,
          origin: _originFor(classifier, library),
          bytes: history.latestBytesFor(className),
          series: series,
          captureTimes: history.captureTimestamps,
        ),
      );
    }

    findings.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return LeakReport(
      findings: findings,
      capturedAt: DateTime.now(),
      trigger: trigger,
      status: status,
      heapBytes: history.latestHeapBytes,
      projectPackageSource: projectPackageSource,
    );
  }

  /// Classifies [library] into a [ClassOrigin]; unknown when the library is
  /// absent or unparseable.
  static ClassOrigin _originFor(OriginClassifier classifier, String? library) {
    if (library == null) return ClassOrigin.unknown;
    final uri = Uri.tryParse(library);
    if (uri == null) return ClassOrigin.unknown;
    return classifier.classify(uri);
  }

  static bool _isMonotonic(List<int> series) {
    for (var i = 1; i < series.length; i++) {
      if (series[i] < series[i - 1]) return false;
    }
    return series.length >= 2 && series.last > series.first;
  }

  static const Set<String> _frameworkPackages = {
    'flutter',
    'flutter_test',
    'flutter_localizations',
    'flutter_web_plugins',
    'sky_engine',
    'vm_service',
  };

  /// Whether [library] is an app-owned (non-SDK, non-framework) `package:` URI.
  /// `dart:*` URIs and framework packages are not app-owned.
  static bool _isAppOwned(String library) {
    final uri = Uri.tryParse(library);
    if (uri == null || uri.scheme != 'package') return false;
    final pkg = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return !_frameworkPackages.contains(pkg);
  }
}
