import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

PerfettoRow row(
  int cid,
  int depth,
  String fn,
  String mod, {
  String? build,
  int ab = 0,
  int ac = 0,
  int fb = 0,
  int fc = 0,
  int? relPc,
}) => PerfettoRow(
  callsiteId: cid,
  depth: depth,
  function: fn,
  module: mod,
  buildId: build,
  allocBytes: ab,
  allocCount: ac,
  freeBytes: fb,
  freeCount: fc,
  relPc: relPc,
);

void main() {
  final when = DateTime.utc(2026, 7, 3);
  test('one callsite, multi-frame stack ordered leaf-first', () {
    final rows = [
      row(7, 2, '', 'base.apk', ab: 1024, ac: 2),
      row(7, 0, 'malloc', 'libc.so', ab: 1024, ac: 2, fb: 0, fc: 0),
      row(7, 1, 'flutter::Foo', 'libflutter.so', build: 'abc', ab: 1024, ac: 2),
    ]; // fed out of depth order; mapper must sort leaf-first itself
    final p = PerfettoProfileMapper(
      capturedAt: when,
    ).parse(rows, label: 'after');
    expect(p.label, 'after');
    expect(p.capturedAt, when);
    expect(p.callsites, hasLength(1));
    final c = p.callsites.single;
    expect(c.frames.map((f) => f.module).toList(), [
      'libc.so',
      'libflutter.so',
      'base.apk',
    ]); // leaf-first
    expect(c.frames[1].function, 'flutter::Foo');
    expect(c.frames[1].buildId, 'abc');
    expect(c.frames[2].function, ''); // unsymbolized stays empty
    expect(c.frames[2].buildId, isNull);
    expect(c.allocBytes, 1024);
    expect(c.stillLiveBytes, 1024); // alloc - free
  });

  test('alloc and free split; still-live subtracts', () {
    final rows = [
      row(1, 0, 'malloc', 'libc.so', ab: 4096, ac: 4, fb: 1024, fc: 1),
    ];
    final c = PerfettoProfileMapper(
      capturedAt: when,
    ).parse(rows).callsites.single;
    expect(c.allocBytes, 4096);
    expect(c.freeBytes, 1024);
    expect(c.stillLiveBytes, 3072);
    expect(c.stillLiveCount, 3);
  });

  test('multiple callsites become multiple NativeCallsites', () {
    final rows = [
      row(1, 0, 'malloc', 'libc.so', ab: 10),
      row(2, 0, 'calloc', 'libc.so', ab: 20),
    ];
    final p = PerfettoProfileMapper(capturedAt: when).parse(rows);
    expect(p.callsites, hasLength(2));
    expect(p.totalStillLiveBytes, 30);
  });

  test('empty rows -> empty profile', () {
    final p = PerfettoProfileMapper(capturedAt: when).parse(<PerfettoRow>[]);
    expect(p.callsites, isEmpty);
    expect(p.totalStillLiveBytes, 0);
  });

  test('meta is carried through', () {
    final p = PerfettoProfileMapper(
      capturedAt: when,
      meta: const NativeProfileMeta(
        pid: 42,
        package: 'com.x',
        samplingIntervalBytes: 4096,
      ),
    ).parse(<PerfettoRow>[]);
    expect(p.meta.pid, 42);
    expect(p.meta.package, 'com.x');
    expect(p.meta.samplingIntervalBytes, 4096);
  });

  group('PerfettoRow.fromCells', () {
    test('parses all 10 cells in column order', () {
      final r = PerfettoRow.fromCells([
        '7',
        '1',
        'flutter::Foo',
        'libflutter.so',
        'abc123',
        '1024',
        '2',
        '512',
        '1',
        '6699',
      ]);
      expect(r.callsiteId, 7);
      expect(r.depth, 1);
      expect(r.function, 'flutter::Foo');
      expect(r.module, 'libflutter.so');
      expect(r.buildId, 'abc123');
      expect(r.allocBytes, 1024);
      expect(r.allocCount, 2);
      expect(r.freeBytes, 512);
      expect(r.freeCount, 1);
      expect(r.relPc, 6699);
    });

    test('empty buildId cell maps to null', () {
      final r = PerfettoRow.fromCells([
        '1',
        '0',
        'malloc',
        'libc.so',
        '',
        '10',
        '1',
        '0',
        '0',
        '',
      ]);
      expect(r.buildId, isNull);
    });

    test('empty function/module cells pass through as empty strings', () {
      final r = PerfettoRow.fromCells([
        '1',
        '0',
        '',
        '',
        '',
        '0',
        '0',
        '0',
        '0',
        '',
      ]);
      expect(r.function, '');
      expect(r.module, '');
    });

    test('empty relPc cell maps to null', () {
      final r = PerfettoRow.fromCells([
        '1',
        '0',
        'malloc',
        'libc.so',
        '',
        '10',
        '1',
        '0',
        '0',
        '',
      ]);
      expect(r.relPc, isNull);
    });
  });

  group('mapper synthesizes 0x<hex> from relPc', () {
    test('name-less frame with relPc gets a 0x<hex> function', () {
      final c = PerfettoProfileMapper(
        capturedAt: when,
      ).parse([row(1, 0, '', 'libflutter.so', relPc: 0x1a2b)]).callsites.single;
      expect(c.frames.single.function, '0x1a2b');
    });

    test('named frame keeps its name even when relPc is present', () {
      final c = PerfettoProfileMapper(
        capturedAt: when,
      ).parse([row(1, 0, 'malloc', 'libc.so', relPc: 5)]).callsites.single;
      expect(c.frames.single.function, 'malloc');
    });

    test('name-less frame with no relPc stays empty', () {
      final c = PerfettoProfileMapper(
        capturedAt: when,
      ).parse([row(1, 0, '', 'base.apk')]).callsites.single;
      expect(c.frames.single.function, '');
    });
  });
}
