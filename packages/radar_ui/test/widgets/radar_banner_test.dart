// test/widgets/radar_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarBanner', () {
    testWidgets('renders message and action', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarBanner(
              message: 'Module-only',
              severity: RadarSeverity.warning,
              action: Text('Add symbols'),
            ),
          ),
        ),
      );

      expect(find.text('Module-only'), findsOneWidget);
      expect(find.text('Add symbols'), findsOneWidget);
    });

    testWidgets('renders leading widget when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarBanner(message: 'Live', leading: Icon(Icons.circle)),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(RadarBanner),
          matching: find.byIcon(Icons.circle),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tints background using severity tokens', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarBanner(
              message: 'Critical issue',
              severity: RadarSeverity.critical,
            ),
          ),
        ),
      );

      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(RadarBanner),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, RadarSeverity.critical.tokens.rowBg);
    });
  });
}
