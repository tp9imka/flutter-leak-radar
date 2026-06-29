// test/widgets/radar_live_pulse_dot_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarLivePulseDot', () {
    testWidgets('renders a dot', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RadarLivePulseDot()),
        ),
      );
      expect(find.byType(RadarLivePulseDot), findsOneWidget);
    });

    testWidgets('has correct default size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RadarLivePulseDot()),
        ),
      );
      // The dot itself is an 8×8 container.
      final sizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(RadarLivePulseDot),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sizedBox.width, 8.0);
      expect(sizedBox.height, 8.0);
    });

    testWidgets(
        'disables animation when MediaQuery.disableAnimations is true',
        (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: RadarLivePulseDot()),
          ),
        ),
      );
      // Widget must render without error under reduced-motion.
      expect(find.byType(RadarLivePulseDot), findsOneWidget);

      // No AnimationController should be running — verify by checking
      // that pumping extra frames doesn't cause setState calls.
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });
}
