import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ci/radar_ci.dart';
import 'package:radar_desktop/src/screens/device_monitor_controller.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_trace/radar_trace.dart';

/// A file reader backed by an in-memory path→content map. Missing paths throw,
/// mirroring `File.readAsString` on an absent file.
class _FakeFiles {
  _FakeFiles(this._byPath);

  final Map<String, String> _byPath;

  Future<String> read(String path) async {
    final content = _byPath[path];
    if (content == null) {
      throw StateError('no such file: $path');
    }
    return content;
  }
}

/// A linear ramp of [n] samples spaced [stepSeconds] apart in [unit].
MetricSeries _ramp(
  String unit, {
  int n = 24,
  int stepSeconds = 15,
  double start = 1000,
  double slope = 120,
  int t0 = 0,
}) => MetricSeries(
  name: 'metric',
  unit: unit,
  samples: [
    for (var i = 0; i < n; i++)
      MetricSample(
        tMicros: t0 + i * stepSeconds * 1000000,
        value: start + slope * i,
      ),
  ],
);

/// A flat series (constant value) of [n] samples in [unit].
MetricSeries _flat(
  String unit, {
  int n = 24,
  int stepSeconds = 15,
  double value = 500,
  int t0 = 0,
}) => MetricSeries(
  name: 'metric',
  unit: unit,
  samples: [
    for (var i = 0; i < n; i++)
      MetricSample(tMicros: t0 + i * stepSeconds * 1000000, value: value),
  ],
);

String _timelineJson({required bool growing}) {
  final timeline = TriageTimeline(
    columns: {
      TriageColumn.javaHeapKb: growing ? _ramp('kb') : _flat('kb'),
      TriageColumn.threads: _flat('count', value: 12),
    },
    marks: const [TriageMark(tMicros: 60000000, label: 'reconnect')],
  );
  return jsonEncode(timeline.toJson());
}

String _runJson() {
  final doc = RadarRunDocument(
    metadata: RunMetadata(startedAt: DateTime.utc(2026, 7, 1)),
    series: [
      _ramp('bytes'),
      MetricSeries(
        name: 'dart.external',
        unit: 'bytes',
        samples: _flat('bytes', value: 2000).samples,
      ),
    ],
    checkpoints: const [
      RunCheckpoint(tMicros: 0, label: 'start', allocationTopN: {}),
      RunCheckpoint(tMicros: 120000000, label: 'end', allocationTopN: {}),
    ],
  );
  return jsonEncode(doc.toJson());
}

void main() {
  group('DeviceMonitorController import', () {
    test('imports a session timeline; series+verdict match triage()', () async {
      final files = _FakeFiles({
        '/s/before/timeline.json': _timelineJson(growing: true),
      });
      final controller = DeviceMonitorController(readFile: files.read);
      addTearDown(controller.dispose);

      await controller.importPrimary('/s/before/timeline.json');

      expect(controller.state, MonitorState.ready);
      final analysis = controller.primary!;
      expect(analysis.kind, MonitorSourceKind.session);

      // Reconstruct the ground-truth verdict and assert the analysis mirrors
      // it exactly — chips render straight off these assessments.
      final timeline = TriageTimeline.fromJson(
        jsonDecode(_timelineJson(growing: true)) as Map<String, Object?>,
      );
      final expected = triage(timeline, controller.options);
      expect(
        analysis.series.map((s) => s.column).toList(),
        expected.assessments.map((a) => a.column).toList(),
      );
      expect(
        analysis.series.map((s) => s.assessment).toList(),
        expected.assessments.map((a) => a.assessment).toList(),
      );
      expect(analysis.bucket, expected.bucket);
      expect(analysis.summary, expected.summary);
      // The growing java heap column produced a real growth verdict.
      final java = analysis.series.firstWhere(
        (s) => s.column == TriageColumn.javaHeapKb,
      );
      expect(java.assessment.verdict, SeriesVerdict.monotonicGrowth);
      // Marks + settle window are carried through for the chart.
      expect(analysis.marks.single.label, 'reconnect');
      expect(analysis.settleWindow, isNotNull);
    });

    test('reads sibling meta.json for provenance', () async {
      final files = _FakeFiles({
        '/s/run1/timeline.json': _timelineJson(growing: false),
        '/s/run1/meta.json': jsonEncode({
          'package': 'com.example.app',
          'device': 'pixel-8',
          'endReason': 'completed',
        }),
      });
      final controller = DeviceMonitorController(readFile: files.read);
      addTearDown(controller.dispose);

      await controller.importPrimary('/s/run1/timeline.json');

      expect(controller.primary!.provenance?.package, 'com.example.app');
      expect(controller.primary!.provenance?.line, contains('pixel-8'));
      // The label is the session directory name.
      expect(controller.primary!.label, 'run1');
    });

    test(
      'a session with no meta.json still imports (provenance null)',
      () async {
        final files = _FakeFiles({
          '/s/run2/timeline.json': _timelineJson(growing: false),
        });
        final controller = DeviceMonitorController(readFile: files.read);
        addTearDown(controller.dispose);

        await controller.importPrimary('/s/run2/timeline.json');

        expect(controller.state, MonitorState.ready);
        expect(controller.primary!.provenance, isNull);
      },
    );

    test(
      'imports a radar_ci run.json; maps its MetricSeries directly',
      () async {
        final files = _FakeFiles({'/runs/run.json': _runJson()});
        final controller = DeviceMonitorController(readFile: files.read);
        addTearDown(controller.dispose);

        await controller.importPrimary('/runs/run.json');

        expect(controller.state, MonitorState.ready);
        final analysis = controller.primary!;
        expect(analysis.kind, MonitorSourceKind.run);
        // One MonitorSeries per run.json series, assessed via assessSeries.
        expect(analysis.series.map((s) => s.label), [
          'metric',
          'dart.external',
        ]);
        expect(analysis.series.every((s) => s.column == null), isTrue);
        // Checkpoints become chart marks.
        expect(analysis.marks.map((m) => m.label), ['start', 'end']);
        // No Lane-A bucket for a Dart-VM run.
        expect(analysis.bucket, isNull);
        expect(analysis.summary, contains('radar_ci run'));
      },
    );

    test('a malformed (non-JSON) file → error state, no crash', () async {
      final files = _FakeFiles({'/bad/timeline.json': 'not json at all {{{'});
      final controller = DeviceMonitorController(readFile: files.read);
      addTearDown(controller.dispose);

      await controller.importPrimary('/bad/timeline.json');

      expect(controller.state, MonitorState.error);
      expect(controller.primary, isNull);
      expect(controller.errorMessage, isNotNull);
    });

    test('valid JSON of an unknown shape → honest error', () async {
      final files = _FakeFiles({
        '/x/thing.json': jsonEncode({'hello': 'world'}),
      });
      final controller = DeviceMonitorController(readFile: files.read);
      addTearDown(controller.dispose);

      await controller.importPrimary('/x/thing.json');

      expect(controller.state, MonitorState.error);
      expect(controller.errorMessage, contains('unrecognized'));
    });

    test(
      'a newer-schema timeline surfaces the parser error, never a render',
      () async {
        final files = _FakeFiles({
          '/x/timeline.json': jsonEncode({
            'schemaVersion': 999,
            'columns': <String, Object?>{},
            'marks': <Object?>[],
          }),
        });
        final controller = DeviceMonitorController(readFile: files.read);
        addTearDown(controller.dispose);

        await controller.importPrimary('/x/timeline.json');

        expect(controller.state, MonitorState.error);
        expect(controller.errorMessage, contains('schemaVersion'));
        expect(controller.primary, isNull);
      },
    );
  });

  group('DeviceMonitorController compare', () {
    test(
      'a second session enables the compare table via the C4 taxonomy',
      () async {
        final files = _FakeFiles({
          '/s/before/timeline.json': _timelineJson(growing: true),
          '/s/after/timeline.json': _timelineJson(growing: false),
        });
        final controller = DeviceMonitorController(readFile: files.read);
        addTearDown(controller.dispose);

        await controller.importPrimary('/s/before/timeline.json');
        expect(controller.canCompare, isTrue);
        await controller.importComparison('/s/after/timeline.json');

        expect(controller.comparison, isNotNull);
        final columns = controller.compareColumnsList!;
        final java = columns.firstWhere(
          (c) => c.column == TriageColumn.javaHeapKb,
        );
        // Grew before, flat after → the fix resolved it.
        expect(java.transition, FixTransition.resolved);
      },
    );

    test(
      'importing a fresh primary invalidates the prior comparison',
      () async {
        final files = _FakeFiles({
          '/s/before/timeline.json': _timelineJson(growing: true),
          '/s/after/timeline.json': _timelineJson(growing: false),
        });
        final controller = DeviceMonitorController(readFile: files.read);
        addTearDown(controller.dispose);

        await controller.importPrimary('/s/before/timeline.json');
        await controller.importComparison('/s/after/timeline.json');
        expect(controller.comparison, isNotNull);

        await controller.importPrimary('/s/after/timeline.json');
        expect(controller.comparison, isNull);
      },
    );

    test(
      'comparing a run.json is refused without destroying the primary',
      () async {
        final files = _FakeFiles({
          '/s/before/timeline.json': _timelineJson(growing: true),
          '/runs/run.json': _runJson(),
        });
        final controller = DeviceMonitorController(readFile: files.read);
        addTearDown(controller.dispose);

        await controller.importPrimary('/s/before/timeline.json');
        await controller.importComparison('/runs/run.json');

        // Primary survives; the comparison is refused with an honest message.
        expect(controller.primary, isNotNull);
        expect(controller.comparison, isNull);
        expect(controller.comparisonError, isNotNull);
      },
    );
  });
}
