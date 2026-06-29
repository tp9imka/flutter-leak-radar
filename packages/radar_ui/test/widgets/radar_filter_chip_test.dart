// test/widgets/radar_filter_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarFilterChip', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarFilterChip(
              label: 'errors-only',
              selected: false,
              onSelected: () {},
            ),
          ),
        ),
      );
      expect(find.text('errors-only'), findsOneWidget);
    });

    testWidgets('active chip has accent background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarFilterChip(
              label: 'all',
              selected: true,
              onSelected: () {},
            ),
          ),
        ),
      );

      // Find the DecoratedBox that paints the chip background.
      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(RadarFilterChip),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      // Active chip fills with accentSubtle or accent-derived color.
      expect(decoration.color, RadarColors.accentSubtle);
    });

    testWidgets('inactive chip has bgInput background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarFilterChip(
              label: 'hot/dup',
              selected: false,
              onSelected: () {},
            ),
          ),
        ),
      );
      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(RadarFilterChip),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      expect(decoration.color, RadarColors.bgInput);
    });

    testWidgets('onSelected fires when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarFilterChip(
              label: 'growth',
              selected: false,
              onSelected: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(RadarFilterChip));
      expect(tapped, isTrue);
    });
  });
}
