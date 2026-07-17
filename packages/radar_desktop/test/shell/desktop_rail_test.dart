import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/app/desktop_view.dart';
import 'package:radar_desktop/src/shell/desktop_rail.dart';
import 'package:radar_ui/radar_ui.dart';

Future<void> _pump(
  WidgetTester tester, {
  GlobalKey? memoryGroupKey,
  GlobalKey? performanceGroupKey,
  GlobalKey? stabilityGroupKey,
  GlobalKey? androidGroupKey,
  GlobalKey? toolsGroupKey,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(
        body: DesktopRail(
          current: DesktopView.dumps,
          connected: true,
          onSelect: (_) {},
          memoryGroupKey: memoryGroupKey,
          performanceGroupKey: performanceGroupKey,
          stabilityGroupKey: stabilityGroupKey,
          androidGroupKey: androidGroupKey,
          toolsGroupKey: toolsGroupKey,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('every anchor key resolves to a context when supplied', (
    tester,
  ) async {
    final memoryKey = GlobalKey();
    final performanceKey = GlobalKey();
    final stabilityKey = GlobalKey();
    final androidKey = GlobalKey();
    final toolsKey = GlobalKey();

    await _pump(
      tester,
      memoryGroupKey: memoryKey,
      performanceGroupKey: performanceKey,
      stabilityGroupKey: stabilityKey,
      androidGroupKey: androidKey,
      toolsGroupKey: toolsKey,
    );

    expect(memoryKey.currentContext, isNotNull);
    expect(performanceKey.currentContext, isNotNull);
    expect(stabilityKey.currentContext, isNotNull);
    expect(androidKey.currentContext, isNotNull);
    expect(toolsKey.currentContext, isNotNull);
  });

  testWidgets('renders identically when all anchor keys are null', (
    tester,
  ) async {
    await _pump(tester);

    for (final label in [
      'MEMORY',
      'PERFORMANCE',
      'STABILITY',
      'ANDROID NATIVE',
      'SETUP',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Dumps'), findsOneWidget);
  });
}
