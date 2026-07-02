import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeHeapProfile _profile(DateTime at, String label) => NativeHeapProfile(
  capturedAt: at,
  label: label,
  callsites: const [],
  meta: const NativeProfileMeta(),
);

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 9);
  final t1 = DateTime.utc(2026, 1, 1, 10);
  final t2 = DateTime.utc(2026, 1, 1, 11);

  test('timeline sorts both lanes by capturedAt and tags kind', () {
    final session = MemorySession(
      label: 'repro',
      nativeProfiles: [_profile(t2, 'after'), _profile(t0, 'before')],
      dartRefs: [
        DartAnalysisRef(bundleId: 1, label: 'mid-dump', capturedAt: t1),
      ],
    );

    final timeline = session.timeline;

    expect(timeline, hasLength(3));
    expect(timeline.map((e) => e.at), [t0, t1, t2]);
    expect(timeline.map((e) => e.kind), ['native', 'dart', 'native']);
    expect(timeline.map((e) => e.label), ['before', 'mid-dump', 'after']);
  });

  test('fromJson(toJson()) round-trips native profiles + dart refs', () {
    final session = MemorySession(
      label: 'repro',
      nativeProfiles: [_profile(t0, 'before'), _profile(t2, 'after')],
      dartRefs: [
        DartAnalysisRef(bundleId: 7, label: 'mid-dump', capturedAt: t1),
      ],
    );

    final json = session.toJson();
    expect(json['version'], 1);

    final back = MemorySession.fromJson(json);

    expect(back.label, 'repro');
    expect(back.nativeProfiles, hasLength(2));
    expect(back.nativeProfiles[0].label, 'before');
    expect(back.nativeProfiles[1].label, 'after');
    expect(back.dartRefs, hasLength(1));
    expect(back.dartRefs.single.bundleId, 7);
    expect(back.dartRefs.single.label, 'mid-dump');
    expect(back.dartRefs.single.capturedAt, t1);
  });
}
