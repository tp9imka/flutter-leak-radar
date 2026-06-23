import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/ui/growth_sparkline.dart';

void main() {
  group('GrowthSparkline', () {
    testWidgets('renders without error for empty series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GrowthSparkline(series: [], width: 80, height: 24),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for single-point series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GrowthSparkline(series: [5], width: 80, height: 24),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for flat series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GrowthSparkline(
              series: [3, 3, 3, 3, 3],
              width: 80,
              height: 24,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for growing series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GrowthSparkline(
              series: [1, 2, 4, 7, 12],
              width: 120,
              height: 32,
              color: Colors.red,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('golden — growing series renders expected sparkline',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: GrowthSparkline(
                series: [1, 2, 4, 7, 12, 18],
                width: 120,
                height: 32,
                color: Colors.red,
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(GrowthSparkline),
        matchesGoldenFile('goldens/growth_sparkline_growing.png'),
      );
    });
  });
}
