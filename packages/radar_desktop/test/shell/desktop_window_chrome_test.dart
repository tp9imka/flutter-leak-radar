import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/shell/desktop_window_chrome.dart';
import 'package:radar_ui/radar_ui.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool anyToolMissing = false,
  int missingToolCount = 0,
  VoidCallback? onOpenTools,
  VoidCallback? onReopenGuide,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(
        body: DesktopWindowChrome(
          workspaceName: 'untitled workspace',
          anyToolMissing: anyToolMissing,
          missingToolCount: missingToolCount,
          onOpenTools: onOpenTools,
          onReopenGuide: onReopenGuide,
        ),
      ),
    ),
  );
}

Color _dotColor(WidgetTester tester) {
  final decoratedBox = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(Tooltip),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (decoratedBox.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('the health dot is accent when no tool is missing', (
    tester,
  ) async {
    await _pump(tester, anyToolMissing: false);

    expect(_dotColor(tester), RadarColors.accent);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'All tools present');
  });

  testWidgets('the health dot is amber when any tool is missing', (
    tester,
  ) async {
    await _pump(tester, anyToolMissing: true, missingToolCount: 2);

    expect(_dotColor(tester), RadarColors.warning);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, '2 tool(s) missing');
  });

  testWidgets('tapping the health dot invokes onOpenTools', (tester) async {
    var opened = 0;
    await _pump(tester, anyToolMissing: true, onOpenTools: () => opened++);

    await tester.tap(find.byType(Tooltip));
    // The dot sits inside `DragToMoveArea`, whose `onDoubleTap` also
    // enters the gesture arena — a single tap only resolves once that
    // recognizer's double-tap wait window elapses.
    await tester.pump(kDoubleTapTimeout);

    expect(opened, 1);
  });

  testWidgets('the reopen-guide button shows when onReopenGuide is set', (
    tester,
  ) async {
    await _pump(tester, onReopenGuide: () {});

    expect(find.byTooltip('Show guide'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('tapping the reopen-guide button invokes onReopenGuide', (
    tester,
  ) async {
    var reopened = 0;
    await _pump(tester, onReopenGuide: () => reopened++);

    await tester.tap(find.byTooltip('Show guide'));
    // Same double-tap arena caveat as the health dot above: the button
    // sits inside `DragToMoveArea`.
    await tester.pump(kDoubleTapTimeout);

    expect(reopened, 1);
  });

  testWidgets('no reopen-guide button when onReopenGuide is null', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byTooltip('Show guide'), findsNothing);
  });
}
