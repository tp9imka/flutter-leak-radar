// test/ui/export_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

LeakFinding _finding() => LeakFinding(
      className: 'TestBloc',
      kind: LeakKind.growth,
      severity: LeakSeverity.warning,
      liveCount: 3,
      growth: 1,
      series: const [2, 3],
      captureTimes: const [],
    );

Future<void> _installEngine() => LeakRadar.debugInstall(
      LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ),
    );

void main() {
  tearDown(() => LeakRadar.dispose());

  // ── Smoke ─────────────────────────────────────────────────────────────────

  testWidgets('LeakExportSheet renders title "Export findings"',
      (tester) async {
    await _installEngine();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeakExportSheet()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Export findings'), findsOneWidget);
  });

  // ── Format toggle ─────────────────────────────────────────────────────────

  testWidgets('format toggle shows JSON and Markdown segments',
      (tester) async {
    await _installEngine();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeakExportSheet()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('JSON'), findsOneWidget);
    expect(find.text('Markdown'), findsOneWidget);
  });

  testWidgets('Markdown is selected by default — share button shows .md',
      (tester) async {
    await _installEngine();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeakExportSheet()),
      ),
    );
    await tester.pumpAndSettle();
    // No report → button text is "Nothing to export yet", which is the
    // default. Confirm format is Markdown by checking button label state
    // after seeding a scan.
    await LeakRadar.scan();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeakExportSheet()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Share .md'), findsOneWidget);
  });

  testWidgets('tapping JSON segment changes preview without exception',
      (tester) async {
    await _installEngine();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeakExportSheet()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('share button label changes with format selection',
      (tester) async {
    await _installEngine();
    await LeakRadar.scan();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeakExportSheet()),
      ),
    );
    await tester.pumpAndSettle();
    // Default is Markdown.
    expect(find.text('Share .md'), findsOneWidget);

    // Switch to JSON.
    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();
    expect(find.text('Share .json'), findsOneWidget);
  });

  // ── Key ───────────────────────────────────────────────────────────────────

  testWidgets('share button has key export_share_btn', (tester) async {
    await _installEngine();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeakExportSheet()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('export_share_btn')),
      findsOneWidget,
    );
  });

  // ── Integration: opens from LeakRadarScreen ───────────────────────────────

  testWidgets('Export icon in LeakRadarScreen opens LeakExportSheet',
      (tester) async {
    await _installEngine();
    await tester.pumpWidget(
      const MaterialApp(home: LeakRadarScreen()),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    expect(find.byType(LeakExportSheet), findsOneWidget);
  });

  // ── Integration: opens from FindingDetailScreen ───────────────────────────

  testWidgets(
      'Share icon in FindingDetailScreen opens LeakExportSheet',
      (tester) async {
    await _installEngine();
    await tester.pumpWidget(
      MaterialApp(home: FindingDetailScreen(finding: _finding())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    expect(find.byType(LeakExportSheet), findsOneWidget);
  });
}
