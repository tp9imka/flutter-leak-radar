import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarSparkline', () {
    testWidgets('renders without error with non-empty series',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarSparkline(series: [1, 3, 2, 5, 4]),
          ),
        ),
      );
      expect(find.byType(RadarSparkline), findsOneWidget);
    });

    testWidgets('renders without error with empty series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarSparkline(series: []),
          ),
        ),
      );
      expect(find.byType(RadarSparkline), findsOneWidget);
    });

    testWidgets('renders without error with single-point series',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarSparkline(series: [42]),
          ),
        ),
      );
      expect(find.byType(RadarSparkline), findsOneWidget);
    });

    testWidgets('defaults to spec size 52×16', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarSparkline(series: [1, 2, 3]),
          ),
        ),
      );
      final size = tester.getSize(find.byType(RadarSparkline));
      expect(size.width, 52.0);
      expect(size.height, 16.0);
    });
  });
}
