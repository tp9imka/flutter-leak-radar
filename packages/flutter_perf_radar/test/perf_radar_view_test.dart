// packages/flutter_perf_radar/test/perf_radar_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerfRadarView', () {
    testWidgets('renders inside a Scaffold without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // TabBar requires a DefaultTabController ancestor
                // PerfRadarView owns its own DefaultTabController
                Expanded(child: PerfRadarView()),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(PerfRadarView), findsOneWidget);
    });

    testWidgets('shows Spans tab label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      expect(find.text('Spans'), findsOneWidget);
    });

    testWidgets('shows Frames tab label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      expect(find.text('Frames'), findsOneWidget);
    });

    testWidgets('shows Stability tab label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      expect(find.text('Stability'), findsOneWidget);
    });

    testWidgets('PerfRadarScreen still works after refactor', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PerfRadarScreen()));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Perf Radar'), findsOneWidget);
    });
  });
}
