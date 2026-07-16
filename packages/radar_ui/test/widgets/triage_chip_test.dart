// test/widgets/triage_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('TriageChip', () {
    testWidgets('fresh renders NEW', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TriageChip(display: TriageDisplay.fresh)),
        ),
      );
      expect(find.text('NEW'), findsOneWidget);
    });

    testWidgets('known renders KNOWN', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TriageChip(display: TriageDisplay.known)),
        ),
      );
      expect(find.text('KNOWN'), findsOneWidget);
    });

    testWidgets('acknowledged renders ACK', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TriageChip(display: TriageDisplay.acknowledged)),
        ),
      );
      expect(find.text('ACK'), findsOneWidget);
    });

    testWidgets('gone renders GONE in the accent family', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TriageChip(display: TriageDisplay.gone)),
        ),
      );
      expect(find.text('GONE'), findsOneWidget);
      final text = tester.widget<Text>(find.text('GONE'));
      expect(text.style?.color, RadarColors.accent);
    });
  });
}
