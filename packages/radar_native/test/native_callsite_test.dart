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

  group('multi-frame signature (control-char delimiters)', () {
    NativeCallsite csFrames(List<NativeFrame> frames) => NativeCallsite(
      frames: frames,
      allocBytes: 0,
      allocCount: 0,
      freeBytes: 0,
      freeCount: 0,
    );

    test('identical multi-frame stacks produce equal signatures', () {
      final frames = [
        const NativeFrame(function: 'inner', module: 'libx.so'),
        const NativeFrame(function: 'outer', module: 'liby.so'),
      ];
      expect(csFrames(frames).signature, csFrames(List.of(frames)).signature);
    });

    test('same frames in a different order produce different signatures', () {
      const a = NativeFrame(function: 'inner', module: 'libx.so');
      const b = NativeFrame(function: 'outer', module: 'liby.so');
      expect(csFrames([a, b]).signature, isNot(csFrames([b, a]).signature));
    });

    test('symbols containing > and | do not collide across frame boundaries '
        '(the old >/| scheme would have collided here)', () {
      final single = csFrames([
        const NativeFrame(function: 'vector<int>::op|x>y', module: 'libx.so'),
      ]);
      final twoFrame = csFrames([
        const NativeFrame(function: 'vector<int>::op', module: 'libx.so'),
        const NativeFrame(function: 'y', module: 'x'),
      ]);

      // Sanity check: these DO collide under the old '>'/'|' scheme.
      String oldSignature(NativeCallsite c) =>
          c.frames.map((f) => '${f.module}>${f.function}').join('|');
      expect(oldSignature(single), oldSignature(twoFrame));

      // The hardened control-char scheme keeps them distinct.
      expect(single.signature, isNot(twoFrame.signature));
    });
  });
}
