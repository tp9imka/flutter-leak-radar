// test/widgets/origin_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('OriginChip', () {
    testWidgets('renders the project label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OriginChip(origin: RadarOrigin.project)),
        ),
      );
      expect(find.text('YOURS'), findsOneWidget);
    });

    testWidgets('project chip paints violet, not accent', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OriginChip(origin: RadarOrigin.project)),
        ),
      );
      final text = tester.widget<Text>(find.text('YOURS'));
      expect(text.style?.color, RadarColors.violet);
      expect(text.style?.color, isNot(RadarColors.accent));
    });

    testWidgets('renders the dependency label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OriginChip(origin: RadarOrigin.dependency)),
        ),
      );
      expect(find.text('DEPENDENCY'), findsOneWidget);
    });

    testWidgets('renders the em dash for unknown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OriginChip(origin: RadarOrigin.unknown)),
        ),
      );
      expect(find.text('—'), findsOneWidget);
    });
  });
}
