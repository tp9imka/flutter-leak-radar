// End-to-end test: writes a real C3-style session directory with the
// production SessionStore, then imports it through DeviceMonitorController's
// DEFAULT dart:io reader — proving the real file path (timeline + sibling
// meta), triage, and compare all work on real on-disk artifacts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/screens/device_monitor_controller.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_trace/radar_trace.dart';

/// A no-op lock: these single-writer tests never contend, so there is nothing
/// to serialise — [SessionStore] just needs *a* lock.
class _NoLock implements SessionLock {
  @override
  Future<T> guard<T>(Future<T> Function() body) => body();
}

MetricSeries _series(
  String unit, {
  required double start,
  required double slope,
  int n = 24,
}) => MetricSeries(
  name: 'metric',
  unit: unit,
  samples: [
    for (var i = 0; i < n; i++)
      MetricSample(tMicros: i * 15 * 1000000, value: start + slope * i),
  ],
);

SessionMeta _meta(String package) => SessionMeta(
  package: package,
  device: 'pixel-8',
  started: DateTime.utc(2026, 7, 1),
  intervalMicros: 15 * 1000000,
  durationMicros: 360 * 1000000,
  flushEveryMicros: 60 * 1000000,
).ended(DateTime.utc(2026, 7, 1, 0, 6), 'completed');

/// Writes a real C3-style session directory (`timeline.json` + `meta.json`)
/// using the production [SessionStore] writer.
Future<String> _writeSession(
  Directory root,
  String name, {
  required double nativeSlope,
}) async {
  final dir = Directory('${root.path}/$name')..createSync(recursive: true);
  final store = SessionStore(dir: dir.path, lock: _NoLock());
  await store.flushTimeline(
    TriageTimeline(
      columns: {
        TriageColumn.nativePssKb: _series(
          'kb',
          start: 40000,
          slope: nativeSlope,
        ),
        TriageColumn.threads: _series('count', start: 24, slope: 0),
      },
      marks: const [TriageMark(tMicros: 90000000, label: 'reconnect')],
    ),
  );
  await store.writeMeta(_meta('com.example.$name'));
  return store.timelineFile.path;
}

void main() {
  group('Device Monitor imports a real on-disk session dir', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('radar_c6_field'));
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'reads a real timeline.json + sibling meta.json via the default reader',
      () async {
        final beforePath = await _writeSession(
          root,
          'before',
          nativeSlope: 800,
        );

        // The default (dart:io) reader — the exact path the shell uses.
        final controller = DeviceMonitorController();
        addTearDown(controller.dispose);
        await controller.importPrimary(beforePath);

        expect(controller.state, MonitorState.ready);
        final analysis = controller.primary!;
        expect(analysis.kind, MonitorSourceKind.session);
        expect(analysis.label, 'before');
        // Provenance came from the sibling meta.json the real writer produced.
        expect(analysis.provenance?.package, 'com.example.before');
        expect(analysis.provenance?.line, contains('pixel-8'));
        expect(analysis.provenance?.line, contains('completed'));
        // The growing native PSS column reads a real growth verdict + bucket.
        final native = analysis.series.firstWhere(
          (s) => s.column == TriageColumn.nativePssKb,
        );
        expect(native.assessment.verdict, SeriesVerdict.monotonicGrowth);
        expect(analysis.bucket, TriageBucket.nativeMalloc);
        expect(analysis.marks.single.label, 'reconnect');
      },
    );

    test('compares two real session dirs via the C4 taxonomy', () async {
      final beforePath = await _writeSession(root, 'before', nativeSlope: 800);
      final afterPath = await _writeSession(root, 'after', nativeSlope: 0);

      final controller = DeviceMonitorController();
      addTearDown(controller.dispose);
      await controller.importPrimary(beforePath);
      await controller.importComparison(afterPath);

      final native = controller.compareColumnsList!.firstWhere(
        (c) => c.column == TriageColumn.nativePssKb,
      );
      // Grew before, flat after → the fix resolved the native leak.
      expect(native.transition, FixTransition.resolved);
    });
  });
}
