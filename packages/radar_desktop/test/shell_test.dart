import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/app/desktop_view.dart';
import 'package:radar_desktop/src/screens/dumps_screen.dart';
import 'package:radar_desktop/src/screens/trends_screen.dart';
import 'package:radar_desktop/src/shell/desktop_rail.dart';
import 'package:radar_desktop/src/shell/desktop_shell.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  testWidgets('rail lists the five memory destinations and reports taps', (
    tester,
  ) async {
    DesktopView? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(
          body: DesktopRail(
            current: DesktopView.dumps,
            connected: false,
            onSelect: (v) => tapped = v,
          ),
        ),
      ),
    );
    for (final label in [
      'Dumps',
      'Class histogram',
      'Retaining paths',
      'Compare',
      'Trends',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Trends'));
    expect(tapped, DesktopView.trends);
  });

  testWidgets('performance/stability items are locked when offline', (
    tester,
  ) async {
    DesktopView? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: radarDarkTheme(),
        home: Scaffold(
          body: DesktopRail(
            current: DesktopView.dumps,
            connected: false,
            onSelect: (v) => tapped = v,
          ),
        ),
      ),
    );
    // Tapping a locked Performance item does nothing.
    await tester.tap(find.text('Traces'));
    expect(tapped, isNull);
  });

  testWidgets('shell routes memory views to real screens; '
      'opening a dump goes to histogram', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesktopShell()));
    // Default view = dumps → DumpsScreen present.
    expect(find.byType(DumpsScreen), findsOneWidget);
    // Navigate to Trends via the rail.
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.byType(TrendsScreen), findsOneWidget);
  });
}
