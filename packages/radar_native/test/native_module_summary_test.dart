import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeCallsite cs(List<List<String>> fr, int alloc) => NativeCallsite(
  frames: [for (final f in fr) NativeFrame(function: f[0], module: f[1])],
  allocBytes: alloc,
  allocCount: 1,
  freeBytes: 0,
  freeCount: 0,
);

NativeHeapProfile prof(List<NativeCallsite> c) => NativeHeapProfile(
  capturedAt: DateTime.utc(2026, 7, 3),
  label: 'x',
  meta: const NativeProfileMeta(),
  callsites: c,
);

void main() {
  const libc = '/apex/com.android.runtime/lib64/bionic/libc.so';
  const flutter =
      '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so';
  const app = '/data/app/~~H==/com.katim.leak_lab-H==/base.apk';
  test('sums still-live per attributed module and tags kind', () {
    final csA = cs([
      ['malloc', libc],
      ['a', flutter],
    ], 1000);
    final csB = cs([
      ['calloc', libc],
      ['b', flutter],
    ], 500);
    final csC = cs([
      ['malloc', libc],
      ['c', app],
    ], 4000);
    final p = prof([csA, csB, csC]);
    final s = summarizeByModule(p);
    expect(s.map((e) => e.module).toList(), [
      'base.apk',
      'libflutter.so',
    ]); // bytes desc: 4000, 1500
    expect(s.first.kind, NativeModuleKind.app);
    expect(s.first.stillLiveBytes, 4000);
    expect(s[1].kind, NativeModuleKind.engine);
    expect(s[1].stillLiveBytes, 1500);
    // Not just count: the exact callsites, in first-seen order.
    expect(s[1].callsites, [csA, csB]);
  });
  test(
    'empty profile -> empty',
    () => expect(summarizeByModule(prof(const [])), isEmpty),
  );
  test('tie on stillLiveBytes breaks by module name ascending', () {
    const liba = '/data/app/~~H==/com.x-H==/base.apk!liba.so';
    const libz = '/data/app/~~H==/com.x-H==/base.apk!libz.so';
    // Inserted libz before liba, so a plain first-seen order would fail
    // this assertion — only the ascending tie-break makes it pass.
    final p = prof([
      cs([
        ['malloc', libc],
        ['z', libz],
      ], 1000),
      cs([
        ['malloc', libc],
        ['a', liba],
      ], 1000),
    ]);
    final s = summarizeByModule(p);
    expect(s.map((e) => e.module).toList(), ['liba.so', 'libz.so']);
  });
  test('callsite with no frames groups under module "" as unknown', () {
    final p = prof([cs(const [], 500)]);
    final s = summarizeByModule(p);
    expect(s, hasLength(1));
    expect(s.single.module, '');
    expect(s.single.kind, NativeModuleKind.unknown);
    expect(s.single.stillLiveBytes, 500);
  });
}
