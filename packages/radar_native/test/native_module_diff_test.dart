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
  const gpu = '/vendor/lib64/egl/libGLESv2_adreno.so';

  test('joins per-module rollups: grew/gone/added, sorted by |delta|', () {
    final before = prof([
      cs([
        ['malloc', libc],
        ['a', app],
      ], 4000),
      cs([
        ['malloc', libc],
        ['b', flutter],
      ], 1500),
    ]);
    final after = prof([
      cs([
        ['malloc', libc],
        ['a', app],
      ], 6000),
      cs([
        ['malloc', libc],
        ['c', gpu],
      ], 2000),
    ]);

    final diff = diffModuleSummaries(before, after);

    // |Δ|: app 2000, gpuDriver 2000 (tie -> name asc), engine 1500 last.
    expect(diff.map((d) => d.module).toList(), [
      'base.apk',
      'libGLESv2_adreno.so',
      'libflutter.so',
    ]);

    final appDiff = diff[0];
    expect(appDiff.kind, NativeModuleKind.app);
    expect(appDiff.beforeStillLiveBytes, 4000);
    expect(appDiff.afterStillLiveBytes, 6000);
    expect(appDiff.deltaBytes, 2000);
    expect(appDiff.status, NativeDiffStatus.grew);

    final gpuDiff = diff[1];
    expect(gpuDiff.kind, NativeModuleKind.gpuDriver);
    expect(gpuDiff.beforeStillLiveBytes, 0);
    expect(gpuDiff.afterStillLiveBytes, 2000);
    expect(gpuDiff.deltaBytes, 2000);
    expect(gpuDiff.status, NativeDiffStatus.added);

    final engineDiff = diff[2];
    expect(engineDiff.module, 'libflutter.so');
    expect(engineDiff.kind, NativeModuleKind.engine);
    expect(engineDiff.beforeStillLiveBytes, 1500);
    expect(engineDiff.afterStillLiveBytes, 0);
    expect(engineDiff.deltaBytes, -1500);
    expect(engineDiff.status, NativeDiffStatus.gone);
  });

  test('module present in both with equal bytes is flat', () {
    final before = prof([
      cs([
        ['malloc', libc],
        ['a', app],
      ], 4000),
    ]);
    final after = prof([
      cs([
        ['malloc', libc],
        ['a', app],
      ], 4000),
    ]);
    final diff = diffModuleSummaries(before, after).single;
    expect(diff.deltaBytes, 0);
    expect(diff.status, NativeDiffStatus.flat);
  });

  test('empty on both sides -> empty', () {
    expect(diffModuleSummaries(prof(const []), prof(const [])), isEmpty);
  });
}
