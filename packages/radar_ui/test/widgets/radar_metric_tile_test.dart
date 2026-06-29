// test/widgets/radar_metric_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarMetricTile', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarMetricTile(label: 'Live now', value: '42'),
          ),
        ),
      );
      expect(find.text('Live now'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('critical severity colors the value text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarMetricTile(
              label: 'Jank',
              value: '17',
              severity: RadarSeverity.critical,
            ),
          ),
        ),
      );
      final valueText = tester.widget<Text>(find.text('17'));
      expect(valueText.style?.color, RadarColors.critical);
    });

    testWidgets('healthy severity colors the value text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarMetricTile(
              label: 'Status',
              value: '0',
              severity: RadarSeverity.healthy,
            ),
          ),
        ),
      );
      final valueText = tester.widget<Text>(find.text('0'));
      expect(valueText.style?.color, RadarColors.accent);
    });

    testWidgets('explicit color overrides severity', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarMetricTile(
              label: 'Total',
              value: '999',
              color: RadarColors.info,
            ),
          ),
        ),
      );
      final valueText = tester.widget<Text>(find.text('999'));
      expect(valueText.style?.color, RadarColors.info);
    });
  });
}
