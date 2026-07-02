import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

void main() {
  NativeCallsite cs(
    String fn, {
    int alloc = 0,
    int free = 0,
    int aC = 0,
    int fC = 0,
  }) => NativeCallsite(
    frames: [NativeFrame(function: fn, module: 'libfoo.so', buildId: 'abc')],
    allocBytes: alloc,
    allocCount: aC,
    freeBytes: free,
    freeCount: fC,
  );

  test('stillLive = alloc - free', () {
    final c = cs('leaky', alloc: 1000, free: 200, aC: 10, fC: 2);
    expect(c.stillLiveBytes, 800);
    expect(c.stillLiveCount, 8);
  });

  test('signature is stable + identifies the callsite', () {
    expect(cs('a').signature, cs('a').signature);
    expect(cs('a').signature, isNot(cs('b').signature));
  });

  test('NativeCallsite JSON round-trips', () {
    final c = cs('leaky', alloc: 1000, free: 200, aC: 10, fC: 2);
    final back = NativeCallsite.fromJson(c.toJson());
    expect(back.stillLiveBytes, 800);
    expect(back.frames.single.function, 'leaky');
    expect(back.frames.single.module, 'libfoo.so');
  });

  test('NativeFrame value equality', () {
    expect(
      const NativeFrame(function: 'f', module: 'm', buildId: 'b'),
      const NativeFrame(function: 'f', module: 'm', buildId: 'b'),
    );
  });
}
