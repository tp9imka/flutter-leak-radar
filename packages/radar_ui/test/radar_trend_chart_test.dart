import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  testWidgets('renders a multi-point series without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: RadarTrendChart(series: [15, 24, 42, 89]),
          ),
        ),
      ),
    );
    expect(find.byType(RadarTrendChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and single-point series do not throw', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 300,
                height: 120,
                child: RadarTrendChart(series: []),
              ),
              SizedBox(
                width: 300,
                height: 120,
                child: RadarTrendChart(series: [7]),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
