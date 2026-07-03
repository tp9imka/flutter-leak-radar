import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeCallsite _cs(String fn, {required int live, int count = 1}) =>
    NativeCallsite(
      frames: [NativeFrame(function: fn, module: 'libx.so')],
      allocBytes: live,
      allocCount: count,
      freeBytes: 0,
      freeCount: 0,
    );

NativeHeapProfile _p(DateTime at, List<NativeCallsite> cs) => NativeHeapProfile(
  capturedAt: at,
  label: at.toIso8601String(),
  callsites: cs,
  meta: const NativeProfileMeta(),
);

void main() {
  final t0 = DateTime(2026, 1, 1, 9);
  final t1 = DateTime(2026, 1, 1, 13);

  test('ranks callsites by still-live growth, largest first', () {
    final before = _p(t0, [_cs('slow', live: 100), _cs('flat', live: 500)]);
    final after = _p(t1, [_cs('slow', live: 900), _cs('flat', live: 500)]);
    final diff = diffNativeProfiles(before, after);
    expect(diff.first.signature, _cs('slow', live: 0).signature); // grew 800
    expect(diff.first.growthBytes, 800);
    // 'flat' present with 0 growth, ordered after 'slow'.
    expect(diff.map((d) => d.growthBytes), [800, 0]);
  });

  test('a callsite new in after reads against a zero baseline', () {
    final before = _p(t0, [_cs('old', live: 100)]);
    final after = _p(t1, [_cs('old', live: 100), _cs('brandnew', live: 300)]);
    final diff = diffNativeProfiles(before, after);
    final n = diff.firstWhere((d) => d.frames.single.function == 'brandnew');
    expect(n.beforeStillLiveBytes, 0);
    expect(n.growthBytes, 300);
  });

  test('NativeAllocationDiff.fromJson(toJson()) round-trips all fields', () {
    final before = _p(t0, [_cs('leaky', live: 100, count: 2)]);
    final after = _p(t1, [_cs('leaky', live: 900, count: 5)]);
    final diff = diffNativeProfiles(before, after).single;

    final back = NativeAllocationDiff.fromJson(diff.toJson());

    expect(back.signature, diff.signature);
    expect(back.frames, hasLength(diff.frames.length));
    expect(back.frames.single.function, diff.frames.single.function);
    expect(back.frames.single.module, diff.frames.single.module);
    expect(back.beforeStillLiveBytes, diff.beforeStillLiveBytes);
    expect(back.afterStillLiveBytes, diff.afterStillLiveBytes);
    expect(back.beforeStillLiveCount, diff.beforeStillLiveCount);
    expect(back.afterStillLiveCount, diff.afterStillLiveCount);
    expect(back.growthBytes, diff.growthBytes);
  });

  test('includeRemoved surfaces before-only sites as gone rows', () {
    // before has sites A(1000) + B(500); after has A(1000) only.
    final before = NativeHeapProfile(
      capturedAt: DateTime.utc(2026, 7, 3),
      label: 'b',
      meta: const NativeProfileMeta(),
      callsites: [
        NativeCallsite(
          frames: const [NativeFrame(function: 'fa', module: 'libA.so')],
          allocBytes: 1000,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
        NativeCallsite(
          frames: const [NativeFrame(function: 'fb', module: 'libB.so')],
          allocBytes: 500,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
      ],
    );
    final after = NativeHeapProfile(
      capturedAt: DateTime.utc(2026, 7, 3, 1),
      label: 'a',
      meta: const NativeProfileMeta(),
      callsites: [
        NativeCallsite(
          frames: const [NativeFrame(function: 'fa', module: 'libA.so')],
          allocBytes: 1000,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
      ],
    );
    final without = diffNativeProfiles(before, after);
    // before-only site (fb/libB) must not surface without includeRemoved.
    final removedSignature = before.callsites.last.signature;
    expect(without.map((e) => e.signature), isNot(contains(removedSignature)));
    expect(without, hasLength(1)); // default: before-only dropped
    final with_ = diffNativeProfiles(before, after, includeRemoved: true);
    expect(with_, hasLength(2));
    final gone = with_.firstWhere((e) => e.afterStillLiveBytes == 0);
    expect(gone.beforeStillLiveBytes, 500);
    expect(gone.frames.single.module, 'libB.so'); // frames from `before`
    expect(gone.status, NativeDiffStatus.gone);
  });

  test('equal-growth rows are ordered deterministically by signature', () {
    // two new sites with identical growth must sort by signature ascending
    NativeCallsite cs(String fn) => NativeCallsite(
      frames: [NativeFrame(function: fn, module: 'm.so')],
      allocBytes: 100,
      allocCount: 1,
      freeBytes: 0,
      freeCount: 0,
    );
    final before = NativeHeapProfile(
      capturedAt: DateTime.utc(2026, 7, 3),
      label: 'b',
      meta: const NativeProfileMeta(),
      callsites: const [],
    );
    final after = NativeHeapProfile(
      capturedAt: DateTime.utc(2026, 7, 3, 1),
      label: 'a',
      meta: const NativeProfileMeta(),
      callsites: [cs('zzz'), cs('aaa')],
    );
    final out = diffNativeProfiles(before, after);
    expect(out.map((e) => e.frames.single.function).toList(), ['aaa', 'zzz']);
  });
}
