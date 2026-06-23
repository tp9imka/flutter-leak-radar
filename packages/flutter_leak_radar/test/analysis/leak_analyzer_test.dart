// test/analysis/leak_analyzer_test.dart
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/analysis/sample_history.dart';
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/model/leak_finding.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';

HeapSnapshot snap(Map<String, int> counts, int t) => HeapSnapshot(
      capturedAt: DateTime(2026, 1, 1, 0, 0, t),
      samples: [
        for (final e in counts.entries)
          ClassSample(className: e.key, instancesCurrent: e.value, bytesCurrent: 0, timestamp: DateTime(2026, 1, 1, 0, 0, t)),
      ],
    );

void main() {
  test('flat series produces no finding', () {
    final h = SampleHistory()..add(snap({'HomeBloc': 1}, 1))..add(snap({'HomeBloc': 1}, 2));
    final report = const LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]))
        .analyze(h, trigger: 'manual', status: LeakRadarStatus.active);
    expect(report.findings, isEmpty);
  });

  test('monotonic growth produces a growth finding', () {
    final h = SampleHistory()
      ..add(snap({'HomeBloc': 1}, 1))
      ..add(snap({'HomeBloc': 2}, 2))
      ..add(snap({'HomeBloc': 3}, 3));
    final report = const LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]))
        .analyze(h, trigger: 'manual', status: LeakRadarStatus.active);
    expect(report.findings.length, 1);
    final f = report.findings.single;
    expect(f.className, 'HomeBloc');
    expect(f.kind, LeakKind.growth);
    expect(f.growth, 2); // latest(3) - baseline(1)
    expect(f.liveCount, 3);
  });

  test('maxLive trips on exceed only', () {
    final atLimit = SampleHistory()..add(snap({'HomeBloc': 1}, 1));
    final over = SampleHistory()..add(snap({'HomeBloc': 2}, 1));
    const analyzer = LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.maxLive('*Bloc', 1)]));
    expect(analyzer.analyze(atLimit, trigger: 'm', status: LeakRadarStatus.active).findings, isEmpty);
    expect(analyzer.analyze(over, trigger: 'm', status: LeakRadarStatus.active).findings.single.kind, LeakKind.growth);
  });

  test('precise findings are folded into the report', () {
    final h = SampleHistory()..add(snap({'X': 1}, 1));
    final precise = [
      const LeakFinding(className: 'CallSession', kind: LeakKind.notGced, severity: LeakSeverity.critical, liveCount: 1, growth: 0, tag: 'CallSession'),
    ];
    final report = const LeakAnalyzer(SuspectSet.empty())
        .analyze(h, trigger: 'manual', status: LeakRadarStatus.active, preciseFindings: precise);
    expect(report.findings.single.tag, 'CallSession');
    expect(report.worstSeverity, LeakSeverity.critical);
  });
}
