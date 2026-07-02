import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

void main() {
  NativeCallsite cs(String fn, {int alloc = 0, int free = 0}) => NativeCallsite(
    frames: [NativeFrame(function: fn, module: 'libfoo.so')],
    allocBytes: alloc,
    allocCount: 1,
    freeBytes: free,
    freeCount: 0,
  );

  test('totalStillLiveBytes sums callsite still-live', () {
    final profile = NativeHeapProfile(
      capturedAt: DateTime.utc(2026, 7, 3, 12),
      label: 'after',
      callsites: [
        cs('leaky_a', alloc: 1000, free: 200),
        cs('leaky_b', alloc: 500, free: 500),
      ],
      meta: const NativeProfileMeta(
        pid: 1234,
        package: 'com.example.app',
        samplingIntervalBytes: 4096,
      ),
    );

    expect(profile.totalStillLiveBytes, 800);
  });

  test('toJson carries a version envelope', () {
    final profile = NativeHeapProfile(
      capturedAt: DateTime.utc(2026, 7, 3, 12),
      label: 'after',
      callsites: [cs('leaky_a', alloc: 1000, free: 200)],
      meta: const NativeProfileMeta(),
    );

    expect(profile.toJson()['version'], 1);
  });

  test('fromJson(toJson()) round-trips callsites + meta', () {
    final profile = NativeHeapProfile(
      capturedAt: DateTime.utc(2026, 7, 3, 12, 30),
      label: 'before',
      callsites: [
        cs('leaky_a', alloc: 1000, free: 200),
        cs('leaky_b', alloc: 500, free: 500),
      ],
      meta: const NativeProfileMeta(
        pid: 1234,
        package: 'com.example.app',
        samplingIntervalBytes: 4096,
      ),
    );

    final back = NativeHeapProfile.fromJson(profile.toJson());

    expect(back.capturedAt, profile.capturedAt);
    expect(back.label, 'before');
    expect(back.totalStillLiveBytes, 800);
    expect(back.callsites, hasLength(2));
    expect(back.callsites[0].frames.single.function, 'leaky_a');
    expect(back.meta.pid, 1234);
    expect(back.meta.package, 'com.example.app');
    expect(back.meta.samplingIntervalBytes, 4096);
  });

  test('fromJson tolerates a missing version + missing meta', () {
    final json = <String, Object?>{
      'capturedAt': DateTime.utc(2026, 7, 3).toIso8601String(),
      'label': 'legacy',
      'callsites': <Object?>[],
    };

    final profile = NativeHeapProfile.fromJson(json);

    expect(profile.label, 'legacy');
    expect(profile.callsites, isEmpty);
    expect(profile.meta.pid, isNull);
  });
}
