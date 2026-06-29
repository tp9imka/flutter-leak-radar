// test/widgets/radar_tag_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarTag', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarTag(label: 'NOT DISPOSED'),
          ),
        ),
      );
      expect(find.text('NOT DISPOSED'), findsOneWidget);
    });

    testWidgets('critical severity uses critical color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarTag(
              label: 'CRITICAL',
              severity: RadarSeverity.critical,
            ),
          ),
        ),
      );

      // The tag must paint with the critical text color.
      final text = tester.widget<Text>(find.text('CRITICAL'));
      expect(text.style?.color, RadarColors.critical);
    });

    testWidgets('warning severity uses warning color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarTag(
              label: 'HOT',
              severity: RadarSeverity.warning,
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('HOT'));
      expect(text.style?.color, RadarColors.warning);
    });

    testWidgets('explicit color overrides severity', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarTag(
              label: 'CUSTOM',
              color: RadarColors.info,
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('CUSTOM'));
      expect(text.style?.color, RadarColors.info);
    });
  });
}
