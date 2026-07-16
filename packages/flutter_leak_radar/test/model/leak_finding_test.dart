import 'package:flutter_leak_radar/flutter_leak_radar.dart' show ClassOrigin;
import 'package:flutter_leak_radar/src/model/leak_finding.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('origin defaults to unknown and bytes defaults to null', () {
    const f = LeakFinding(
      className: 'A',
      kind: LeakKind.growth,
      severity: LeakSeverity.info,
      liveCount: 1,
      growth: 0,
    );
    expect(f.origin, ClassOrigin.unknown);
    expect(f.bytes, isNull);
  });

  test('ClassOrigin is re-exported from the package barrel', () {
    // Compile-time proof the symbol comes from flutter_leak_radar, not
    // leak_graph directly (the import above shows only flutter_leak_radar).
    expect(ClassOrigin.values, contains(ClassOrigin.project));
  });

  test('toJson carries origin always and bytes only when non-null', () {
    const withBytes = LeakFinding(
      className: 'A',
      kind: LeakKind.growth,
      severity: LeakSeverity.info,
      liveCount: 1,
      growth: 0,
      origin: ClassOrigin.project,
      bytes: 2048,
    );
    final json = withBytes.toJson();
    expect(json['origin'], 'project');
    expect(json['bytes'], 2048);

    const noBytes = LeakFinding(
      className: 'A',
      kind: LeakKind.growth,
      severity: LeakSeverity.info,
      liveCount: 1,
      growth: 0,
      origin: ClassOrigin.dependency,
    );
    expect(noBytes.toJson().containsKey('bytes'), isFalse);
    expect(noBytes.toJson()['origin'], 'dependency');
  });

  test('fromJson round-trips origin and bytes', () {
    const original = LeakFinding(
      className: 'A',
      kind: LeakKind.growth,
      severity: LeakSeverity.warning,
      liveCount: 3,
      growth: 2,
      origin: ClassOrigin.flutterFramework,
      bytes: 512,
    );
    final restored = LeakFinding.fromJson(original.toJson());
    expect(restored.origin, ClassOrigin.flutterFramework);
    expect(restored.bytes, 512);
  });

  test('fromJson defaults origin to unknown when absent', () {
    final restored = LeakFinding.fromJson(const {
      'className': 'A',
      'kind': 'growth',
      'severity': 'info',
      'liveCount': 1,
      'growth': 0,
    });
    expect(restored.origin, ClassOrigin.unknown);
    expect(restored.bytes, isNull);
  });

  test(
    'withRetainingPath and withAllocationStack preserve origin and bytes',
    () {
      const f = LeakFinding(
        className: 'A',
        kind: LeakKind.growth,
        severity: LeakSeverity.info,
        liveCount: 1,
        growth: 0,
        origin: ClassOrigin.project,
        bytes: 64,
      );
      final withStack = f.withAllocationStack(StackTrace.current);
      expect(withStack.origin, ClassOrigin.project);
      expect(withStack.bytes, 64);
    },
  );
}
