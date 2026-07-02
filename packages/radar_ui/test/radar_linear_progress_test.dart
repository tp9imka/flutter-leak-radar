import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  testWidgets('RadarLinearProgress renders and animates without error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 200, child: RadarLinearProgress()),
        ),
      ),
    );
    expect(find.byType(RadarLinearProgress), findsOneWidget);
    // Advance the animation a couple of frames; must not throw.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
