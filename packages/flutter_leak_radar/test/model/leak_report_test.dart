import 'package:flutter_leak_radar/src/model/leak_finding.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';
import 'package:flutter_test/flutter_test.dart';

LeakFinding finding(String name, LeakSeverity sev) => LeakFinding(
  className: name,
  kind: LeakKind.growth,
  severity: sev,
  liveCount: 3,
  growth: 2,
  series: const [1, 2, 3],
);

void main() {
  test('worstSeverity is info for empty findings', () {
    final r = LeakReport(
      findings: const [],
      capturedAt: DateTime(2026),
      trigger: 'manual',
      status: LeakRadarStatus.active,
    );
    expect(r.hasLeaks, false);
    expect(r.worstSeverity, LeakSeverity.info);
  });

  test('worstSeverity is the max over findings', () {
    final r = LeakReport(
      findings: [
        finding('A', LeakSeverity.warning),
        finding('B', LeakSeverity.critical),
      ],
      capturedAt: DateTime(2026),
      trigger: 'manual',
      status: LeakRadarStatus.active,
    );
    expect(r.hasLeaks, true);
    expect(r.worstSeverity, LeakSeverity.critical);
  });

  test('toJson round-trips finding count and toMarkdown lists class names', () {
    final r = LeakReport(
      findings: [finding('HomeBloc', LeakSeverity.critical)],
      capturedAt: DateTime(2026, 1, 2),
      trigger: 'manual',
      status: LeakRadarStatus.active,
      heapBytes: 1024,
    );
    final json = r.toJson();
    expect((json['findings'] as List).length, 1);
    expect(json['trigger'], 'manual');
    expect(r.toMarkdown(), contains('HomeBloc'));
  });

  test('equality by value', () {
    final a = finding('X', LeakSeverity.info);
    final b = finding('X', LeakSeverity.info);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
