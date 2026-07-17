import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ci/radar_ci.dart';
import 'package:radar_desktop/src/screens/device_monitor_controller.dart';
import 'package:radar_desktop/src/screens/device_monitor_screen.dart';
import 'package:radar_desktop/src/screens/live_memory_controller.dart';
import 'package:radar_desktop/src/seams/desktop_memory_poll.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:radar_ui/radar_ui.dart';

class _FakeFiles {
  _FakeFiles(this._byPath);
  final Map<String, String> _byPath;
  Future<String> read(String path) async {
    final content = _byPath[path];
    if (content == null) throw StateError('no such file: $path');
    return content;
  }
}

MetricSeries _ramp(String unit, {int n = 24, double slope = 120}) =>
    MetricSeries(
      name: 'metric',
      unit: unit,
      samples: [
        for (var i = 0; i < n; i++)
          MetricSample(tMicros: i * 15 * 1000000, value: 1000 + slope * i),
      ],
    );

MetricSeries _flat(String unit, {int n = 24, double value = 500}) =>
    MetricSeries(
      name: 'metric',
      unit: unit,
      samples: [
        for (var i = 0; i < n; i++)
          MetricSample(tMicros: i * 15 * 1000000, value: value),
      ],
    );

String _timelineJson({required bool growing}) => jsonEncode(
  TriageTimeline(
    columns: {
      TriageColumn.javaHeapKb: growing ? _ramp('kb') : _flat('kb'),
      TriageColumn.threads: _flat('count', value: 12),
    },
    marks: const [TriageMark(tMicros: 60000000, label: 'reconnect')],
  ).toJson(),
);

String _runJson() => jsonEncode(
  RadarRunDocument(
    metadata: RunMetadata(startedAt: DateTime.utc(2026, 7, 1)),
    series: [_ramp('bytes')],
    checkpoints: const [
      RunCheckpoint(tMicros: 0, label: 'start', allocationTopN: {}),
    ],
  ).toJson(),
);

Widget _host(Widget child) => MaterialApp(
  home: Theme(
    data: radarDarkTheme(),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('a session import renders chart, chips, and router summary', (
    tester,
  ) async {
    final files = _FakeFiles({
      '/s/soak/timeline.json': _timelineJson(growing: true),
    });
    final controller = DeviceMonitorController(readFile: files.read);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(DeviceMonitorScreen(controller: controller)));
    await controller.importPrimary('/s/soak/timeline.json');
    await tester.pump();

    expect(find.byType(RadarTimeSeriesChart), findsOneWidget);
    // The growing java heap column reads a GROWTH verdict chip.
    expect(find.text('GROWTH'), findsWidgets);
    // The router summary banner names the growth.
    expect(find.textContaining('growing'), findsOneWidget);
    // Batch-delta readout present.
    expect(find.textContaining('Batch delta'), findsOneWidget);
  });

  testWidgets('a radar_ci run import renders a chart and run summary', (
    tester,
  ) async {
    final files = _FakeFiles({'/runs/run.json': _runJson()});
    final controller = DeviceMonitorController(readFile: files.read);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(DeviceMonitorScreen(controller: controller)));
    await controller.importPrimary('/runs/run.json');
    await tester.pump();

    expect(find.byType(RadarTimeSeriesChart), findsOneWidget);
    expect(find.textContaining('radar_ci run'), findsOneWidget);
    // A run.json is not a native session, so no compare affordance.
    expect(find.text('Add second session…'), findsNothing);
  });

  testWidgets('a malformed file shows an error panel and never a chart', (
    tester,
  ) async {
    final files = _FakeFiles({'/bad/timeline.json': 'not json {{{'});
    final controller = DeviceMonitorController(readFile: files.read);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(DeviceMonitorScreen(controller: controller)));
    await controller.importPrimary('/bad/timeline.json');
    await tester.pump();

    expect(find.textContaining("Couldn't import"), findsOneWidget);
    expect(find.byType(RadarTimeSeriesChart), findsNothing);
  });

  testWidgets('a second session renders the compare table', (tester) async {
    final files = _FakeFiles({
      '/s/before/timeline.json': _timelineJson(growing: true),
      '/s/after/timeline.json': _timelineJson(growing: false),
    });
    final controller = DeviceMonitorController(readFile: files.read);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(DeviceMonitorScreen(controller: controller)));
    await controller.importPrimary('/s/before/timeline.json');
    await controller.importComparison('/s/after/timeline.json');
    await tester.pump();

    // The grew-then-flat java heap column resolves.
    expect(find.text('RESOLVED'), findsOneWidget);
    expect(find.text('outcome'), findsOneWidget);
  });

  testWidgets('the live tab renders two separate series when connected', (
    tester,
  ) async {
    final samples = <MemorySample>[
      (heapUsage: 100, externalUsage: 10),
      (heapUsage: 140, externalUsage: 12),
    ];
    var i = 0;
    var clock = 0;
    final live = LiveMemoryController(
      poll: () async => samples[i++],
      clock: () => clock,
    );
    addTearDown(live.dispose);
    await live.pollOnce();
    clock += 1000000;
    await live.pollOnce();

    final controller = DeviceMonitorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        DeviceMonitorScreen(
          controller: controller,
          live: live,
          connected: true,
        ),
      ),
    );

    // Switch to the Live tab.
    await tester.tap(find.text('Live'));
    await tester.pump();

    expect(find.byType(RadarTimeSeriesChart), findsOneWidget);
    // Both series are legended separately — never merged.
    expect(find.text('heap'), findsOneWidget);
    expect(find.text('external'), findsOneWidget);
    expect(find.textContaining('2 samples'), findsOneWidget);
  });

  testWidgets('the live tab is locked and shows a prompt while offline', (
    tester,
  ) async {
    final controller = DeviceMonitorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(DeviceMonitorScreen(controller: controller)));

    // Tapping the disabled Live tab does nothing; the import prompt stays.
    await tester.tap(find.text('Live'));
    await tester.pump();
    expect(find.textContaining('Import a native session'), findsOneWidget);
  });

  group('layout width', () {
    for (final width in [800.0, 722.0, 1280.0]) {
      testWidgets('no overflow at ${width.toInt()}px (ready + compare)', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final files = _FakeFiles({
          '/s/before/timeline.json': _timelineJson(growing: true),
          '/s/after/timeline.json': _timelineJson(growing: false),
        });
        final controller = DeviceMonitorController(readFile: files.read);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _host(DeviceMonitorScreen(controller: controller)),
        );
        await controller.importPrimary('/s/before/timeline.json');
        await controller.importComparison('/s/after/timeline.json');
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(RadarTimeSeriesChart), findsOneWidget);
      });
    }
  });
}
