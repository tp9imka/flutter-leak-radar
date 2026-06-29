// test/widgets/radar_sort_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarSortHeader', () {
    Widget buildHeader({
      String activeSortKey = '',
      RadarSortDirection direction = RadarSortDirection.descending,
      void Function(String, RadarSortDirection)? onSort,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: RadarSortHeader(
            label: 'avg',
            sortKey: 'avg',
            activeSortKey: activeSortKey,
            direction: direction,
            onSort: onSort ?? (_, __) {},
          ),
        ),
      );
    }

    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(buildHeader());
      expect(find.text('avg'), findsOneWidget);
    });

    testWidgets(
        'active column shows descending arrow ↓ in accent color',
        (tester) async {
      await tester.pumpWidget(
        buildHeader(
          activeSortKey: 'avg',
          direction: RadarSortDirection.descending,
        ),
      );
      // Arrow glyph must appear.
      expect(find.text('↓'), findsOneWidget);
      // Arrow must be in accent green.
      final arrowText = tester.widget<Text>(find.text('↓'));
      expect(arrowText.style?.color, RadarColors.accent);
    });

    testWidgets(
        'active column shows ascending arrow ↑ in accent color',
        (tester) async {
      await tester.pumpWidget(
        buildHeader(
          activeSortKey: 'avg',
          direction: RadarSortDirection.ascending,
        ),
      );
      expect(find.text('↑'), findsOneWidget);
      final arrowText = tester.widget<Text>(find.text('↑'));
      expect(arrowText.style?.color, RadarColors.accent);
    });

    testWidgets('inactive column shows no arrow', (tester) async {
      await tester.pumpWidget(
        buildHeader(activeSortKey: 'count'),
      );
      expect(find.text('↓'), findsNothing);
      expect(find.text('↑'), findsNothing);
    });

    testWidgets('tap toggles direction when already active', (tester) async {
      String? gotKey;
      RadarSortDirection? gotDir;
      await tester.pumpWidget(
        buildHeader(
          activeSortKey: 'avg',
          direction: RadarSortDirection.descending,
          onSort: (k, d) {
            gotKey = k;
            gotDir = d;
          },
        ),
      );
      await tester.tap(find.byType(RadarSortHeader));
      expect(gotKey, 'avg');
      expect(gotDir, RadarSortDirection.ascending);
    });

    testWidgets('tap sets descending when column becomes active',
        (tester) async {
      String? gotKey;
      RadarSortDirection? gotDir;
      await tester.pumpWidget(
        buildHeader(
          activeSortKey: 'count', // different key
          direction: RadarSortDirection.descending,
          onSort: (k, d) {
            gotKey = k;
            gotDir = d;
          },
        ),
      );
      await tester.tap(find.byType(RadarSortHeader));
      expect(gotKey, 'avg');
      expect(gotDir, RadarSortDirection.descending);
    });
  });
}
