import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

class _FakeRunner implements TraceProcessorRunner {
  _FakeRunner(this.rows);
  final List<PerfettoRow> rows;
  String? lastPath;
  @override
  Future<List<PerfettoRow>> query(String tracePath) async {
    lastPath = tracePath;
    return rows;
  }
}

void main() {
  test('facade runs the runner and maps rows into a checkpoint', () async {
    final rows = [
      PerfettoRow(
        callsiteId: 1,
        depth: 0,
        function: 'malloc',
        module: 'libc.so',
        allocBytes: 2048,
        allocCount: 2,
        freeBytes: 0,
        freeCount: 0,
      ),
    ];
    final fake = _FakeRunner(rows);
    final parser = PerfettoTraceProcessorParser(fake);
    final when = DateTime.utc(2026, 7, 3);
    final p = await parser.parseTrace(
      '/x/trace.pftrace',
      capturedAt: when,
      label: 'before',
      meta: const NativeProfileMeta(package: 'com.katim.leak_lab'),
    );
    expect(fake.lastPath, '/x/trace.pftrace');
    expect(p.label, 'before');
    expect(p.capturedAt, when);
    expect(p.meta.package, 'com.katim.leak_lab');
    expect(p.totalStillLiveBytes, 2048);
  });
}
