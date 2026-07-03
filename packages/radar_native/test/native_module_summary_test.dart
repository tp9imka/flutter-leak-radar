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
    final p = prof([
      cs([
        ['malloc', libc],
        ['a', flutter],
      ], 1000),
      cs([
        ['calloc', libc],
        ['b', flutter],
      ], 500),
      cs([
        ['malloc', libc],
        ['c', app],
      ], 4000),
    ]);
    final s = summarizeByModule(p);
    expect(s.map((e) => e.module).toList(), [
      'base.apk',
      'libflutter.so',
    ]); // bytes desc: 4000, 1500
    expect(s.first.kind, NativeModuleKind.app);
    expect(s.first.stillLiveBytes, 4000);
    expect(s[1].kind, NativeModuleKind.engine);
    expect(s[1].stillLiveBytes, 1500);
    expect(s[1].callsites, hasLength(2));
  });
  test(
    'empty profile -> empty',
    () => expect(summarizeByModule(prof(const [])), isEmpty),
  );
}
