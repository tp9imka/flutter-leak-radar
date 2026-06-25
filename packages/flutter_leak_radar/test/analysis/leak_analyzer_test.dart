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
      ClassSample(
        className: e.key,
        instancesCurrent: e.value,
        bytesCurrent: 0,
        timestamp: DateTime(2026, 1, 1, 0, 0, t),
      ),
  ],
);

HeapSnapshot snapLib(List<(String name, int count, String? lib)> rows, int t) =>
    HeapSnapshot(
      capturedAt: DateTime(2026, 1, 1, 0, 0, t),
      samples: [
        for (final r in rows)
          ClassSample(
            className: r.$1,
            instancesCurrent: r.$2,
            bytesCurrent: 0,
            library: r.$3,
            timestamp: DateTime(2026, 1, 1, 0, 0, t),
          ),
      ],
    );

void main() {
  test('appOnly default rule skips framework-owned but keeps app-owned', () {
    const fw = 'package:flutter/src/widgets/focus_manager.dart';
    const app = 'package:my_app/home.dart';
    final h = SampleHistory()
      ..add(snapLib([('_FocusState', 1, fw), ('HomeState', 1, app)], 1))
      ..add(snapLib([('_FocusState', 3, fw), ('HomeState', 3, app)], 2));
    final report = LeakAnalyzer(
      SuspectSet.defaults(),
    ).analyze(h, trigger: 'm', status: LeakRadarStatus.active);
    final classes = report.findings.map((f) => f.className).toSet();
    expect(classes, contains('HomeState'));
    expect(classes, isNot(contains('_FocusState')));
  });

  test('appOnly filter fails OPEN when the library is unknown', () {
    // No library on the samples → keep rather than silently drop.
    final h = SampleHistory()
      ..add(snap({'_FocusState': 1}, 1))
      ..add(snap({'_FocusState': 3}, 2));
    final report = LeakAnalyzer(
      SuspectSet.defaults(),
    ).analyze(h, trigger: 'm', status: LeakRadarStatus.active);
    expect(report.findings.any((f) => f.className == '_FocusState'), isTrue);
  });

  test('an explicit (non-appOnly) rule still flags a framework class', () {
    const fw = 'package:flutter/src/widgets/editable_text.dart';
    final h = SampleHistory()
      ..add(snapLib([('TextEditingController', 1, fw)], 1))
      ..add(snapLib([('TextEditingController', 3, fw)], 2));
    final report = LeakAnalyzer(
      const SuspectSet(<LeakRule>[LeakRule.growth('TextEditingController')]),
    ).analyze(h, trigger: 'm', status: LeakRadarStatus.active);
    final f = report.findings.singleWhere(
      (f) => f.className == 'TextEditingController',
    );
    expect(f.library, fw);
  });

  test('flat series produces no finding', () {
    final h = SampleHistory()
      ..add(snap({'HomeBloc': 1}, 1))
      ..add(snap({'HomeBloc': 1}, 2));
    final report = const LeakAnalyzer(
      SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
    ).analyze(h, trigger: 'manual', status: LeakRadarStatus.active);
    expect(report.findings, isEmpty);
  });

  test('monotonic growth produces a growth finding', () {
    final h = SampleHistory()
      ..add(snap({'HomeBloc': 1}, 1))
      ..add(snap({'HomeBloc': 2}, 2))
      ..add(snap({'HomeBloc': 3}, 3));
    final report = const LeakAnalyzer(
      SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
    ).analyze(h, trigger: 'manual', status: LeakRadarStatus.active);
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
    const analyzer = LeakAnalyzer(
      SuspectSet(<LeakRule>[LeakRule.maxLive('*Bloc', 1)]),
    );
    expect(
      analyzer
          .analyze(atLimit, trigger: 'm', status: LeakRadarStatus.active)
          .findings,
      isEmpty,
    );
    expect(
      analyzer
          .analyze(over, trigger: 'm', status: LeakRadarStatus.active)
          .findings
          .single
          .kind,
      LeakKind.growth,
    );
  });

  test('growth rule: no finding when class appears only in latest snapshot', () {
    // NewBloc series = [0, 0, 5] — only 1 non-zero sample → warm-up guard skips it.
    final h = SampleHistory()
      ..add(snap({'Other': 1}, 1))
      ..add(snap({'Other': 1}, 2))
      ..add(snap({'Other': 1, 'NewBloc': 5}, 3));
    final report = const LeakAnalyzer(
      SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
    ).analyze(h, trigger: 'manual', status: LeakRadarStatus.active);
    expect(report.findings.where((f) => f.className == 'NewBloc'), isEmpty);
  });

  test(
    'growth rule: finding when class is live in ≥2 snapshots and growing',
    () {
      // NewBloc series = [0, 3, 5] — 2 non-zero samples; baseline=3, growth=2.
      final h = SampleHistory()
        ..add(snap({}, 1))
        ..add(snap({'NewBloc': 3}, 2))
        ..add(snap({'NewBloc': 5}, 3));
      final report = const LeakAnalyzer(
        SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
      ).analyze(h, trigger: 'manual', status: LeakRadarStatus.active);
      expect(report.findings.length, 1);
      final f = report.findings.single;
      expect(f.className, 'NewBloc');
      expect(f.growth, 2); // 5 − 3
    },
  );

  test('precise findings are folded into the report', () {
    final h = SampleHistory()..add(snap({'X': 1}, 1));
    final precise = [
      const LeakFinding(
        className: 'CallSession',
        kind: LeakKind.notGced,
        severity: LeakSeverity.critical,
        liveCount: 1,
        growth: 0,
        tag: 'CallSession',
      ),
    ];
    final report = const LeakAnalyzer(SuspectSet.empty()).analyze(
      h,
      trigger: 'manual',
      status: LeakRadarStatus.active,
      preciseFindings: precise,
    );
    expect(report.findings.single.tag, 'CallSession');
    expect(report.worstSeverity, LeakSeverity.critical);
  });
}
