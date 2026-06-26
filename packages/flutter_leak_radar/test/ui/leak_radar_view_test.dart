// packages/flutter_leak_radar/test/ui/leak_radar_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeakRadarView', () {
    testWidgets('renders inside a Scaffold without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LeakRadarView())),
      );
      expect(find.byType(LeakRadarView), findsOneWidget);
    });

    testWidgets('shows no-leaks empty state when engine is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LeakRadarView())),
      );
      expect(find.text('No leaks detected'), findsOneWidget);
    });

    testWidgets('LeakRadarScreen still works after refactor', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Leak Radar'), findsOneWidget);
    });
  });
}
