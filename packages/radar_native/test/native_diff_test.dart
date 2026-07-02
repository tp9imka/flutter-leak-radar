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
}
